@_exported import GoDEngine
import GoDFoundation
import Structs
import Disassembler
import Foundation

public struct XDEngine: Engine {
    public typealias DataType = XDEngine.Data
    public typealias EnumsType = XDEngine.Enums
    public typealias StructsType = XDEngine.Structs

    /// The folder an engine serializes to is named after it, so callers
    /// that need the path before building an instance (project setup,
    /// generated configs) can read it from the type instead of repeating
    /// the literal and letting the two drift apart.
    public static let defaultName = "XD Engine"
    public let name = Self.defaultName
    public private(set) var data = XDEngine.Data()
    public private(set) var enums = XDEngine.Enums()
    public private(set) var structs = XDEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> XDEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }

    /// The engine for a specific XD build.
    ///
    /// Only the save-section struct bindings vary: XD shipped in Japan
    /// first and the international builds widened four sections, so a JP
    /// save needs `sectionStructTypes` pointed at the JP structs. Binding
    /// the international structs to a JP save doesn't mis-decode it — the
    /// dump notices the size mismatch and falls back to a raw `.bin` — but
    /// it does cost the player every editable section that differs,
    /// including `PCBox`, which is most of what a save editor is for.
    ///
    /// An unknown game ID gets the international bindings, which is what
    /// `defaults()` has always returned.
    public static func defaultEngine(forGameID gameID: String) throws -> XDEngine {
        var data = Data()
        if gameID == PokemonXD.gameIDJP {
            data.sectionStructTypes = Data.japaneseSectionStructTypes
        }
        return try .init(data: data, enums: Enums(), structs: Structs())
    }

    /// Copies the Swift-package-bundled reference resources into the
    /// engine folder during project setup. Each entry is keyed by the
    /// relative `File` declared on `Data.Resources`, so consumers can
    /// resolve the on-disk path without the engine having to know about
    /// Bundle.module.
    public func bundledResources() -> [File: GoDData] {
        var result: [File: GoDData] = [:]

        func add(_ file: File, named bundledName: String) {
            if let bytes = PokemonXD.bundledResource(named: bundledName) {
                result[file] = bytes
            }
        }

        add(data.resources.commonRelSymbolMap, named: "common_rel_symbols.json")
        // The US variants are the defaults so the files are never empty;
        // `ProjectSetup` overwrites both with the ROM's own region via
        // `regionalResources`. One path, one file — ops stay region-blind.
        add(data.resources.commonRelTypeMap, named: "common_rel_typemap_us.json")
        add(data.resources.dolTypeMap, named: "dol_typemap_us.json")
        // The REL route table is per region — each names only the files that
        // disc ships, and a file's layout can differ between builds — so the
        // US table is the default and `ProjectSetup` writes the ROM's own.
        // Every type map and symbol index any region's matchers name is
        // installed, since the region isn't known yet.
        add(data.resources.relRoutes, named: "rel_routes_us.json")
        for file in Set(PokemonXD.relRouteTables.flatMap(\.matcherFiles)) {
            add(file, named: file.fileName)
        }
        // The flag descriptor table is region-independent, so unlike the maps
        // above there is nothing for ProjectSetup to overwrite per region.
        add(data.resources.generalFlagsTable, named: "general_flags.csv")
        add(data.resources.saveSectionLayout, named: "save_section_layout.json")
        // DOL symbol map is region-specific — written by `ProjectSetup`
        // once the ROM's game ID is known, not bundled at engine-write
        // time.
        return result
    }
}

public enum PokemonXD {

    public static let gameIDJP = "GXXJ"
    public static let gameIDUS = "GXXE"
    public static let gameIDEU = "GXXP"

    public static let gameIDs = [
        gameIDJP,
        gameIDUS,
        gameIDEU
    ]

    /// The REL route table for a specific build: every REL that disc ships,
    /// routed by its own analysis (`scripts/analysis/gen_rel_routes.py`).
    public static func relRouteTableData(for gameID: String) -> GoDData? {
        guard let suffix = regionSuffix(for: gameID) else { return nil }
        return bundledResource(named: "rel_routes_\(suffix).json")
    }

    public static var relRouteTables: [RelRouteTable] {
        ["us", "eu", "jp"].compactMap { suffix in
            bundledResource(named: "rel_routes_\(suffix).json").flatMap { data in
                try? JSONDecoder().decode(RelRouteTable.self, from: data.data)
            }
        }
    }

    /// Returns the symbol map data for the given game ID, if available as a bundled resource.
    public static func symbolMapData(for gameID: String) -> GoDData? {
        guard gameIDs.contains(gameID) else { return nil }
        return bundledResource(named: gameID + ".map")
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

    /// Loads a file from the XD module's `Resources/` bundle directory.
    /// Used both by the public accessors above and by
    /// `XDEngine.bundledResources()` when copying defaults into a new
    /// project's engine folder.
    public static func bundledResource(named name: String) -> GoDData? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources") else {
            return nil
        }
        guard let data = try? Foundation.Data(contentsOf: url) else { return nil }
        return GoDData(data: data, byteOrder: .big)
    }
}
