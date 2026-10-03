import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import GTX
import Colosseum
import ScriptDecompiler

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

                try gsEngine.packProject(
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildXD(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try gsEngine.packProject(
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildGSfsysTOC(fstRegistryFile, outputFile, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let sourceFolder = fstRegistryFile.parentFolder else {
                    throw FSTErrors.fileNotFound(fstRegistryFile, .init())
                }

                logger?.log(.info("Building GSfsys.toc from FSTRegistry"))
                let tocData = try gsEngine.buildGSfsysTOC(
                    fstRegistryFile: fstRegistryFile,
                    sourceFolder: sourceFolder,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(tocData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(tocData.length) bytes)"))
                }

            case let .buildFST(contentsFolder, outputFile, overwrite, dolphinEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)

                logger?.log(.info("Building fst.bin from \(contentsFolder.path)"))
                let fst = DolphinFST(fileSystem: fileSystem, root: contentsFolder)
                let fstData = try fst.tocData(userOffset: 0, dolphinEngine: dolphinEngine)

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(fstData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(fstData.length) bytes, \(fst.files.count) files)"))
                }

            case let .packFSYS(registryFile, outputFile, sourceFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                logger?.log(.info("Packing FSYS archive from \(registryFile.fileName) entries)"))

                let archiveData = try gsEngine.packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(archiveData.data, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(archiveData.data.length) bytes)"))
                }

            case let .buildFonts(fontsFolder, outputFolder, overwrite):
                try buildFonts(
                    in: fontsFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildFlashMenus(projectsFolder, outputFolder, overwrite):
                try buildFlashMenus(
                    in: projectsFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildFlashMenu(metadataFile, outputFile, overwrite):
                try buildFlashMenu(
                    metadataFile: metadataFile, outputFile: outputFile, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildMessages(jsonFolder, outputFolder, overwrite):
                try buildMessages(
                    in: jsonFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildMessage(jsonFile, outputFile, overwrite):
                try buildMessage(
                    jsonFile: jsonFile, outputFile: outputFile, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildATXs(jsonFolder, outputFolder, overwrite):
                try buildATXs(
                    in: jsonFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildATX(metadataFile, outputFile, overwrite):
                try buildATX(
                    metadataFile: metadataFile, outputFile: outputFile, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildAudios(jsonFolder, outputFolder, overwrite):
                try buildAudios(
                    in: jsonFolder, outputFolder: outputFolder, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildAudio(metadataFile, ishOutputFile, isdOutputFile, overwrite):
                try buildAudio(
                    metadataFile: metadataFile, ishOutputFile: ishOutputFile,
                    isdOutputFile: isdOutputFile, overwrite: overwrite,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildColoScripts(sourceFolder, outputFolder, overwrite, gameEngine, engines):
                try buildColoScripts(
                    in: sourceFolder, outputFolder: outputFolder, overwrite: overwrite,
                    gameEngine: gameEngine, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )

            case let .buildColoScript(sourceFile, outputFile, overwrite, gameEngine, engines):
                try buildColoScript(
                    sourceFile: sourceFile, outputFile: outputFile, overwrite: overwrite,
                    gameEngine: gameEngine, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )
            }
        }
    }
}
