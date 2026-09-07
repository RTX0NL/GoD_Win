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

    /// Also the engine's folder name once serialized, so callers that only
    /// need the path don't have to build an engine to read it.
    public static let engineName = "Pokemon Engine"
    public let name = PokemonEngine.engineName
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

    /// Which game's species / move / item numbering to use.
    ///
    /// Deliberately not `GSGame`: this module carries no dependency on the
    /// Genius Sonority engine, and taking one for a three-case identifier
    /// would invert the layering — Pokemon data is the general thing. The
    /// raw values match `GSGame`'s so callers that hold one can convert with
    /// `PokemonEngine.Game(rawValue:)`.
    public enum Game: String, Codable, CaseIterable {
        case colosseum, galeOfDarkness, battleRevolution
    }

    /// An engine whose species, move and item ids are the given game's.
    ///
    /// The fixed cross-game enums (types, natures, genders, egg groups, exp
    /// rates) are shared and come from `Enums.allItems`; the numbered lists
    /// vary, because every game indexes them differently —
    /// Deoxys is species 410 in Colosseum and XD but 386 in Battle
    /// Revolution, and item lists diverge wholesale.
    public static func defaultEngine(for game: Game) throws -> PokemonEngine {
        var enumList = Enums.allItems
        switch game {
        case .colosseum:
            enumList += [
                PokemonEnumDefaults.colosseumSpeciesEnum,
                PokemonEnumDefaults.colosseumMovesEnum,
                PokemonEnumDefaults.colosseumItemsEnum,
                PokemonEnumDefaults.coloXdAbilitiesEnum,
                PokemonEnumDefaults.coloXdMoveTargetEnum,
                PokemonEnumDefaults.coloXdMoveCategoryEnum,
                PokemonEnumDefaults.coloXdMoveEffectTypeEnum,
                PokemonEnumDefaults.coloXdContestCategoryEnum,
                PokemonEnumDefaults.coloXdItemPocketEnum,
            ]
        case .galeOfDarkness:
            enumList += [
                PokemonEnumDefaults.xdSpeciesEnum,
                PokemonEnumDefaults.xdMovesEnum,
                PokemonEnumDefaults.xdItemsEnum,
                PokemonEnumDefaults.coloXdAbilitiesEnum,
                PokemonEnumDefaults.coloXdMoveTargetEnum,
                PokemonEnumDefaults.coloXdMoveCategoryEnum,
                PokemonEnumDefaults.coloXdMoveEffectTypeEnum,
                PokemonEnumDefaults.coloXdContestCategoryEnum,
                PokemonEnumDefaults.coloXdItemPocketEnum,
            ]
        case .battleRevolution:
            enumList += [
                PokemonEnumDefaults.pbrSpeciesEnum,
                PokemonEnumDefaults.pbrMovesEnum,
                PokemonEnumDefaults.pbrItemsEnum,
                PokemonEnumDefaults.pbrAbilitiesEnum,
                PokemonEnumDefaults.pbrMoveTargetEnum,
                PokemonEnumDefaults.pbrMoveCategoryEnum,
                PokemonEnumDefaults.pbrMoveEffectTypeEnum,
            ]
        }
        return try .init(data: Data(), enums: Enums(unchecked: enumList), structs: Structs())
    }
}
