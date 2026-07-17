@_exported import GoDEngine
import GoDFoundation
import Structs
import Foundation

/// Cross-game Pokémon engine — owns the canonical species / move / item /
/// ability / nature / type enums (consumed by Colo, XD and PBR for
/// name↔id resolution) plus the combined `Trainer` struct definition
/// (the union schema for the trainer-dump op).
public struct PokemonEngine: Engine {
    public typealias DataType = PokemonEngine.Data
    public typealias EnumsType = PokemonEngine.Enums
    public typealias StructsType = PokemonEngine.Structs

    public let name = "Pokemon Engine"
    public private(set) var data = PokemonEngine.Data()
    public private(set) var enums = PokemonEngine.Enums()
    public private(set) var structs = PokemonEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> PokemonEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}
