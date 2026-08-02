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
        perFileFolder: Bool = false,
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
            if perFileFolder { destination = destination.folder(stem) }
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
        perFileFolder: Bool = false,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?,
        artifacts: (File, String) throws -> [FileData]
    ) throws {
        let stem = file.fileName.withoutExtensions
        let destination = perFileFolder ? outputFolder.folder(stem) : outputFolder
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
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?,
        binaries: (File, String) throws -> [FileData]
    ) throws {
        let inputs = fileSystem.scan(folder, matches: predicate)
        logger?.log(.info("Building \(inputs.count) \(label) file(s)"))

        for scanned in inputs {
            let stem = stemOf(scanned.file)
            let destination = outputFolder.folder(scanned.relativeFolder.path)
            let built = try binaries(scanned.file, stem)
            for binary in built {
                let outFile = destination.file(binary.file.fileName)
                if overwrite || fileSystem.inspectFile(at: outFile) == nil {
                    try fileSystem.writeFile(binary.data, at: outFile, overwrite: overwrite)
                }
            }
            logger?.log(.info("  \(stem) → \(built.map(\.file.fileName).joined(separator: ", "))"))
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
