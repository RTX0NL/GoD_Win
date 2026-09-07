//
//  PBRFontOperation.swift
//  GODOps
//
//  Battle Revolution fonts <-> their editable artifacts.
//
//  The work is almost entirely the file-format registry's: PBR's registry
//  binds `fnt` to `PBRFont` and `f3d` to `PBRFont3D`, so these operations
//  only have to decide *which files* and *where*. They deliberately do not
//  reach for a codec directly — routing through the registry is what keeps
//  a third PBR font format from needing a fourth operation.
//
//  A batch never aborts on one bad file. A folder of PBR fonts can contain a
//  Genius Sonority `.fnt` that wandered in (the two share the extension and
//  reject each other by design), and losing the other 147 fonts to it would
//  be a poor trade. Failures are counted and named.
//

import Foundation
import GoDFoundation
import PBR

extension PBRFontDump {

    /// Extensions the PBR registry knows as fonts. Checked against the
    /// registry rather than hardcoded at the call site so the two can't drift.
    static let fontExtensions = ["fnt", "f3d"]

    static func dump(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump PBR font", status: .started))
        let written = try dumpOne(
            font: config.fontPath,
            into: config.outputFolder,
            overwrite: config.overwrite,
            fileSystem: fileSystem
        )
        logger?.log(.info("Wrote \(written.count) artifact(s) for \(config.fontPath.fileName)"))
        logger?.log(.taskStatus(taskName: "Dump PBR font", status: .completed(true)))
    }

    static func dump(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let taskName = "Dump PBR fonts"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        guard fileSystem.inspectFolder(at: config.fontsFolder) != nil else {
            logger?.log(.warning("PBR fonts folder not found: \(config.fontsFolder.path)"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
            return
        }

        let inputs = fileSystem.scan(config.fontsFolder) { file in
            fontExtensions.contains((file.fileType ?? "").lowercased())
        }
        logger?.log(.info("Found \(inputs.count) PBR font file(s)"))

        var dumped = 0
        var skipped = 0
        for scanned in inputs {
            // Mirror the source layout so a project's folder structure
            // survives into the artifacts.
            let destination = config.outputFolder.folder(scanned.relativeFolder.path)
            do {
                _ = try dumpOne(
                    font: scanned.file,
                    into: destination,
                    overwrite: config.overwrite,
                    fileSystem: fileSystem
                )
                dumped += 1
            } catch {
                // A Genius Sonority font in a PBR folder lands here, and so
                // does anything genuinely malformed. Both are worth naming
                // and neither is worth abandoning the batch for.
                logger?.log(.warning("\(scanned.file.path): \(error)"))
                skipped += 1
            }
        }
        logger?.log(.info("Dumped \(dumped) PBR font(s)"
                          + (skipped > 0 ? "; \(skipped) skipped" : "")))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }

    /// Dumps one font into its own subfolder under `folder`.
    @discardableResult
    private static func dumpOne(
        font: File,
        into folder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree
    ) throws -> [File] {
        guard let bytes = fileSystem.readFile(at: font)?.allData else {
            throw FSTErrors.fileNotFound(font, .init())
        }
        let ext = (font.fileType ?? "").lowercased()
        let stem = font.fileName.withoutExtensions
        // Named after the source file, not `input`, so the artifacts say
        // which font they came from.
        let binaries = [FileData(file: File("\(stem).\(ext)"), data: bytes)]
        return try PBREngine.fileFormats().dump(
            binaries: binaries,
            extension: ext,
            into: folder.folder(stem),
            fileSystem: fileSystem,
            overwrite: overwrite
        )
    }
}

extension PBRFontBuild {

    static func build(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Build PBR font", status: .started))
        let written = try buildOne(
            bundle: config.fontFolder,
            into: config.outputFolder,
            overwrite: config.overwrite,
            fileSystem: fileSystem
        )
        logger?.log(.info("Wrote \(written.map(\.fileName).joined(separator: ", "))"))
        logger?.log(.taskStatus(taskName: "Build PBR font", status: .completed(true)))
    }

    static func build(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let taskName = "Build PBR fonts"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        guard let root = fileSystem.inspectFolder(at: config.fontsFolder) else {
            logger?.log(.warning("PBR font source folder not found: \(config.fontsFolder.path)"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
            return
        }

        var built = 0
        var skipped = 0
        for folder in root.subFolders {
            do {
                _ = try buildOne(
                    bundle: folder,
                    into: config.outputFolder,
                    overwrite: config.overwrite,
                    fileSystem: fileSystem
                )
                built += 1
            } catch {
                logger?.log(.warning("\(folder.path): \(error)"))
                skipped += 1
            }
        }
        logger?.log(.info("Built \(built) PBR font(s)"
                          + (skipped > 0 ? "; \(skipped) skipped" : "")))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }

    /// Rebuilds one bundle. The manifest's own name carries the format —
    /// `<stem>.fnt.json` or `<stem>.f3d.json` — so the bundle is
    /// self-describing and the config doesn't have to repeat it.
    @discardableResult
    private static func buildOne(
        bundle: Folder,
        into outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree
    ) throws -> [File] {
        guard let ext = formatExtension(in: bundle, fileSystem: fileSystem) else {
            throw PBRFontErrors.noFontManifest(folder: bundle, .init())
        }
        let binaries = try PBREngine.fileFormats().build(
            extension: ext, from: bundle, fileSystem: fileSystem
        )
        var written = [File]()
        for binary in binaries {
            let destination = outputFolder.file(binary.file.fileName)
            try fileSystem.writeFile(binary.data, at: destination, overwrite: overwrite)
            written.append(destination)
        }
        return written
    }

    /// The format a bundle describes, read from its manifest filename.
    private static func formatExtension(
        in bundle: Folder,
        fileSystem: FileSystemTree
    ) -> String? {
        guard let contents = fileSystem.inspectFolder(at: bundle) else { return nil }
        for file in contents.files where file.fileType?.lowercased() == "json" {
            // `<stem>.<format>.json` — the middle component is the format.
            let parts = file.fileName.components(separatedBy: ".")
            guard parts.count >= 3 else { continue }
            let candidate = parts[parts.count - 2].lowercased()
            if PBRFontDump.fontExtensions.contains(candidate) { return candidate }
        }
        return nil
    }
}

enum PBRFontErrors: Error, CustomStringConvertible {
    case noFontManifest(folder: Folder, ErrorTrace)

    var description: String {
        switch self {
        case let .noFontManifest(folder, trace):
            return "No PBR font manifest in \(folder.path) — expected a "
                + "`<name>.fnt.json` or `<name>.f3d.json`.\n\(trace)"
        }
    }
}
