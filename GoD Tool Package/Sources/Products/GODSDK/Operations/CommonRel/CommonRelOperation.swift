import GoDFoundation
import Dolphin
import Disassembler
import XD
import Colosseum

/// `common.rel` is a regular REL — these ops are thin wrappers around
/// `RelDisassembly`/`RelAssembly` that auto-resolve the typemap and
/// symbol-map paths from the project's game engine folder, so users
/// don't have to repeat them in every config.
extension CommonRelDump {
    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let resources = try resolveGameEngineResources(at: config.gameEngine, fileSystem: fileSystem)

        let symbolIndexPath = config.gameEngine.file(resources.commonRelSymbolMap.path)
        let typeMapPath = config.gameEngine.file(resources.commonRelTypeMap.path)
        let dolSymbolMapPath = config.gameEngine.file(resources.dolSymbolMap.path)

        let disassemblyConfig = RelDisassembly.Config(
            relPath: config.relPath,
            outputFolder: config.outputFolder,
            dolphinEngine: config.dolphinEngine,
            symbolIndexPath: fileSystem.inspectFile(at: symbolIndexPath) != nil ? symbolIndexPath : nil,
            dolSymbolMapPath: fileSystem.inspectFile(at: dolSymbolMapPath) != nil ? dolSymbolMapPath : nil,
            typeMapPath: fileSystem.inspectFile(at: typeMapPath) != nil ? typeMapPath : nil,
            // The common.rel type map's chunk types resolve against the game
            // engine's own struct definitions.
            engines: config.engines ?? [config.gameEngine]
        )

        logger?.log(.info("Dumping common.rel from \(config.relPath.path)"))
        try RelDisassembly.disassemble(
            config: disassemblyConfig,
            settings: settings,
            fileSystem: fileSystem,
            logger: logger
        )
    }
}

extension CommonRelBuild {
    static func build(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let assemblyConfig = RelAssembly.Config(
            inputFolder: config.inputFolder,
            relName: config.relName,
            outputPath: config.outputPath,
            overwrite: config.overwrite,
            engines: config.engines
        )
        logger?.log(.info("Building common.rel → \(config.outputPath.path)"))
        try RelAssembly.assemble(
            config: assemblyConfig,
            settings: settings,
            fileSystem: fileSystem,
            logger: logger
        )
    }
}

/// Game-engine `Data.Resources` — a stripped-down view that the common.rel
/// (and later map.rel) ops consume so they don't have to know which
/// concrete engine type wrote the project. Both `XDEngine` and
/// `ColosseumEngine` produce conformers via `gameEngineResources`.
struct GameEngineResources {
    let commonRelSymbolMap: File
    let commonRelTypeMap: File
    let dolSymbolMap: File
}

/// Tries XDEngine first, then ColosseumEngine. The engine folder for a
/// project is keyed by the engine's `name`, so we can probe both — the
/// caller's `gameEngine` path points at whichever one is real for this
/// project, and the other load attempt cleanly fails out.
private func resolveGameEngineResources(
    at folder: Folder,
    fileSystem: FileSystemTree
) throws -> GameEngineResources {
    if let engine = try? XDEngine(from: folder, in: fileSystem) {
        let r = engine.data.resources
        return GameEngineResources(
            commonRelSymbolMap: r.commonRelSymbolMap,
            commonRelTypeMap: r.commonRelTypeMap,
            dolSymbolMap: r.dolSymbolMap
        )
    }
    if let engine = try? ColosseumEngine(from: folder, in: fileSystem) {
        let r = engine.data.resources
        return GameEngineResources(
            commonRelSymbolMap: r.commonRelSymbolMap,
            commonRelTypeMap: r.commonRelTypeMap,
            dolSymbolMap: r.dolSymbolMap
        )
    }
    throw CommonRelErrors.unknownGameEngine(folder: folder, .init())
}

enum CommonRelErrors: Error, CustomStringConvertible {
    case unknownGameEngine(folder: Folder, ErrorTrace)

    var description: String {
        switch self {
        case let .unknownGameEngine(folder, trace):
            return "common.rel op: folder is neither an XD nor a Colosseum engine: \(folder.path)\n\(trace)"
        }
    }
}
