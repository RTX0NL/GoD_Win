import GoDFoundation
import Dolphin
import Disassembler
import Structs

extension RelDisassembly {
    /// Thin wrapper: loads the optional sidecars the config names — symbol
    /// index, DOL symbol map, type map and the engines that resolve it —
    /// and hands the module to `RelDisassembler`, which owns the layout.
    static func disassemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        guard RelOperationsGate.enabled else {
            throw RelOperationsGate.DisabledError(operation: "relDisassembly", trace: .init())
        }

        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)
        _ = dolphinEngine  // reserved for future (e.g. SDA base → name resolution)

        guard let relData = fileSystem.readFile(at: config.relPath)?.allData else {
            throw RelDisassemblyErrors.relNotFound(file: config.relPath, .init())
        }

        let relName = config.relPath.fileName.replacingOccurrences(of: ".rel", with: "")
        let rel = try RELFile(binary: relData, name: relName)

        var inputs = RelDisassembler.Inputs()
        inputs.registry = registry

        if let indexPath = config.symbolIndexPath,
           let indexData = fileSystem.readFile(at: indexPath)?.allData,
           let parsed = try? JSONDecoder().decode(RelSymbolIndex.self, from: indexData) {
            inputs.symbolIndex = parsed
            logger?.log(.info("Loaded \(parsed.symbols.count) symbol names from index"))
        }

        if let dolMapPath = config.dolSymbolMapPath,
           let dolMapData = fileSystem.readFile(at: dolMapPath)?.allData {
            let parser = SymbolMapParser()
            let dolSymbols = parser.parse(dolMapData.string(format: .utf8))
            inputs.dolSymbolLookup = parser.buildLookup(dolSymbols)
            logger?.log(.info("Loaded \(dolSymbols.count) DOL symbols for cross-module resolution"))
        }

        if let typeMapPath = config.typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath)?.allData,
           let typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData) {
            inputs.typeMap = typeMap
            inputs.structs = resolveStructTypes(
                from: typeMap,
                engineFolders: config.engines ?? [],
                fileSystem: fileSystem,
                logger: logger
            )
            logger?.log(.info("Loaded type map with \(typeMap.chunks.count) chunks"))
        }

        logger?.log(.info(
            "Disassembling REL '\(relName)' (module \(rel.moduleID), "
            + "\(rel.sections.filter { !$0.isEmpty }.count) non-empty sections)"
        ))

        let output = InMemoryFST()
        try RelDisassembler(inputs: inputs).disassemble(rel, into: Folder("/"), fileSystem: output, logger: logger)
        try fileSystem.importFST(output, from: Folder("/"), to: config.outputFolder, overwrite: true, logger: logger)
    }
}

enum RelDisassemblyErrors: Error, CustomStringConvertible {
    case relNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .relNotFound(file, trace):
            return "REL file not found: \(file)\n\(trace)"
        }
    }
}
