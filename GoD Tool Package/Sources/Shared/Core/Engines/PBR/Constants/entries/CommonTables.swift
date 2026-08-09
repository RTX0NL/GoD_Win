import GoDFoundation

/// The `common.fsys` table registry.
///
/// Table names and the US/PAL ↔ JP index permutation come from the legacy
/// tool's `GoDDataTable` accessors and its `PBR common pointers.txt` note,
/// which records the RAM jump table of pointers to each table alongside the
/// `common_XX.bin` member it was loaded from. Entry strides are measured
/// from the PAL disc (RPBP01): each table's header word at +0x04.
///
/// A `structName` of `nil` means the entry layout hasn't been documented —
/// those tables still round-trip via their raw byte-array struct, they just
/// aren't field-addressable yet.
public extension PBREngine.Data {
    static let defaultCommonTables: [CommonTable] = [
        .init(name: "PokemonIcons",           index: 0,  japaneseIndex: 6,   structName: "PBRPokemonIcon",              entrySize: 0x10),
        // The JP disc drops PAL's per-language block from this record, so it
        // is the same table 10 bytes shorter.
        .init(name: "Countries",              index: 1,  japaneseIndex: 7,   structName: "PBRCountry",                  entrySize: 0x76,
              japaneseStructName: "PBRCountryJP", japaneseEntrySize: 0x6C),
        .init(name: "PokeCouponShop",         index: 2,  japaneseIndex: 8,   structName: "PBRPokeCouponReward",         entrySize: 0x0C),
        // Present on the JP disc after all, at index 9, carrying one quote
        // set instead of five (PAL's five are one per PAL language and hold
        // identical ids). Confirmed by matching all 106 rows against the PAL
        // table: same `index` sequence from 182, same message ids, same
        // 17…54 group indices and 0x81/0x82 flags.
        .init(name: "ColosseumsUnknown",      index: 3,  japaneseIndex: 9,   structName: "PBRColosseumsUnknown",        entrySize: 0xBA,
              japaneseStructName: "PBRColosseumsUnknownJP", japaneseEntrySize: 0x3A),
        .init(name: "TypeMatchups",           index: 4,  japaneseIndex: 10,  structName: "PBRTypeMatchup",              entrySize: 0x12),
        .init(name: "ExperienceTables",       index: 5,  japaneseIndex: 11,  structName: "PBRExperienceTable",          entrySize: 0x194),
        .init(name: "PokemonModels",          index: 6,  japaneseIndex: 12,  structName: "PBRPokemonModel",             entrySize: 0x48),
        .init(name: "PokemonModelEffects",    index: 7,  japaneseIndex: 13,  structName: "PBRPokemonModelEffect",       entrySize: 0x14),
        .init(name: "PokemonStats",           index: 8,  japaneseIndex: 14,  structName: "PBRPokemonStats",             entrySize: 0x34),
        .init(name: "Evolutions",             index: 9,  japaneseIndex: 15,  structName: "PBRPokemonEvolutions",        entrySize: 0x2A),
        .init(name: "BallModels",             index: 10, japaneseIndex: 23,  structName: "PBRBallModel",                entrySize: 0x20),
        .init(name: "Colosseums",             index: 11, japaneseIndex: 24,  structName: "PBRColosseum",                entrySize: 0x5C),
        .init(name: "FightAIBattlePass",      index: 12, japaneseIndex: 25,  structName: "PBRFightAIBattlePass",        entrySize: 0x0C),
        .init(name: "FightAIExpectData",      index: 13, japaneseIndex: 26,  structName: "PBRFightAIExpectData",        entrySize: 0x2C),
        .init(name: "FightAIPokemonPartData", index: 14, japaneseIndex: 27,  structName: "PBRFightAIPokemonPartData",   entrySize: 0x0E),
        .init(name: "FightAIValues",          index: 15, japaneseIndex: 28,  structName: "PBRFightAIValue",             entrySize: 0x04),
        .init(name: "FightAIMoveData",        index: 16, japaneseIndex: 29,  structName: "PBRFightAIMoveData",          entrySize: 0x06),
        .init(name: "FlagIDs",                index: 17, japaneseIndex: 0,   structName: "PBRFlagID",                   entrySize: 0x0C),
        .init(name: "FloorEvent",             index: 18, japaneseIndex: 1,   structName: "PBRFloorEvent",               entrySize: 0x20),
        .init(name: "Items",                  index: 19, japaneseIndex: 2,   structName: "PBRItem",                     entrySize: 0x28),
        .init(name: "MenuBattleRules",        index: 20, japaneseIndex: 3,   structName: "PBRMenuBattleRule",           entrySize: 0x0E),
        .init(name: "PokemonBodies",          index: 21, japaneseIndex: 4,   structName: "PBRPokemonBody",              entrySize: 0x0C),
        .init(name: "PokemonFaces",           index: 22, japaneseIndex: 5,   structName: "PBRPokemonFace",              entrySize: 0x08),
        // The entry array is the per-ability message-ID pair; the ability
        // records themselves live in the name table. See the struct's docs.
        .init(name: "Abilities",              index: 23, japaneseIndex: 17,  structName: "PBRAbilityMessageIDs",        entrySize: 0x04),
        .init(name: "TrainerCustomParts",     index: 24, japaneseIndex: 18,  structName: "PBRTrainerCustomisation",     entrySize: 0x3C),
        .init(name: "TrainerCustomTable",     index: 25, japaneseIndex: 19,  structName: "PBRTrainerCustomTableEntry",  entrySize: 0x06),
        .init(name: "TrainerEvent",           index: 26, japaneseIndex: 20,  structName: "PBRTrainerEvent",             entrySize: 0x2C),
        .init(name: "TrainerModels",          index: 27, japaneseIndex: 21,  structName: "PBRTrainerModel",             entrySize: 0x54),
        .init(name: "TrainerTitles",          index: 28, japaneseIndex: 22,  structName: "PBRTrainerTitle",             entrySize: 0x0E),
        .init(name: "TMs",                    index: 29, japaneseIndex: 30,  structName: "PBRTM",                       entrySize: 0x04),
        .init(name: "Moves",                  index: 30, japaneseIndex: 31,  structName: "PBRMove",                     entrySize: 0x18),
        // Absent from the JP disc — the international release added it, which
        // is why JP ships 32 tables to US/PAL's 33. JP index 9 (previously
        // mapped here) is `ColosseumsUnknown`; nothing on the JP disc has
        // TutorialData's 0x1C stride and 266-row shape.
        .init(name: "TutorialData",           index: 31, japaneseIndex: nil, structName: "PBRTutorialData",             entrySize: 0x1C),
        .init(name: "LevelUpMoves",           index: 32, japaneseIndex: 16,  structName: "PBRLevelUpMoves",             entrySize: 0x50),
    ]
}

public extension PBREngine {
    /// Table descriptor for a canonical table name, e.g. `"PokemonModels"`.
    func commonTable(named name: String) -> Data.CommonTable? {
        data.commonTables.first { $0.name == name }
    }

    /// Table descriptor for a `common.fsys` file index on a given disc.
    /// JP discs order the members differently, so the lookup has to know
    /// which build it's reading.
    func commonTable(fileIndex: Int, japanese: Bool) -> Data.CommonTable? {
        data.commonTables.first {
            japanese ? $0.japaneseIndex == fileIndex : $0.index == fileIndex
        }?.resolved(japanese: japanese)
    }
}
