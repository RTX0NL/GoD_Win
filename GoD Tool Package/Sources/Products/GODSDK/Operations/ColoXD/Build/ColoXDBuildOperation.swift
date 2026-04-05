import GoDFoundation
import GoDEngine
import GeniusSonority

extension ColoXD {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .packFSYS(registryFile, outputFile, sourceFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let registryData = fileSystem.readFile(at: registryFile) else {
                    throw FSTErrors.fileNotFound(registryFile, .init())
                }
                let registry: FSYSRegistry = try JSONDecoder().decode(FSYSRegistry.self, from: registryData)

                logger?.log(.info("Packing FSYS archive from \(registryFile.fileName) (\(registry.entries.count) entries)"))

                var entries = [FSYSArchive.Entry]()
                for registryEntry in registry.entries {
                    let filePath = sourceFolder.file(registryEntry.file.path)
                    guard let data = fileSystem.readFile(at: filePath) else {
                        throw FSTErrors.fileNotFound(filePath, .init())
                    }
                    let filename = registryEntry.metadata.name
                        + (registryEntry.metadata.fileType.isEmpty ? "" : ".\(registryEntry.metadata.fileType)")
                    entries.append(FSYSArchive.Entry(
                        metadata: registryEntry.metadata,
                        filename: filename,
                        data: data
                    ))
                }

                let archive = FSYSArchive(metadata: registry.metaData, entries: entries)
                let archiveData = try archive.data(groupID: registry.groupID, engine: gsEngine)

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(archiveData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(archiveData.length) bytes)"))
                }
            }
        }
    }
}
