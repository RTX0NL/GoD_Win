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

            case let .unpackFSYS(fsysFile, outputFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let data = fileSystem.readFile(at: fsysFile) else {
                    throw FSTErrors.fileNotFound(fsysFile, .init())
                }

                let archive = try FSYSArchive(data: data, engine: gsEngine)
                let archiveName = fsysFile.fileName.withoutExtensions

                logger?.log(.info("Unpacking FSYS archive: \(fsysFile.fileName) (\(archive.entries.count) entries)"))

                // Build registry and extract files
                var registryEntries = [FSYSRegistry.Entry]()
                for entry in archive.entries {
                    let targetFile = outputFolder.file(entry.filename)
                    registryEntries.append(.init(metadata: entry.metadata, file: targetFile))
                    if overwrite || fileSystem.inspectFile(at: targetFile) == nil {
                        fileSystem.writeFile(entry.data, at: targetFile, overwrite: overwrite)
                    }
                }

                let registry = FSYSRegistry(
                    groupID: archive.groupID,
                    metaData: archive.metaData,
                    entries: registryEntries
                )
                let registryFile = outputFolder.file(archiveName + ".json")
                try fileSystem.encodeJSON(registry, to: registryFile, overwrite: overwrite)

                logger?.log(.info("Wrote registry: \(registryFile.fileName)"))
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
    
    /// Result of processing a single FSYS archive
    private struct FsysResult {
        let registry: FSYSRegistry
        let registryFile: File
        let extractedFiles: [(file: File, data: GoDData)]
    }

    /// Processes a single FSYS archive (parsing + LZSS decompression).
    /// Pure function with no side effects — safe to call from any thread.
    private static func processFsys(
        data: GoDData,
        fileName: String,
        toc: FsysTOC,
        gsEngine: GeniusSonorityEngine
    ) throws -> FsysResult {
        let archive = try FSYSArchive(data: data, engine: gsEngine)
        let archiveName = fileName.withoutExtensions
        let groupID = archive.groupID != 0 ? archive.groupID : (toc.fsysID(for: archiveName) ?? 0)

        var entries = [FSYSRegistry.Entry]()
        var extractedFiles = [(file: File, data: GoDData)]()

        for entry in archive.entries {
            let targetFolder = gsEngine.resolveFolder(
                forFileType: entry.metadata.fileType,
                entryFilename: entry.filename,
                archiveName: archiveName
            )
            let targetFile = targetFolder.file(entry.filename)
            entries.append(.init(metadata: entry.metadata, file: targetFile))
            extractedFiles.append((file: targetFile, data: entry.data))
        }

        let registry = FSYSRegistry(
            groupID: groupID,
            metaData: archive.metaData,
            entries: entries
        )
        let registryFile = gsEngine.data.fsys.archivesFolder.file(fileName + ".json")

        return FsysResult(
            registry: registry,
            registryFile: registryFile,
            extractedFiles: extractedFiles
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
        outputFolders.insert(fsysConfig.archivesFolder)

        outputFolders.forEach { folder in
            _ = projectFileSystem.createFolder(at: folder, overwrite: true)
        }

        let gsfsysFile = rootFolder.file(gsEngine.data.fsys.GSfsysFile.path)
        guard let gsfsysData = fileSystem.readFile(at: gsfsysFile) else {
            throw ColoXDDumpErrors.missingToC(file: gsfsysFile, .init())
        }
        let toc = try FsysTOC(tocData: gsfsysData, engine: gsEngine)

        logger?.log(.info("Decoding Colosseum/XD File System"))
        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .started))

        // Phase 1: Collect file paths from the files/ subfolder only.
        // System files (boot.bin, main.dol, etc.) in sys/ are handled by the GameCube dump layer.
        let filesFolder = rootFolder.folder("files")

        var fsysPaths = [(path: File, data: GoDData)]()
        var otherPaths = [(path: File, data: GoDData)]()

        func collectPaths(folder: Folder) throws {
            guard let folderData = fileSystem.inspectFolder(at: folder) else {
                return
            }
            for path in folderData.files {
                guard let data = fileSystem.readFile(at: path) else { continue }
                if path.fileType == "fsys" {
                    fsysPaths.append((path: path, data: data))
                } else {
                    otherPaths.append((path: path, data: data))
                }
            }
            for subFolder in folderData.subFolders {
                try collectPaths(folder: subFolder)
            }
        }

        try collectPaths(folder: filesFolder)

        let totalCount = fsysPaths.count + otherPaths.count
        var fstEntries = [FSTRegistry.Entry]()

        // Phase 2: Write non-FSYS game files, routing by file type
        for other in otherPaths {
            let targetFolder = gsEngine.resolveFolder(
                forFileType: other.path.fileType,
                entryFilename: other.path.fileName,
                archiveName: ""
            )
            let outputFile = targetFolder.file(other.path.fileName)
            _ = projectFileSystem.writeFile(other.data, at: outputFile, overwrite: true)
            fstEntries.append(.init(type: .binary, file: outputFile))
        }

        // Phase 3: Process FSYS archives in parallel batches
        // Batch to limit memory: process N archives at a time
        let batchSize = max(1, ProcessInfo.processInfo.activeProcessorCount * 2)
        var fsysIndex = 0

        while fsysIndex < fsysPaths.count {
            let batchEnd = min(fsysIndex + batchSize, fsysPaths.count)
            let batch = Array(fsysPaths[fsysIndex..<batchEnd])

            var batchResults = [Result<FsysResult, Error>?](repeating: nil, count: batch.count)

            DispatchQueue.concurrentPerform(iterations: batch.count) { i in
                let source = batch[i]
                do {
                    batchResults[i] = .success(try processFsys(
                        data: source.data,
                        fileName: source.path.fileName,
                        toc: toc,
                        gsEngine: gsEngine
                    ))
                } catch {
                    batchResults[i] = .failure(error)
                }
            }

            // Merge batch results into the InMemoryFST
            for result in batchResults {
                guard let result else { continue }
                switch result {
                case .success(let fsysResult):
                    for extracted in fsysResult.extractedFiles {
                        _ = projectFileSystem.writeFile(extracted.data, at: extracted.file, overwrite: true)
                    }
                    _ = projectFileSystem.writeFile(fsysResult.registry, at: fsysResult.registryFile, overwrite: true)
                    fstEntries.append(.init(type: .fsys, file: fsysResult.registryFile))
                case .failure(let error):
                    throw error
                }
            }

            fsysIndex = batchEnd

            if logger != nil {
                let processed = otherPaths.count + fsysIndex
                let percentage = Percentage(min(Double(processed) / Double(totalCount) * 100, 100))
                logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .progress(percentage)))
            }
        }

        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .completed(true)))

        _ = projectFileSystem.writeFile(
            FSTRegistry(entries: fstEntries),
            at: Folder("/").file("FST.json"),
            overwrite: true
        )

        return projectFileSystem
    }
    
}
