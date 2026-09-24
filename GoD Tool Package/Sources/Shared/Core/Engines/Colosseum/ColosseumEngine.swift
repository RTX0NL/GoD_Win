@_exported import GoDEngine
import GoDFoundation
import Structs
import ScriptDecompiler
import Foundation

public struct ColosseumEngine: Engine {
    public typealias DataType = ColosseumEngine.Data
    public typealias EnumsType = ColosseumEngine.Enums
    public typealias StructsType = ColosseumEngine.Structs

    /// The folder an engine serializes to is named after it, so callers
    /// that need the path before building an instance (project setup,
    /// generated configs) can read it from the type instead of repeating
    /// the literal and letting the two drift apart.
    public static let defaultName = "Colosseum Engine"
    public let name = Self.defaultName
    public private(set) var data = ColosseumEngine.Data()
    public private(set) var enums = ColosseumEngine.Enums()
    public private(set) var structs = ColosseumEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> ColosseumEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }

    /// Copies the Swift-package-bundled reference resources into the
    /// engine folder during project setup. See `XDEngine.bundledResources()`
    /// for the rationale.
    public func bundledResources() -> [File: GoDData] {
        var result: [File: GoDData] = [:]

        func add(_ file: File, named bundledName: String) {
            if let bytes = PokemonColosseum.bundledResource(named: bundledName) {
                result[file] = bytes
            }
        }

        // common_rel_symbols is region-specific (StringTable*/Script
        // pointer indices differ per region) — written by `ProjectSetup`
        // once the ROM's game ID is known. Same pattern as `dolSymbolMap`.
        // US variants are the defaults; `ProjectSetup` overwrites them with
        // the ROM's own region via `regionalResources`.
        add(data.resources.commonRelTypeMap, named: "common_rel_typemap_us.json")
        add(data.resources.dolTypeMap, named: "dol_typemap_us.json")
        add(data.resources.mapRelSymbolMap, named: "map_rel_symbols.json")
        add(data.resources.mapRelTypeMapType1, named: "map_rel_typemap_type1.json")
        add(data.resources.mapRelTypeMapType2, named: "map_rel_typemap_type2.json")
        add(data.resources.pocketMenuSymbolMap, named: "pocket_menu_symbols.json")
        // US is the bundled default so the file is never empty; `ProjectSetup`
        // writes the JP table over it when the disc is Japanese.
        add(data.resources.generalFlagsTable, named: "general_flags_us.csv")
        add(data.resources.saveSectionLayout, named: "save_section_layout.json")
        // DOL symbol map is also region-specific — written by `ProjectSetup`.
        return result
    }
}

public enum PokemonColosseum {

    public static let gameIDJP = "GC6J"
    public static let gameIDUS = "GC6E"
    public static let gameIDEU = "GC6P"

    public static let gameIDs = [
        gameIDJP,
        gameIDUS,
        gameIDEU
    ]

    /// The flag descriptor table for a build. US and PAL are byte-identical;
    /// JP differs in one byte, which is enough to move every later flag in two
    /// of the three banks, so the region matters.
    public static func generalFlagsTableData(for gameID: String) -> GoDData? {
        guard let suffix = regionSuffix(for: gameID) else { return nil }
        return bundledResource(named: "general_flags_\(suffix == "eu" ? "us" : suffix).csv")
    }

    /// Returns the symbol map data for the given game ID, if available as a bundled resource.
    public static func symbolMapData(for gameID: String) -> GoDData? {
        guard gameIDs.contains(gameID) else { return nil }
        return bundledResource(named: gameID + ".map")
    }

    /// Returns the region-matched common.rel pointer-index → symbol name
    /// table. The bundled map is keyed by region because StringTable*/
    /// Script live at different pointer indices per build (see
    /// legacy `CMRelIndexes.swift:108-126`); the project copy is always
    /// written to the engine's region-neutral `commonRelSymbolMap` path.
    public static func commonRelSymbolMapData(for gameID: String) -> GoDData? {
        let suffix: String
        switch gameID {
        case gameIDUS: suffix = "us"
        case gameIDEU: suffix = "eu"
        case gameIDJP: suffix = "jp"
        default: return nil
        }
        return bundledResource(named: "common_rel_symbols_\(suffix).json")
    }


    /// Region suffix used by the bundled per-region resources.
    /// Nil for a game ID this engine doesn't own.
    static func regionSuffix(for gameID: String) -> String? {
        switch gameID {
        case gameIDUS: return "us"
        case gameIDEU: return "eu"
        case gameIDJP: return "jp"
        default: return nil
        }
    }

    /// Typed regions within `main.dol` for a specific build.
    ///
    /// Keyed by region because every chunk in it is identified by address,
    /// and the data sections move between builds — a US map applied to a PAL
    /// disc names nothing at best and mistypes bytes at worst. The project
    /// copy is always written to the engine's region-neutral
    /// `dolTypeMap` path, so downstream ops never learn about regions.
    public static func dolTypeMapData(for gameID: String) -> GoDData? {
        guard let suffix = regionSuffix(for: gameID) else { return nil }
        return bundledResource(named: "dol_typemap_\(suffix).json")
    }

    /// Typed regions within `common.rel` for a specific build. Same
    /// reasoning as the DOL map: chunks are keyed by pointer-index symbol,
    /// and those indices differ per build.
    public static func commonRelTypeMapData(for gameID: String) -> GoDData? {
        guard let suffix = regionSuffix(for: gameID) else { return nil }
        return bundledResource(named: "common_rel_typemap_\(suffix).json")
    }

    /// Returns the REL symbol index data for a given REL name (e.g. "common_rel", "pocket_menu", "map_rel")
    public static func relSymbolIndexData(for relName: String) -> GoDData? {
        return bundledResource(named: relName + "_symbols.json")
    }

    /// Loads a file from the Colo module's bundled resources. Swift PM
    /// flattens this target's `Resources/` directory into the bundle
    /// root (XD's bundle preserves the subdir; the inconsistency is a
    /// quirk of how `.process` handles each target), so we look up by
    /// name only — no `subdirectory` argument.
    public static func bundledResource(named name: String) -> GoDData? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            return nil
        }
        guard let data = try? Foundation.Data(contentsOf: url) else { return nil }
        return GoDData(data: data, byteOrder: .big)
    }
}

public extension ColosseumEngine {
    /// Builtin signatures keyed by function id, the form the script emitter
    /// and parser both want. The engine stores them keyed by the string form
    /// the JSON uses, so every caller was re-deriving this.
    var scriptBuiltInFunctionsByID: [Int: ScriptFunctionDef] {
        data.scriptBuiltInFunctions.reduce(into: [:]) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
    }

    /// Enum definitions keyed by name, for resolving enum-typed script
    /// arguments back to case names.
    var enumsByName: [String: Enum] {
        Dictionary(enums.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
