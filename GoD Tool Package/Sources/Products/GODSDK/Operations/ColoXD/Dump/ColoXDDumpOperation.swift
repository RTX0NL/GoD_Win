//
//  ColosseumXDDumpOperation.swift
//  
//
//  Created by Stars Momodu on 28/08/2024.
//

import GoDFoundation
import Dolphin
import GeniusSonority
import GTX

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

                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)
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

                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)

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
                    let targetFolder = gsEngine.resolveFolder(
                        forFileType: entry.metadata.fileType,
                        entryFilename: entry.filename,
                        archiveName: archiveName
                    ).resolvedFolder
                    let targetFile = targetFolder.file(entry.filename)
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

            case let .dumpFonts(fontsFolder, outputFolder, overwrite):
                // Find all .fnt files in the fonts folder
                guard let contents = fileSystem.inspectFolder(at: fontsFolder) else { break }
                let fntFiles = contents.files.filter { $0.fileType == "fnt" }
                logger?.log(.info("Found \(fntFiles.count) font files"))

                for fntFile in fntFiles {
                    guard let data = fileSystem.readFile(at: fntFile) else { continue }
                    guard let font = try? GSFont(data: data) else {
                        logger?.log(.warning("Failed to parse font: \(fntFile.fileName)"))
                        continue
                    }

                    let fontName = fntFile.fileName.replacingOccurrences(of: ".fnt", with: "")
                    let fontFolder = outputFolder.folder(fontName)
                    fileSystem.createFolder(at: fontFolder, overwrite: overwrite)

                    let (imageData, metadata) = GSFontAtlas.exportAtlas(font: font)

                    let atlasFile = fontFolder.file("atlas.pgm")
                    let metadataFile = fontFolder.file("metadata.json")

                    if overwrite || fileSystem.inspectFile(at: atlasFile) == nil {
                        fileSystem.writeFile(imageData, at: atlasFile, overwrite: overwrite)
                    }
                    try fileSystem.encodeJSON(metadata, to: metadataFile, overwrite: overwrite)

                    logger?.log(.info("  \(fontName): \(font.visibleGlyphs.count) glyphs → \(fontFolder.path)"))
                }
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

        let textureDecoder = GXTextureDecoder()

        for entry in archive.entries {
            let targetFolder = gsEngine.resolveFolder(
                forFileType: entry.metadata.fileType,
                entryFilename: entry.filename,
                archiveName: archiveName
            ).resolvedFolder

            let fileType = entry.metadata.fileType
            if fileType == "gtx" || fileType == "atx" {
                // Store texture metadata in the registry for re-encoding on import
                let texMeta = fileType == "atx"
                    ? textureDecoder.parseATXHeader(data: entry.data)
                    : textureDecoder.parseHeader(data: entry.data)

                if let image = textureDecoder.decode(data: entry.data),
                   let pngData = image.pngData() {
                    let pngFile = targetFolder.file(entry.filename.withoutExtensions + ".png")
                    entries.append(.init(metadata: entry.metadata, file: pngFile, textureMetadata: texMeta))
                    extractedFiles.append((file: pngFile, data: pngData))
                } else {
                    let targetFile = targetFolder.file(entry.filename)
                    entries.append(.init(metadata: entry.metadata, file: targetFile, textureMetadata: texMeta))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
            } else {
                let targetFile = targetFolder.file(entry.filename)
                entries.append(.init(metadata: entry.metadata, file: targetFile))
                extractedFiles.append((file: targetFile, data: entry.data))
            }
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

        // Folders are created on-demand when files are written,
        // avoiding empty directories for unused file types.
        let fsysConfig = gsEngine.data.fsys

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
        let gsfsysFileName = gsEngine.data.fsys.GSfsysFile.fileName
        for other in otherPaths {
            // Skip the FSYS table of contents — it's not needed in the unpacked output
            if other.path.fileName == gsfsysFileName { continue }

            let targetFolder = gsEngine.resolveFolder(
                forFileType: other.path.fileType,
                entryFilename: other.path.fileName,
                archiveName: ""
            ).resolvedFolder
            let outputFile = targetFolder.file(other.path.fileName)
            _ = projectFileSystem.writeFile(other.data, at: outputFile, overwrite: true)
            fstEntries.append(.init(type: .binary, file: outputFile))
        }

        // Phase 3: Process all FSYS archives concurrently
        var fsysResults = [Result<FsysResult, Error>?](repeating: nil, count: fsysPaths.count)
        let progressLock = NSLock()
        var fsysProcessed = 0
        var lastReportedPercent = -1

        DispatchQueue.concurrentPerform(iterations: fsysPaths.count) { i in
            let source = fsysPaths[i]
            do {
                fsysResults[i] = .success(try processFsys(
                    data: source.data,
                    fileName: source.path.fileName,
                    toc: toc,
                    gsEngine: gsEngine
                ))
            } catch {
                fsysResults[i] = .failure(error)
            }

            if let logger {
                progressLock.lock()
                fsysProcessed += 1
                let processed = otherPaths.count + fsysProcessed
                let percent = Int(min(Double(processed) / Double(totalCount) * 100, 100))
                if percent > lastReportedPercent {
                    lastReportedPercent = percent
                    logger.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
                }
                progressLock.unlock()
            }
        }

        // Font deduplication: collect all .fnt files, deduplicate by content
        var uniqueFonts = [(data: GoDData, file: File)]()
        var fontFileMapping = [String: File]()
        let fontsFolder: Folder = fsysConfig.fileTypeFolders["fnt"] ?? "/Assets/Text/Fonts"

        for case .success(let r) in fsysResults.compactMap({ $0 }) {
            for extracted in r.extractedFiles where extracted.file.fileType == "fnt" {
                if let existing = uniqueFonts.first(where: { $0.data == extracted.data }) {
                    fontFileMapping[extracted.file.path] = existing.file
                } else {
                    let canonical = fontsFolder.file("Font_Data_\(uniqueFonts.count + 1).fnt")
                    uniqueFonts.append((data: extracted.data, file: canonical))
                    fontFileMapping[extracted.file.path] = canonical
                }
            }
        }

        for font in uniqueFonts {
            _ = projectFileSystem.writeFile(font.data, at: font.file, overwrite: true)
        }

        // Merge results into the InMemoryFST, remapping font paths
        for result in fsysResults {
            guard let result else { continue }
            switch result {
            case .success(let fsysResult):
                for extracted in fsysResult.extractedFiles {
                    // Skip .fnt files — they were written above as deduplicated
                    if extracted.file.fileType == "fnt" { continue }
                    _ = projectFileSystem.writeFile(extracted.data, at: extracted.file, overwrite: true)
                }

                // Remap font entries in registry to deduplicated paths
                let remappedEntries = fsysResult.registry.entries.map { entry -> FSYSRegistry.Entry in
                    if entry.file.fileType == "fnt",
                       let mappedFile = fontFileMapping[entry.file.path] {
                        return FSYSRegistry.Entry(
                            metadata: entry.metadata,
                            file: mappedFile,
                            textureMetadata: entry.textureMetadata
                        )
                    }
                    return entry
                }
                let remappedRegistry = FSYSRegistry(
                    groupID: fsysResult.registry.groupID,
                    metaData: fsysResult.registry.metaData,
                    entries: remappedEntries
                )

                _ = projectFileSystem.writeFile(remappedRegistry, at: fsysResult.registryFile, overwrite: true)
                fstEntries.append(.init(type: .fsys, file: fsysResult.registryFile))
            case .failure(let error):
                throw error
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
