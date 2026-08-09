import GoDFoundation
import Nintendo

/// Thin wrappers over `NintendoEngine`'s unpack/pack. Everything about the
/// archive — its format, its byte order, the order of its entries — comes
/// from the file itself on the way out and from the manifest on the way
/// back, so these ops only decide *which* files to process and where the
/// results go.

extension NintendoArchiveDump {

    static func dump(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let engine = try loadEngine(config.nintendoEngine, fileSystem: fileSystem)
        guard let data = fileSystem.readFile(at: config.archivePath)?.allData else {
            throw FSTErrors.fileNotFound(config.archivePath, .init())
        }
        try engine.unpackArchive(
            data: data,
            archiveName: config.archivePath.fileName,
            into: config.outputFolder,
            fileSystem: fileSystem,
            overwrite: config.overwrite,
            logger: logger
        )
    }

    static func dump(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let engine = try loadEngine(config.nintendoEngine, fileSystem: fileSystem)
        let candidates = collectFiles(
            in: config.archivesFolder, recursive: config.recursive, fileSystem: fileSystem
        )

        var unpacked = 0
        var skipped = 0
        for file in candidates {
            // Identify by magic, not by extension: the point of the
            // discriminator is that the file says what it is. A file that
            // isn't an archive is skipped silently — a bulk dump is
            // expected to be pointed at a mixed folder.
            guard let data = fileSystem.readFile(at: file)?.allData,
                  let signature = NintendoArchiveSignature.detect(data) else {
                skipped += 1
                continue
            }
            guard matches(config.filter, signature: signature, file: file) else {
                skipped += 1
                continue
            }
            // One subfolder per archive keeps two archives holding the same
            // internal filename from overwriting each other.
            try engine.unpackArchive(
                data: data,
                archiveName: file.fileName,
                into: config.outputFolder.folder(file.fileName),
                fileSystem: fileSystem,
                overwrite: config.overwrite,
                logger: logger
            )
            unpacked += 1
        }

        logger?.log(.info("Nintendo archives: unpacked \(unpacked), skipped \(skipped)"))
    }

    private static func matches(
        _ filter: Filter, signature: NintendoArchiveSignature, file: File
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .onlyFormats(let formats):
            return formats.contains { $0.lowercased() == signature.format.rawValue }
        case .onlyExtensions(let extensions):
            guard let ext = file.fileType?.lowercased() else { return false }
            return extensions.contains { $0.lowercased() == ext }
        }
    }
}

extension NintendoArchiveBuild {

    static func build(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let engine = try loadEngine(config.nintendoEngine, fileSystem: fileSystem)
        let registry: NintendoArchiveRegistry = try fileSystem.decodeJSON(from: config.manifestPath)
        let packed = try engine.packArchive(manifestFile: config.manifestPath, fileSystem: fileSystem)

        let destination = config.outputPath
            ?? (config.manifestPath.parentFolder ?? Folder("/")).file(registry.archiveName)
        try fileSystem.writeFile(packed, at: destination, overwrite: config.overwrite)
        logger?.log(.info("Packed \(registry.archiveName) (\(packed.length) bytes)"))
    }

    static func build(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let engine = try loadEngine(config.nintendoEngine, fileSystem: fileSystem)
        let candidates = collectFiles(
            in: config.inputFolder, recursive: config.recursive, fileSystem: fileSystem
        )

        var packed = 0
        for file in candidates where file.fileType?.lowercased() == "json" {
            // Any JSON in the tree could be something else's manifest, so
            // decoding is the filter: one that isn't ours is skipped.
            guard let registry: NintendoArchiveRegistry = try? fileSystem.decodeJSON(from: file) else {
                continue
            }
            let data = try engine.packArchive(manifestFile: file, fileSystem: fileSystem)
            let destination = config.outputFolder.file(registry.archiveName)
            try fileSystem.writeFile(data, at: destination, overwrite: config.overwrite)
            packed += 1
        }

        logger?.log(.info("Nintendo archives: packed \(packed)"))
    }
}

// MARK: - Shared helpers

private func loadEngine(_ folder: Folder?, fileSystem: FileSystemTree) throws -> NintendoEngine {
    guard let folder else { return try NintendoEngine.defaults() }
    return try NintendoEngine(from: folder, in: fileSystem)
}

/// Every regular file under `folder`, optionally descending. Order is
/// stable so a bulk run reports the same sequence every time.
private func collectFiles(
    in folder: Folder, recursive: Bool, fileSystem: FileSystemTree
) -> [File] {
    guard let contents = fileSystem.inspectFolder(at: folder) else { return [] }
    var found = contents.files.sorted { $0.path < $1.path }
    guard recursive else { return found }
    for sub in contents.subFolders.sorted(by: { $0.path < $1.path }) {
        found += collectFiles(in: sub, recursive: true, fileSystem: fileSystem)
    }
    return found
}
