@_exported import GoDEngine
import GoDFoundation
import Structs
import Foundation

public struct XDEngine: Engine {
    public typealias DataType = XDEngine.Data
    public typealias EnumsType = XDEngine.Enums
    public typealias StructsType = XDEngine.Structs

    public let name = "XD Engine"
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
        add(data.resources.commonRelTypeMap, named: "common_rel_typemap.json")
        add(data.resources.mapRelSymbolMap, named: "map_rel_symbols.json")
        add(data.resources.mapRelTypeMap, named: "map_rel_typemap.json")
        add(data.resources.pocketMenuSymbolMap, named: "pocket_menu_symbols.json")
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

    /// Returns the symbol map data for the given game ID, if available as a bundled resource.
    public static func symbolMapData(for gameID: String) -> GoDData? {
        guard gameIDs.contains(gameID) else { return nil }
        return bundledResource(named: gameID + ".map")
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
