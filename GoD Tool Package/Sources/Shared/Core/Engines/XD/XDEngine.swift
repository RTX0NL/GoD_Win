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
        return loadResource(gameID + ".map")
    }

    /// Returns the REL symbol index data for a given REL name (e.g. "common_rel", "pocket_menu", "map_rel")
    public static func relSymbolIndexData(for relName: String) -> GoDData? {
        return loadResource(relName + "_symbols.json")
    }

    private static func loadResource(_ name: String) -> GoDData? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources") else {
            return nil
        }
        guard let data = try? Foundation.Data(contentsOf: url) else { return nil }
        return GoDData(data: data, byteOrder: .big)
    }
}
