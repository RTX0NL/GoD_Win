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
import Colosseum
import ScriptDecompiler

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
                
                let output = try geniusEngine.unpackProject(
                    from: fstFolder,
                    fileSystem: fileSystem,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)
            case let .dumpXD(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)

                let output = try geniusEngine.unpackProject(
                    from: fstFolder,
                    fileSystem: fileSystem,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)

            case let .unpackFSYS(fsysFile, outputFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let data = fileSystem.readFile(at: fsysFile)?.allData else {
                    throw FSTErrors.fileNotFound(fsysFile, .init())
                }

                let archive = try FSYSArchive(data: data, engine: gsEngine)
                let archiveName = fsysFile.fileName.withoutExtensions

                logger?.log(.info("Unpacking FSYS archive: \(fsysFile.fileName) (\(archive.entries.count) entries)"))

                var registryEntries = [FSYSRegistry.Entry]()
                for entry in archive.entries {
                    let targetFolder = gsEngine.resolveFolder(
                        forFileType: entry.metadata.fileExtension,
                        entryFilename: entry.filename,
                        archiveName: archiveName
                    ).resolvedFolder
                    let targetFile = targetFolder.file(entry.filename)
                    registryEntries.append(.init(metadata: entry.metadata, file: targetFile))
                    if overwrite || fileSystem.inspectFile(at: targetFile) == nil {
                        try fileSystem.writeFile(entry.data, at: targetFile, overwrite: overwrite)
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
                try dumpFonts(
                    in: fontsFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpFlashMenus(flashMenusFolder, outputFolder, overwrite):
                try dumpFlashMenus(
                    in: flashMenusFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpFlashMenu(gswFile, outputFolder, overwrite):
                try dumpFlashMenu(
                    gswFile: gswFile, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpMessages(messagesFolder, outputFolder, overwrite, variant):
                try dumpMessages(
                    in: messagesFolder, outputFolder: outputFolder, overwrite: overwrite,
                    variant: variant, fileSystem: fileSystem, logger: logger
                )

            case let .dumpMessage(msgFile, outputFolder, overwrite, variant):
                try dumpMessage(
                    msgFile: msgFile, outputFolder: outputFolder, overwrite: overwrite,
                    variant: variant, fileSystem: fileSystem, logger: logger
                )

            case let .dumpATXs(atxFolder, outputFolder, overwrite):
                try dumpATXs(
                    in: atxFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpATX(atxFile, outputFolder, overwrite):
                try dumpATX(
                    atxFile: atxFile, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpAudios(audioFolder, outputFolder, overwrite):
                try dumpAudios(
                    in: audioFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpAudio(ishFile, isdFile, outputFolder, overwrite):
                try dumpAudio(
                    ishFile: ishFile, isdFile: isdFile, outputFolder: outputFolder,
                    overwrite: overwrite, fileSystem: fileSystem, logger: logger
                )

            case let .dumpColoScripts(scriptsFolder, outputFolder, overwrite, language, gameEngine, engines):
                try dumpColoScripts(
                    in: scriptsFolder, outputFolder: outputFolder, overwrite: overwrite,
                    language: language, gameEngine: gameEngine, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpColoScript(scdFile, outputFolder, overwrite, language, gameEngine, engines):
                try dumpColoScript(
                    scdFile: scdFile, outputFolder: outputFolder, overwrite: overwrite,
                    language: language, gameEngine: gameEngine, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpXDScripts(scriptsFolder, outputFolder, overwrite):
                try dumpXDScripts(
                    in: scriptsFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .dumpXDDecks(decksFolder, outputFolder, overwrite, engines):
                try dumpXDDecks(
                    in: decksFolder, outputFolder: outputFolder, overwrite: overwrite,
                    engines: engines, fileSystem: fileSystem, logger: logger
                )
            }
        }
    }

    /// Resolves a relative path string (e.g. `./textures/foo.png`) against
    /// `base`, normalizing leading `.`/`..` components. Used for paths stored
    /// inside metadata JSONs (GSW `pngPath`, font `atlasPath`, etc.).
    static func resolveRelativeFile(_ relativePath: String, in base: Folder) -> File {
        guard let lastSlash = relativePath.lastIndex(of: "/") else {
            return base.file(relativePath)
        }
        let dir = String(relativePath[..<lastSlash])
        let name = String(relativePath[relativePath.index(after: lastSlash)...])
        return base.folder(dir).file(name)
    }
}
