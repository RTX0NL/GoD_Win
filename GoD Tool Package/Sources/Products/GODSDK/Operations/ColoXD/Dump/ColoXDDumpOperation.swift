//
//  ColosseumXDDumpOperation.swift
//  
//
//  Created by Stars Momodu on 28/08/2024.
//

import GoDFoundation
import Dolphin
import GeniusSonority

extension ColoXD {
    /// Structural output folders for operation metadata (not file-type routing)
    private static let fsysRegistryFolder: Folder = "/Data/Archives"
    private static let dataFolder: Folder = "/Data"
    
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpColosseum(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
                
                let output = try dumpColosseum(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings,
                    logger: logger
                )
                
                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite)
            case let .dumpXD(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
                
                let output = try dumpXD(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings,
                    logger: logger
                )
                
                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite)
            }
        }
    }
    
    private static func dumpColosseum(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings,
            logger: logger
        )
    }
    
    private static func dumpXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings,
            logger: logger
        )
    }
    
    private static func dumpColosseumXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        
        let projectFileSystem = InMemoryFST()

        // Derive the set of output folders from engine config
        let fsysConfig = gsEngine.data.fsys
        var outputFolders = Set<Folder>()
        outputFolders.insert(fsysConfig.defaultFolder)
        outputFolders.formUnion(fsysConfig.fileTypeFolders.values)
        for overrideMap in fsysConfig.archiveFileTypeFolders.values {
            outputFolders.formUnion(overrideMap.values)
        }
        outputFolders.insert(fsysRegistryFolder)
        outputFolders.insert(dataFolder)

        outputFolders.forEach { folder in
            _ = projectFileSystem.createFolder(at: folder, overwrite: true)
        }

        let gsfsysFile = rootFolder.file(gsEngine.data.fsys.GSfsysFile)
        guard let gsfsysData = fileSystem.readFile(at: gsfsysFile) else {
            throw ColoXDDumpErrors.missingToC(file: gsfsysFile, .init())
        }
        let toc = try FsysTOC(tocData: gsfsysData, engine: gsEngine)
        var fstEntries = [FSTRegistry.Entry]()

        var totalFileCount = 0
        var filesProcessed = 0
        var shouldTrackProgress = false
        if logger != nil {
            func countFiles(_ folder: Folder) -> Int {
                guard let info = fileSystem.inspectFolder(at: folder) else {
                    return 0
                }
                var count = info.files.count
                info.subFolders.forEach { count += countFiles($0) }
                return count
            }

            totalFileCount = countFiles(rootFolder)
            shouldTrackProgress = totalFileCount > 0
        }

        func dump(folder: Folder) throws {
            guard let folderData = fileSystem.inspectFolder(at: folder) else {
                throw FSTErrors.folderNotFound(folder, .init())
            }

            try folderData.files.forEach { path in
                guard let file = fileSystem.readFile(at: path) else { return }
                let fileName = path.fileName
                let groupID = toc.fsysID(for: fileName.withoutExtensions) ?? 0

                switch path.fileType {
                case "fsys":
                    let archive = try FSYSArchive(data: file, engine: gsEngine)
                    let archiveName = fileName.withoutExtensions

                    var entries = [FSYSRegistry.Entry]()

                    archive.entries.forEach { entry in
                        let targetFolder = gsEngine.resolveFolder(
                            forFileType: entry.metadata.fileType,
                            entryFilename: entry.filename,
                            archiveName: archiveName
                        )

                        let targetFile = targetFolder.file(entry.filename)
                        entries.append(
                            .init(
                                metadata: entry.metadata,
                                file: targetFile
                            )
                        )
                        _ = projectFileSystem.writeFile(
                            entry.data,
                            at: targetFile,
                            overwrite: true
                        )
                    }

                    let registry = FSYSRegistry(
                        groupID: groupID,
                        metaData: archive.metaData,
                        entries: entries
                    )

                    let registryFile = fsysRegistryFolder.file(fileName + ".json")
                    _ = projectFileSystem.writeFile(
                        registry,
                        at: registryFile,
                        overwrite: true
                    )
                    fstEntries.append(.init(type: .fsys, file: registryFile))

                default:
                    let outputFile = fsysConfig.defaultFolder.file(fileName)
                    _ = projectFileSystem.writeFile(
                        file,
                        at: outputFile,
                        overwrite: true
                    )
                    fstEntries.append(.init(type: .binary, file: outputFile))
                }

                if shouldTrackProgress {
                    filesProcessed += 1
                    let percentage = Percentage(min(Double(filesProcessed) / Double(totalFileCount) * 100, 100))
                    logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .progress(percentage)))
                }
            }

            try folderData.subFolders.forEach(dump)
        }

        logger?.log(.info("Decoding Colosseum/XD File System"))
        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .started))

        try dump(folder: rootFolder)

        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .completed(true)))

        _ = projectFileSystem.writeFile(
            FSTRegistry(entries: fstEntries),
            at: dataFolder.file("FST.json"),
            overwrite: true
        )

        return projectFileSystem
    }
    
}
