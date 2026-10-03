import GoDFoundation
import Structs

/// Static cross-game enum defaults. Species / move / item / ability
/// rosters depend on the specific game's data tables and are loaded
/// from there at dump/build time, so they're not bundled here. The
/// enums below are fixed-cardinality and shared across all GS games.
public extension PokemonEnumDefaults {

    static let gendersEnum = Enum(
        name: "Gender",
        allowUnknownCases: false,
        values: [
            .init(name: "Male",       rawValue: 0),
            .init(name: "Female",     rawValue: 1),
            .init(name: "Genderless", rawValue: 2),
        ],
        propertyType: .uint8
    )

    static let naturesEnum = Enum(
        name: "Nature",
        allowUnknownCases: false,
        values: [
            .init(name: "Hardy",   rawValue: 0),
            .init(name: "Lonely",  rawValue: 1),
            .init(name: "Brave",   rawValue: 2),
            .init(name: "Adamant", rawValue: 3),
            .init(name: "Naughty", rawValue: 4),
            .init(name: "Bold",    rawValue: 5),
            .init(name: "Docile",  rawValue: 6),
            .init(name: "Relaxed", rawValue: 7),
            .init(name: "Impish",  rawValue: 8),
            .init(name: "Lax",     rawValue: 9),
            .init(name: "Timid",   rawValue: 10),
            .init(name: "Hasty",   rawValue: 11),
            .init(name: "Serious", rawValue: 12),
            .init(name: "Jolly",   rawValue: 13),
            .init(name: "Naive",   rawValue: 14),
            .init(name: "Modest",  rawValue: 15),
            .init(name: "Mild",    rawValue: 16),
            .init(name: "Quiet",   rawValue: 17),
            .init(name: "Bashful", rawValue: 18),
            .init(name: "Rash",    rawValue: 19),
            .init(name: "Calm",    rawValue: 20),
            .init(name: "Gentle",  rawValue: 21),
            .init(name: "Sassy",   rawValue: 22),
            .init(name: "Careful", rawValue: 23),
            .init(name: "Quirky",  rawValue: 24),
        ],
        propertyType: .uint8
    )

    static let typesEnum = Enum(
        name: "Type",
        allowUnknownCases: true,
        values: [
            .init(name: "Normal",   rawValue: 0),
            .init(name: "Fighting", rawValue: 1),
            .init(name: "Flying",   rawValue: 2),
            .init(name: "Poison",   rawValue: 3),
            .init(name: "Ground",   rawValue: 4),
            .init(name: "Rock",     rawValue: 5),
            .init(name: "Bug",      rawValue: 6),
            .init(name: "Ghost",    rawValue: 7),
            .init(name: "Steel",    rawValue: 8),
            .init(name: "None",     rawValue: 9),
            .init(name: "Fire",     rawValue: 10),
            .init(name: "Water",    rawValue: 11),
            .init(name: "Grass",    rawValue: 12),
            .init(name: "Electric", rawValue: 13),
            .init(name: "Psychic",  rawValue: 14),
            .init(name: "Ice",      rawValue: 15),
            .init(name: "Dragon",   rawValue: 16),
            .init(name: "Dark",     rawValue: 17),
            .init(name: "Shadow",   rawValue: 18),
        ],
        propertyType: .uint8
    )

    static let eggGroupsEnum = Enum(
        name: "EggGroup",
        allowUnknownCases: true,
        values: [
            .init(name: "None",       rawValue: 0),
            .init(name: "Monster",    rawValue: 1),
            .init(name: "Water1",     rawValue: 2),
            .init(name: "Bug",        rawValue: 3),
            .init(name: "Flying",     rawValue: 4),
            .init(name: "Field",      rawValue: 5),
            .init(name: "Fairy",      rawValue: 6),
            .init(name: "Grass",      rawValue: 7),
            .init(name: "HumanLike",  rawValue: 8),
            .init(name: "Water3",     rawValue: 9),
            .init(name: "Mineral",    rawValue: 10),
            .init(name: "Amorphous",  rawValue: 11),
            .init(name: "Water2",     rawValue: 12),
            .init(name: "Ditto",      rawValue: 13),
            .init(name: "Dragon",     rawValue: 14),
            .init(name: "Undiscovered", rawValue: 15),
        ],
        propertyType: .uint8
    )

    static let expRatesEnum = Enum(
        name: "ExpRate",
        allowUnknownCases: false,
        values: [
            .init(name: "MediumFast", rawValue: 0),
            .init(name: "Erratic",    rawValue: 1),
            .init(name: "Fluctuating", rawValue: 2),
            .init(name: "MediumSlow", rawValue: 3),
            .init(name: "Fast",       rawValue: 4),
            .init(name: "Slow",       rawValue: 5),
        ],
        propertyType: .uint8
    )
}
