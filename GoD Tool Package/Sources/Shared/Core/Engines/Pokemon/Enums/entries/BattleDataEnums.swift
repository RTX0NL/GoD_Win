import GoDFoundation
import Structs

/// Enums for Colosseum and XD battle-data fields whose values the games'
/// code branches on. Both games compile the same routines, so one set
/// serves both; each game engine lists the ones its structs reference.
/// Evidence per enum is in `Documentation/File Formats/XD/common.rel
/// Tables.md` and `Colosseum/common.rel Tables.md`.
public extension PokemonEnumDefaults {

    /// A type-chart cell. The values are status-effect (joutai) ids — rows
    /// 63-67 of the status table — and `zokuseiGetAisyouValue` branches on
    /// them. `Missed` never appears in a chart.
    static let typeEffectivenessEnum = Enum(
        name: "TypeEffectiveness",
        allowUnknownCases: true,
        values: [
            .init(name: "Neutral",          rawValue: 0x3F),
            .init(name: "Missed",           rawValue: 0x40),
            .init(name: "SuperEffective",   rawValue: 0x41),
            .init(name: "NotVeryEffective", rawValue: 0x42),
            .init(name: "NoEffect",         rawValue: 0x43),
        ],
        propertyType: .uint16
    )

    /// Which object a status effect lives on: `statusGetStatus`'s jump
    /// table (gamedata, PC box, hero, item, Pokémon, move, field, side,
    /// trainer).
    static let statusEffectOwnerEnum = Enum(
        name: "StatusEffectOwner",
        allowUnknownCases: true,
        values: [
            .init(name: "None",     rawValue: 0),
            .init(name: "GameData", rawValue: 1),
            .init(name: "PCBox",    rawValue: 2),
            .init(name: "Hero",     rawValue: 3),
            .init(name: "Item",     rawValue: 4),
            .init(name: "Pokemon",  rawValue: 5),
            .init(name: "Move",     rawValue: 6),
            .init(name: "Field",    rawValue: 7),
            .init(name: "Side",     rawValue: 8),
            .init(name: "Trainer",  rawValue: 9),
        ],
        propertyType: .uint8
    )

    /// How a status effect is written over an existing one
    /// (`checkWriteJoutaiDataId` / `writeJoutaiDataId`). Modes 0 and 1 take
    /// the same branch; no difference between them has been found.
    static let statusWriteModeEnum = Enum(
        name: "StatusWriteMode",
        allowUnknownCases: true,
        values: [
            .init(name: "Overwrite0",        rawValue: 0),
            .init(name: "Overwrite1",        rawValue: 1),
            .init(name: "IfAbsent",          rawValue: 2),
            .init(name: "ReplaceUnlessSame", rawValue: 3),
            .init(name: "Stack",             rawValue: 4),
        ],
        propertyType: .uint8
    )

    /// A species' Pokédex color: the Gen III body colors, one higher, with
    /// 0 on the dummy species.
    static let pokedexColorEnum = Enum(
        name: "PokedexColor",
        allowUnknownCases: true,
        values: [
            .init(name: "None",   rawValue: 0),
            .init(name: "Red",    rawValue: 1),
            .init(name: "Blue",   rawValue: 2),
            .init(name: "Yellow", rawValue: 3),
            .init(name: "Green",  rawValue: 4),
            .init(name: "Black",  rawValue: 5),
            .init(name: "Brown",  rawValue: 6),
            .init(name: "Purple", rawValue: 7),
            .init(name: "Gray",   rawValue: 8),
            .init(name: "White",  rawValue: 9),
            .init(name: "Pink",   rawValue: 10),
        ],
        propertyType: .uint8
    )

    /// A Shadow Pokémon's Reverse Mode pattern
    /// (`pokemonGetDarkPokemonHyperJoutaiKakuritu`): the chance column of a
    /// level × pattern percent table, highest at 1. The game clamps the
    /// pattern to 4, so `VeryLow` behaves exactly like `Low`.
    static let reverseModeRateEnum = Enum(
        name: "ReverseModeRate",
        allowUnknownCases: true,
        values: [
            .init(name: "None",     rawValue: 0),
            .init(name: "VeryHigh", rawValue: 1),
            .init(name: "High",     rawValue: 2),
            .init(name: "Medium",   rawValue: 3),
            .init(name: "Low",      rawValue: 4),
            .init(name: "VeryLow",  rawValue: 5),
        ],
        propertyType: .uint8
    )

    /// A deck Pokémon's role in the AI (`DeckPokemon::getKeyPlayer`): the
    /// switch-in scoring treats 1, 2 and 3 differently, and lead selection
    /// takes 2 first and 3 second. The case names are interpretations.
    static let deckPokemonKeyPlayerEnum = Enum(
        name: "DeckPokemonKeyPlayer",
        allowUnknownCases: true,
        values: [
            .init(name: "None",       rawValue: 0),
            .init(name: "Key",        rawValue: 1),
            .init(name: "LeadFirst",  rawValue: 2),
            .init(name: "LeadSecond", rawValue: 3),
        ],
        propertyType: .uint8
    )
}
