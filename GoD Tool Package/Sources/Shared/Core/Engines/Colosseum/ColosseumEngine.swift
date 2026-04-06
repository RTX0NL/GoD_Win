@_exported import GoDEngine
import GoDFoundation
import Structs

public struct ColosseumEngine: Engine {
    public typealias DataType = ColosseumEngine.Data
    public typealias EnumsType = ColosseumEngine.Enums
    public typealias StructsType = ColosseumEngine.Structs

    public let name = "Colosseum Engine"
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
}
