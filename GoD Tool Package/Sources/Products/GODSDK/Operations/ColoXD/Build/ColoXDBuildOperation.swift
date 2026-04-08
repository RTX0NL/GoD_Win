import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import GTX

extension ColoXD {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildColosseum(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try buildColosseumXD(
                    fileSystem: fileSystem,
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    dolphinEngine: dolphinEngine,
                    gsEngine: gsEngine,
                    logger: logger
                )

            case let .buildXD(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try buildColosseumXD(
                    fileSystem: fileSystem,
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    dolphinEngine: dolphinEngine,
                    gsEngine: gsEngine,
                    logger: logger
                )

            case let .packFSYS(registryFile, outputFile, sourceFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                logger?.log(.info("Packing FSYS archive from \(registryFile.fileName) entries)"))

                let archiveData = try packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    gsEngine: gsEngine,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(archiveData.data, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(archiveData.data.length) bytes)"))
                }

            case let .buildFont(metadataFile, atlasFile, outputFile, overwrite):
                guard let metaData = fileSystem.readFile(at: metadataFile) else {
                    throw FSTErrors.fileNotFound(metadataFile, .init())
                }
                guard let imageData = fileSystem.readFile(at: atlasFile) else {
                    throw FSTErrors.fileNotFound(atlasFile, .init())
                }

                let metadata: GSFontAtlas.Metadata = try JSONDecoder().decode(
                    GSFontAtlas.Metadata.self, from: metaData
                )
                let font = try GSFontAtlas.importAtlas(imageData: imageData, metadata: metadata)
                let fontData = try font.data

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(fontData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Built font \(outputFile.fileName) (\(font.visibleGlyphs.count) glyphs, \(fontData.length) bytes)"))
                }
            }
        }
    }

    // MARK: - Core FSYS packing

    /// Packs a single FSYS archive from its registry and resolved entry file data.
    private static func packFSYS(
        registry: FSYSRegistry,
        entryFiles: [FileData],
        gsEngine: GeniusSonorityEngine
    ) throws -> FSYSArchive {
        let entries = zip(registry.entries, entryFiles).map { registryEntry, fileData in
            FSYSArchive.Entry(
                metadata: registryEntry.metadata,
                filename: fileData.fileName,
                data: fileData.data
            )
        }

        return FSYSArchive(metadata: registry.metaData, entries: entries)
    }

    /// Reads a registry JSON and its entry files from the filesystem, packs into an FSYS archive.
    /// Pure function safe for concurrent use.
    private static func packFSYSFromRegistry(
        registryFile: File,
        sourceFolder: Folder,
        gsEngine: GeniusSonorityEngine,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryFile)

        let entryFiles = try registry.entries.map { registryEntry -> FileData in
            let filePath = sourceFolder.file(registryEntry.file.path)
            guard let data = fileSystem.readFile(at: filePath) else {
                throw FSTErrors.fileNotFound(filePath, .init())
            }
            var entryData = data
            // Re-encode PNG back to GTX if texture metadata is present
            if filePath.fileType == "png", let texMeta = registryEntry.textureMetadata {
                let decoder = GXTextureDecoder()
                if let image = GoDImage.fromPNG(data),
                   let gtxData = decoder.encode(image: image, metadata: texMeta) {
                    entryData = gtxData
                }
            }
            let filename = registryEntry.metadata.name + "." + registryEntry.metadata.fileType
            return FileData(fileName: filename, data: entryData)
        }

        let archiveData = try packFSYS(registry: registry, entryFiles: entryFiles, gsEngine: gsEngine)
        let fsysFileName = registryFile.fileName.withoutExtension
        return FileData(fileName: fsysFileName, data: try archiveData.data(groupID: registry.groupID, engine: gsEngine))
    }

    // MARK: - Build all FSYS archives from an unpacked project

    private static func buildColosseumXD(
        fileSystem: FileSystemTree,
        fstRegistryFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        logger: Logger? = nil
    ) throws {
        guard let sourceFolder = fstRegistryFile.parentFolder else {
            throw FSTErrors.fileNotFound(fstRegistryFile, .init())
        }
        let fstRegistry: FSTRegistry = try fileSystem.decodeJSON(from: fstRegistryFile)

        logger?.log(.info("Building Colosseum/XD File System"))
        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .started))

        let fsysEntries = fstRegistry.entries.filter { $0.type == .fsys }
        let binaryEntries = fstRegistry.entries.filter { $0.type == .binary }
        let totalCount = fsysEntries.count + binaryEntries.count

        // Phase 1: Copy non-FSYS binary files to output
        for (i, entry) in binaryEntries.enumerated() {
            let sourcePath = sourceFolder.file(entry.file.path)
            guard let data = fileSystem.readFile(at: sourcePath) else {
                throw FSTErrors.fileNotFound(sourcePath, .init())
            }
            let outputFile = outputFolder.file("files/" + entry.file.fileName)
            if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                fileSystem.writeFile(data, at: outputFile, overwrite: overwrite)
            }

            let percent = Int(Double(i + 1) / Double(totalCount) * 100)
            if percent > 0 {
                logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
            }
        }

        // Phase 2: Pack FSYS archives concurrently
        var fsysResults = [Result<FileData, Error>?](repeating: nil, count: fsysEntries.count)
        let progressLock = NSLock()
        var fsysProcessed = 0
        var lastReportedPercent = Int(Double(binaryEntries.count) / Double(totalCount) * 100)

        DispatchQueue.concurrentPerform(iterations: fsysEntries.count) { i in
            let entry = fsysEntries[i]
            let registryFile = sourceFolder.file(entry.file.path)

            do {
                fsysResults[i] = .success(try packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    gsEngine: gsEngine,
                    fileSystem: fileSystem
                ))
            } catch {
                fsysResults[i] = .failure(error)
            }

            if let logger {
                progressLock.lock()
                fsysProcessed += 1
                let processed = binaryEntries.count + fsysProcessed
                let percent = Int(min(Double(processed) / Double(totalCount) * 100, 100))
                if percent > lastReportedPercent {
                    lastReportedPercent = percent
                    logger.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
                }
                progressLock.unlock()
            }
        }

        // Write packed archives to output
        for result in fsysResults {
            guard let result else { continue }
            switch result {
            case .success(let packed):
                let outputFile = outputFolder.file("files/" + packed.fileName)
                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(packed.data, at: outputFile, overwrite: overwrite)
                }
            case .failure(let error):
                throw error
            }
        }

        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .completed(true)))
    }
}
