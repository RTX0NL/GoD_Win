import Foundation
import Structs

/// Names for the numbered members of `common.fsys`.
///
/// The game reaches these through a RAM jump table of pointers, one slot per
/// table; the legacy tool's `PBR common pointers.txt` records that jump table
/// alongside the `common_XX.bin` member each pointer was loaded from, and its
/// `GoDDataTable` accessors record the US/PAL ↔ JP index permutation.
///
/// Both enums are `allowUnknownCases` so a modded disc with extra members
/// still round-trips (as `PBRCommonTableIndex_<n>`) instead of failing.
public extension PBREnumDefaults {

    /// `common.fsys` member index → table, on US (RPBE) and PAL (RPBP) discs.
    static let commonTableIndex = Enum(
        name: "PBRCommonTableIndex",
        allowUnknownCases: true,
        values: [
            .init(name: "PokemonIcons",           rawValue: 0),
            .init(name: "Countries",              rawValue: 1),
            .init(name: "PokeCouponShop",         rawValue: 2),
            .init(name: "ColosseumsUnknown",      rawValue: 3),
            .init(name: "TypeMatchups",           rawValue: 4),
            .init(name: "ExperienceTables",       rawValue: 5),
            .init(name: "PokemonModels",          rawValue: 6),
            .init(name: "PokemonModelEffects",    rawValue: 7),
            .init(name: "PokemonStats",           rawValue: 8),
            .init(name: "Evolutions",             rawValue: 9),
            .init(name: "BallModels",             rawValue: 10),
            .init(name: "Colosseums",             rawValue: 11),
            .init(name: "FightAIBattlePass",      rawValue: 12),
            .init(name: "FightAIExpectData",      rawValue: 13),
            .init(name: "FightAIPokemonPartData", rawValue: 14),
            .init(name: "FightAIValues",          rawValue: 15),
            .init(name: "FightAIMoveData",        rawValue: 16),
            .init(name: "FlagIDs",                rawValue: 17),
            .init(name: "FloorEvent",             rawValue: 18),
            .init(name: "Items",                  rawValue: 19),
            .init(name: "MenuBattleRules",        rawValue: 20),
            .init(name: "PokemonBodies",          rawValue: 21),
            .init(name: "PokemonFaces",           rawValue: 22),
            .init(name: "Abilities",              rawValue: 23),
            .init(name: "TrainerCustomParts",     rawValue: 24),
            .init(name: "TrainerCustomTable",     rawValue: 25),
            .init(name: "TrainerEvent",           rawValue: 26),
            .init(name: "TrainerModels",          rawValue: 27),
            .init(name: "TrainerTitles",          rawValue: 28),
            .init(name: "TMs",                    rawValue: 29),
            .init(name: "Moves",                  rawValue: 30),
            .init(name: "TutorialData",           rawValue: 31),
            .init(name: "LevelUpMoves",           rawValue: 32),
        ],
        propertyType: .uint32
    )

    /// `common.fsys` member index → table, on Japanese (RPBJ) discs. Same
    /// 33 tables minus `ColosseumsUnknown`, in a different order — so an
    /// index means a different table depending on the build, and nothing
    /// may assume the US/PAL numbering.
    static let commonTableIndexJP = Enum(
        name: "PBRCommonTableIndexJP",
        allowUnknownCases: true,
        values: [
            .init(name: "FlagIDs",                rawValue: 0),
            .init(name: "FloorEvent",             rawValue: 1),
            .init(name: "Items",                  rawValue: 2),
            .init(name: "MenuBattleRules",        rawValue: 3),
            .init(name: "PokemonBodies",          rawValue: 4),
            .init(name: "PokemonFaces",           rawValue: 5),
            .init(name: "PokemonIcons",           rawValue: 6),
            .init(name: "Countries",              rawValue: 7),
            .init(name: "PokeCouponShop",         rawValue: 8),
            .init(name: "TutorialData",           rawValue: 9),
            .init(name: "TypeMatchups",           rawValue: 10),
            .init(name: "ExperienceTables",       rawValue: 11),
            .init(name: "PokemonModels",          rawValue: 12),
            .init(name: "PokemonModelEffects",    rawValue: 13),
            .init(name: "PokemonStats",           rawValue: 14),
            .init(name: "Evolutions",             rawValue: 15),
            .init(name: "LevelUpMoves",           rawValue: 16),
            .init(name: "Abilities",              rawValue: 17),
            .init(name: "TrainerCustomParts",     rawValue: 18),
            .init(name: "TrainerCustomTable",     rawValue: 19),
            .init(name: "TrainerEvent",           rawValue: 20),
            .init(name: "TrainerModels",          rawValue: 21),
            .init(name: "TrainerTitles",          rawValue: 22),
            .init(name: "BallModels",             rawValue: 23),
            .init(name: "Colosseums",             rawValue: 24),
            .init(name: "FightAIBattlePass",      rawValue: 25),
            .init(name: "FightAIExpectData",      rawValue: 26),
            .init(name: "FightAIPokemonPartData", rawValue: 27),
            .init(name: "FightAIValues",          rawValue: 28),
            .init(name: "FightAIMoveData",        rawValue: 29),
            .init(name: "TMs",                    rawValue: 30),
            .init(name: "Moves",                  rawValue: 31),
        ],
        propertyType: .uint32
    )
}
