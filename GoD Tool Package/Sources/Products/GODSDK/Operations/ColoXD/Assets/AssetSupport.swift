//
//  AssetSupport.swift
//  GODOps
//
//  Shared plumbing for the per-format asset operations in this folder.
//
//  Each format gets its own operations — `dumpFonts`, `buildATX` and so on —
//  because each is a different job with a different config shape, and a caller
//  reading a config should see the format it is asking for. What they have in
//  common is not the *job* but the mechanics around it: walking a folder,
//  mirroring its layout into the output, writing the artifacts, and reporting
//  what failed instead of abandoning the batch. That lives here so the
//  operations stay short enough to read.
//

import Foundation
import GoDFoundation
import GeniusSonority

/// Where a format's artifacts sit under the source folder.
///
/// Some formats name their companion files after something *inside* the
/// asset — a GSW's textures are named by tag id, an ATX's frames are
/// numbered from zero — so two of them dumped side by side would overwrite
/// each other. Those get a folder each.
///
/// This is one fact about the format, and it belongs in one place because
/// both directions have to agree on it: whatever the dump nests, the build
/// has to un-nest. When only the dump knew, `buildFlashMenus` wrote
/// `<out>/French/title_fr_010/title_fr_010.gsw` — one level below the
/// game-side file it was meant to replace — so 167 of XD PAL's 168 rebuilt
/// menus sat in folders the packer never looks in, and every menu edit was
/// silently dropped while the run reported success.
enum AssetLayout {
    /// Artifacts sit directly in the mirrored folder:
    /// `<root>/<language>/<stem>.json`.
    case flat
    /// Artifacts sit in a folder of their own, named after the asset:
    /// `<root>/<language>/<stem>/<stem>.json`.
    case perAssetFolder
}

extension ColoXD {

    // MARK: - Batch dumping

    /// Walks `folder` for files matching `predicate` and dumps each one.
    ///
    /// `artifacts` is the only per-format part: given an input file and its
    /// stem, produce the editable files to write. Everything else — mirroring
    /// language subfolders (`French/`, `German/`, …) into the output, giving
    /// formats with companion assets their own subfolder, and counting
    /// failures — is the same whatever the format.
    static func dumpBatch(
        in folder: Folder,
        matching predicate: (File) -> Bool,
        label: String,
        outputFolder: Folder,
        layout: AssetLayout = .flat,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?,
        artifacts: (File, String) throws -> [FileData]
    ) throws {
        let inputs = fileSystem.scan(folder, matches: predicate)
        logger?.log(.info("Found \(inputs.count) \(label) file(s)"))

        var skipped = 0
        for scanned in inputs {
            let stem = scanned.file.fileName.withoutExtensions
            var destination = outputFolder.folder(scanned.relativeFolder.path)
            if case .perAssetFolder = layout { destination = destination.folder(stem) }
            do {
                try writeArtifacts(
                    try artifacts(scanned.file, stem),
                    into: destination,
                    stem: stem,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )
            } catch {
                // One unparseable asset shouldn't abandon the batch, but the
                // run has to say how many it gave up on — a silent skip looks
                // identical to a clean pass.
                skipped += 1
                logger?.log(.warning("Failed to dump \(label) \(scanned.file.fileName): \(error)"))
            }
        }

        if skipped > 0 {
            logger?.log(.warning("Skipped \(skipped) of \(inputs.count) \(label) file(s)"))
        }
    }

    /// Single-file counterpart to `dumpBatch`. A failure here is the whole
    /// operation, so it propagates rather than being counted.
    static func dumpSingle(
        file: File,
        outputFolder: Folder,
        layout: AssetLayout = .flat,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?,
        artifacts: (File, String) throws -> [FileData]
    ) throws {
        let stem = file.fileName.withoutExtensions
        let destination: Folder
        switch layout {
        case .flat:           destination = outputFolder
        case .perAssetFolder: destination = outputFolder.folder(stem)
        }
        try writeArtifacts(
            try artifacts(file, stem),
            into: destination,
            stem: stem,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger
        )
    }

    private static func writeArtifacts(
        _ artifacts: [FileData],
        into destination: Folder,
        stem: String,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try fileSystem.createFolder(at: destination, overwrite: overwrite)
        for artifact in artifacts {
            try fileSystem.writeFile(
                artifact.data,
                at: resolveArtifact(artifact.file, in: destination),
                overwrite: overwrite
            )
        }
        logger?.log(.info("  \(stem): \(artifacts.count) artifact(s) → \(destination.path)"))
    }

    // MARK: - Batch building

