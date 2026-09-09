import Structs

/// Enums for the `common.rel` battle table (`fightEncountData`). These are
/// Genius Sonority's own value sets — a battle's kind indexes XD's
/// `BattleTypes` table, its participants come from XD's deck files — so they
/// belong to the game engine, not the shared Pokemon set. All use
/// `allowUnknownCases: true` so a modded value still round-trips.
public enum XDCommonRelEnumDefaults {

    /// `fightKind` — the row of the `BattleTypes` table that supplies a
    /// battle's rules (prize money, exp, whether Pokémon count as seen…).
    /// Names from the legacy tool's `XGBattleTypes`, XD perspective. The US
    /// disc uses 0 and 2–16; 1, 17 and 18 are Colosseum-only.
    public static let battleKind = Enum(
        name: "BattleKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None",                    rawValue: 0),
            .init(name: "StoryAdminColosseum",     rawValue: 1),
            .init(name: "Story",                   rawValue: 2),
            .init(name: "ColosseumPreliminary",    rawValue: 3),
            .init(name: "Sample",                  rawValue: 4),
            .init(name: "ColosseumFinal",          rawValue: 5),
            .init(name: "OrreColosseumPreliminary", rawValue: 6),
            .init(name: "OrreColosseumFinal",      rawValue: 7),
            .init(name: "MtBattle",                rawValue: 8),
            .init(name: "MtBattleFinal",           rawValue: 9),
            .init(name: "BattleMode",              rawValue: 10),
            .init(name: "LinkBattle",              rawValue: 11),
            .init(name: "WildPokemon",             rawValue: 12),
            .init(name: "BattleBingo",             rawValue: 13),
            .init(name: "BattleCD",                rawValue: 14),
            .init(name: "BattleTutorial",          rawValue: 15),
            .init(name: "MirorBPokespot",          rawValue: 16),
            .init(name: "ECardSpecialBattle",      rawValue: 17),
            .init(name: "BattleModeMtBattleFinal", rawValue: 18),
        ],
        propertyType: .uint8
    )

    /// Active Pokémon per trainer (`fightoutPokemonNum`): 1 for a single
    /// battle, 2 for a double. Legacy `XGBattleStyles`.
    public static let battleStyle = Enum(
        name: "BattleStyle",
        allowUnknownCases: true,
        values: [
            .init(name: "None",   rawValue: 0),
            .init(name: "Single", rawValue: 1),
            .init(name: "Double", rawValue: 2),
            .init(name: "Other",  rawValue: 3),
        ],
        propertyType: .uint8
    )

    /// Which deck file a battle participant's trainer is read from
    /// (`fightDeckGrpId`). The numbering is the deck files' own — legacy
    /// `XGDecks.id` — and 0 doubles as "no deck": the player's slot is deck
    /// 0 with trainer id 5000.
    public static let deck = Enum(
        name: "Deck",
        allowUnknownCases: true,
        values: [
            .init(name: "DarkPokemon", rawValue: 0),
            .init(name: "Story",       rawValue: 1),
            .init(name: "Hundred",     rawValue: 2),
            .init(name: "Imasugu",     rawValue: 3),
            .init(name: "Virtual",     rawValue: 4),
            .init(name: "Bingo",       rawValue: 5),
            .init(name: "Colosseum",   rawValue: 6),
            .init(name: "Sample",      rawValue: 7),
        ],
        propertyType: .uint16
    )

    /// A room's floor kind (`floorDataBiosGetFloorKind`, byte +0x01 of the
    /// `Rooms` record). The floor code branches on it everywhere a room is
    /// entered: which lifecycle path runs, whether shadows and fog are set
    /// up, the frame-rate mode, whether the player can move. Named from the
    /// rooms that carry each value on the US disc — the same partition
    /// Colosseum uses, where the value sits in the top three bits of a
    /// flags byte. Kind 3 is handled by the code but no room uses it.
    public static let roomKind = Enum(
        name: "RoomKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None",       rawValue: 0),  // room 0 and the fight demo
            .init(name: "Field",      rawValue: 1),  // overworld maps the player walks in
            .init(name: "Battle",     rawValue: 2),  // colosseums and the per-town battle arenas
            .init(name: "Unused3",    rawValue: 3),
            .init(name: "MoveViewer", rawValue: 4),  // room 999, waza_viewer
            .init(name: "Scene",      rawValue: 5),  // menus, logos, demos, cutscene-only rooms
            .init(name: "SystemMenu", rawValue: 6),  // title, top menu, battle-mode menu, flash menu
            .init(name: "BingoSheet", rawValue: 7),  // room 907, bingo_sheet
        ],
        propertyType: .uint8
    )

    /// Who drives a participant slot (`GSInputDevice`): the AI, or one of
    /// the four controller ports. Legacy `XGTrainerController`.
    public static let battleController = Enum(
        name: "BattleController",
        allowUnknownCases: true,
        values: [
            .init(name: "AI",      rawValue: 0),
            .init(name: "Player1", rawValue: 1),
            .init(name: "Player2", rawValue: 2),
            .init(name: "Player3", rawValue: 3),
            .init(name: "Player4", rawValue: 4),
        ],
        propertyType: .uint32
    )
}
