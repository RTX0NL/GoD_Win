import GoDFoundation
import Dolphin
import Disassembler
import XD
import Colosseum

/// Map .rel ops — thin wrappers around `RelDisassembly` / `RelAssembly`
/// that fan out across a folder of map files and apply per-file
/// filtering. The typemap is provided explicitly by the caller (Type 1
/// vs Type 2 for Colo, the unified map for XD); the rest of the engine
/// resources (symbol map, DOL symbols) are read from `gameEngine` the
/// same way `commonRelDump` does.

extension MapRelDump {
    static func dump(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try dumpOne(
            relPath: config.relPath,
            outputFolder: config.outputFolder,
            overwrite: config.overwrite,
            typeMapPath: config.typeMapPath,
            dolphinEngine: config.dolphinEngine,
            gameEngine: config.gameEngine,
            settings: settings,
            fileSystem: fileSystem,
            logger: logger
        )
    }

    static func dump(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        guard let contents = fileSystem.inspectFolder(at: config.relsFolder) else {
            logger?.log(.warning("Map REL batch: folder not found: \(config.relsFolder.path)"))
            return
        }
        let relFiles = contents.files.filter { $0.fileType == "rel" }
        let filtered = try filterRels(relFiles, by: config.filter, fileSystem: fileSystem)

        logger?.log(.info("Map REL batch: \(filtered.count)/\(relFiles.count) files match filter \(config.filter)"))

        for relFile in filtered {
            let stem = relFile.fileName.withoutExtensions
            let mapOutputFolder = config.outputFolder.folder(stem)
            try dumpOne(
                relPath: relFile,
                outputFolder: mapOutputFolder,
                overwrite: config.overwrite,
                typeMapPath: config.typeMapPath,
                dolphinEngine: config.dolphinEngine,
                gameEngine: config.gameEngine,
                settings: settings,
                fileSystem: fileSystem,
                logger: logger
            )
        }
    }

    private static func dumpOne(
        relPath: File,
        outputFolder: Folder,
        overwrite: Bool,
        typeMapPath: File,
        dolphinEngine: Folder,
        gameEngine: Folder,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let resources = try resolveMapEngineResources(at: gameEngine, fileSystem: fileSystem)
        let symbolPath = gameEngine.file(resources.mapRelSymbolMap.path)
        let dolSymbolPath = gameEngine.file(resources.dolSymbolMap.path)

        let cfg = RelDisassembly.Config(
            relPath: relPath,
            outputFolder: outputFolder,
            dolphinEngine: dolphinEngine,
            symbolIndexPath: fileSystem.inspectFile(at: symbolPath) != nil ? symbolPath : nil,
            dolSymbolMapPath: fileSystem.inspectFile(at: dolSymbolPath) != nil ? dolSymbolPath : nil,
            typeMapPath: fileSystem.inspectFile(at: typeMapPath) != nil ? typeMapPath : nil
        )
        try RelDisassembly.disassemble(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    private static func filterRels(
        _ files: [File],
        by filter: Filter,
        fileSystem: FileSystemTree
    ) throws -> [File] {
        switch filter {
        case .all:
            return files
        case .onlyPrefixes(let prefixes):
            return files.filter { f in prefixes.contains(where: { f.fileName.hasPrefix($0) }) }
        case .excludePrefixes(let prefixes):
            return files.filter { f in !prefixes.contains(where: { f.fileName.hasPrefix($0) }) }
        case .coloType1:
            return files.filter { classifyColo($0, fileSystem: fileSystem) == .type1 }
        case .coloType2:
            return files.filter { classifyColo($0, fileSystem: fileSystem) == .type2 }
        }
    }

    /// Parses the REL just enough to classify it as Type 1 / Type 2 via
    /// the angle-sentinel check on pointer index 1. Files that fail to
    /// parse are reported as Type 1 (the conservative default — better
    /// to keep them in the standard pipeline than silently drop them).
    private static func classifyColo(
        _ relFile: File,
        fileSystem: FileSystemTree
    ) -> RELFile.ColosseumMapType {
        guard let data = fileSystem.readFile(at: relFile) else { return .type1 }
        let stem = relFile.fileName.withoutExtensions
        guard let rel = try? RELFile(binary: data, name: stem) else { return .type1 }
        return rel.classifyColosseumMap()
    }
}

extension MapRelBuild {
    static func build(
        config: SingleConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let cfg = RelAssembly.Config(
            inputFolder: config.inputFolder,
            relName: config.relName,
            outputPath: config.outputPath,
            overwrite: config.overwrite
        )
        try RelAssembly.assemble(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    static func build(
        config: BatchConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        guard let contents = fileSystem.inspectFolder(at: config.inputFolder) else {
            logger?.log(.warning("Map REL build batch: folder not found: \(config.inputFolder.path)"))
            return
        }
        for sub in contents.subFolders {
            let mapName = sub.folderName
            let outputFile = config.outputFolder.file("\(mapName).rel")
            let cfg = RelAssembly.Config(
                inputFolder: sub,
                relName: mapName,
                outputPath: outputFile,
                overwrite: config.overwrite
            )
            do {
                try RelAssembly.assemble(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
            } catch {
                logger?.log(.warning("Map REL build failed for \(mapName): \(error)"))
            }
        }
    }
}

private struct MapEngineResources {
    let mapRelSymbolMap: File
    let dolSymbolMap: File
}

private func resolveMapEngineResources(
    at folder: Folder,
    fileSystem: FileSystemTree
) throws -> MapEngineResources {
    if let engine = try? XDEngine(from: folder, in: fileSystem) {
        return MapEngineResources(
            mapRelSymbolMap: engine.data.resources.mapRelSymbolMap,
            dolSymbolMap: engine.data.resources.dolSymbolMap
        )
    }
    if let engine = try? ColosseumEngine(from: folder, in: fileSystem) {
        return MapEngineResources(
            mapRelSymbolMap: engine.data.resources.mapRelSymbolMap,
            dolSymbolMap: engine.data.resources.dolSymbolMap
        )
    }
    throw MapRelErrors.unknownGameEngine(folder: folder, .init())
}

enum MapRelErrors: Error, CustomStringConvertible {
    case unknownGameEngine(folder: Folder, ErrorTrace)
    case coloTypeFilterNotImplemented(ErrorTrace)

    var description: String {
        switch self {
        case let .unknownGameEngine(folder, trace):
            return "map REL op: folder is neither an XD nor a Colosseum engine: \(folder.path)\n\(trace)"
        case .coloTypeFilterNotImplemented(let trace):
            return "Colosseum Type 1/Type 2 runtime detection isn't wired up yet — use `.onlyPrefixes` / `.excludePrefixes` for now.\n\(trace)"
        }
    }
}