    /// Walks `folder` for manifests matching `predicate` and rebuilds each.
    ///
    /// `binaries` returns the game-side files for one manifest; they are
    /// written into the output folder with the input's directory layout
    /// mirrored, the same way `dumpBatch` mirrors it on the way out.
    static func buildBatch(
        in folder: Folder,
        matching predicate: (File) -> Bool,
        stem stemOf: (File) -> String,
        label: String,
        outputFolder: Folder,
        layout: AssetLayout = .flat,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?,
        binaries: (File, String) throws -> [FileData]
    ) throws {
        let inputs = fileSystem.scan(folder, matches: predicate)
        logger?.log(.info("Building \(inputs.count) \(label) file(s)"))

        // One asset that won't rebuild costs its own file, not the batch: the
        // game-side file it would have replaced is left as the dump wrote it,
        // which is valid. The run still fails at the end naming everything
        // that needs fixing — the same policy as an FSYS pack — rather than
        // stopping at the first one, which is how a single bad font atlas
        // used to leave 103 of Colosseum JP's 137 fonts unbuilt.
        var failures = [String]()
        for scanned in inputs {
            let stem = stemOf(scanned.file)
            let destination = buildDestination(
                mirroring: scanned.relativeFolder, under: outputFolder, layout: layout
            )
            do {
                let built = try binaries(scanned.file, stem)
                for binary in built {
                    let outFile = destination.file(binary.file.fileName)
                    let existing = fileSystem.inspectFile(at: outFile)
                    // These operations replace files the dump unpacked, so an
                    // output path with nothing at it means the build and the
                    // dump disagree about where the game-side file lives, and
                    // what gets written will never reach the packer. That is
                    // what the per-asset-folder bug looked like from the
                    // outside: a clean run, 167 new files, nothing rebuilt.
                    if existing == nil {
                        logger?.log(.warning(
                            "\(label) \(stem): nothing at \(outFile.path) to replace — "
                                + "writing it there anyway, but check the output folder is right"
                        ))
                    }
                    if overwrite || existing == nil {
                        try fileSystem.writeFile(binary.data, at: outFile, overwrite: overwrite)
                    }
                }
                logger?.log(.info("  \(stem) → \(built.map(\.file.fileName).joined(separator: ", "))"))
            } catch {
                failures.append(scanned.file.fileName)
                logger?.log(.warning("Failed to build \(label) \(scanned.file.fileName): \(error)"))
            }
        }

        if !failures.isEmpty {
            throw AssetBatchError.buildFailures(label: label, names: failures, total: inputs.count)
        }
    }

    // MARK: - Manifest helpers

    /// Reads a manifest and the companion files it names, in the shape the
    /// `FileFormat.init(outputs:)` initializers expect.
    static func artifactBundle(
        manifest: File,
        companions: (GoDData, Folder) -> [String],
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let manifestData = fileSystem.readFile(at: manifest)?.allData,
              let baseFolder = manifest.parentFolder else {
            throw FSTErrors.fileNotFound(manifest, .init())
        }
        var outputs = [FileData(file: File(manifest.fileName), data: manifestData)]
        for relative in companions(manifestData, baseFolder) {
            let file = resolveRelativeFile(relative, in: baseFolder)
            guard let data = fileSystem.readFile(at: file)?.allData else {
                throw FSTErrors.fileNotFound(file, .init())
            }
            outputs.append(FileData(file: File(relative), data: data))
        }
        return outputs
    }

    /// Stem of the asset a compound-suffixed manifest belongs to
    /// (`absol.atx.json` -> `absol`).
    static func stem(of manifest: File, droppingSuffix suffix: String) -> String {
        let name = manifest.fileName
        if !suffix.isEmpty, name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name.withoutExtensions
    }

    /// Where a rebuilt binary goes, given where its manifest was found.
    ///
    /// Under `.perAssetFolder` the dump put the manifest in a folder of its
    /// own, and the game-side file it replaces sits *beside* that folder, so
    /// the last component is dropped. The drop is unconditional rather than
    /// matched against the stem: the folder is only ever a container, so a
    /// renamed one should still resolve to the file the manifest names.
    private static func buildDestination(
        mirroring relativeFolder: Folder,
        under outputFolder: Folder,
        layout: AssetLayout
    ) -> Folder {
        guard case .perAssetFolder = layout else {
            return outputFolder.folder(relativeFolder.path)
        }
        let components = relativeFolder.path
            .split(separator: "/")
            .map(String.init)
            .filter { $0 != "." }
        let parent = components.dropLast()
        guard !parent.isEmpty else { return outputFolder }
        return outputFolder.folder(parent.joined(separator: "/"))
    }

    /// Places an artifact's (possibly nested) relative path under `folder`.
    private static func resolveArtifact(_ relative: File, in folder: Folder) -> File {
        var path = relative.path
        if path.hasPrefix("/") { path.removeFirst() }
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return folder.file(path) }
        var current = folder
        for part in parts.dropLast() { current = current.folder(part) }
        return current.file(last)
    }
}

/// What a batch operation couldn't do, reported once at the end.
public enum AssetBatchError: Error, CustomStringConvertible {
    /// Batch members that failed to rebuild. Everything else was written.
    case buildFailures(label: String, names: [String], total: Int)

    public var description: String {
        switch self {
        case let .buildFailures(label, names, total):
            let listed = names.prefix(8).joined(separator: ", ")
            let rest = names.count > 8 ? ", … (\(names.count - 8) more)" : ""
            return "Error: \(names.count) of \(total) \(label) file(s) couldn't be built: \(listed)\(rest)"
        }
    }
}
