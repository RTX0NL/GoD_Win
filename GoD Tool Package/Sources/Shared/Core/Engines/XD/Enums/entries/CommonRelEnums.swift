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

    /// A Battle Bingo mystery panel's reward (`menuBingoSheetBtn`). Every
    /// card carries exactly one of each of 1, 2 and 3.
    public static let battleBingoMysteryPanelKind = Enum(
        name: "BattleBingoMysteryPanelKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None",        rawValue: 0),
            .init(name: "MasterBall",  rawValue: 1),
            .init(name: "EnergyPlus1", rawValue: 2),
            .init(name: "EnergyPlus2", rawValue: 3),
        ],
        propertyType: .uint8
    )

    /// A mart's kind (`menuShopMain`'s switch on the mart list's +0x01):
    /// 0, 5 and 6 run the shop, 1 the vending machine, 2-4 the coupon
    /// exchange in that mode. The title message is a DOL table indexed by it.
    public static let shopKind = Enum(
        name: "ShopKind",
        allowUnknownCases: true,
        values: [
            .init(name: "Shop",              rawValue: 0),
            .init(name: "VendingMachine",    rawValue: 1),
            .init(name: "MemoryCardCoupons", rawValue: 2),
            .init(name: "GBACoupons",        rawValue: 3),
            .init(name: "PokeCoupons",       rawValue: 4),
            .init(name: "BattleCDs",         rawValue: 5),
            .init(name: "HerbShop",          rawValue: 6),
        ],
        propertyType: .uint8
    )

    /// Which matchup sprite the status screen draws for a move against the
    /// target (`menuPokemonStatusDrawWaza`'s 16-way jump table on Move +0x15).
    public static let moveMatchupDisplay = Enum(
        name: "MoveMatchupDisplay",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "TypeChart", rawValue: 1),
            .init(name: "Shadow", rawValue: 2),
            .init(name: "NoTarget", rawValue: 3),
            .init(name: "IneffectiveOnGhost", rawValue: 4),
            .init(name: "IneffectiveOnGrass", rawValue: 5),
            .init(name: "IneffectiveOnPoisonSteel", rawValue: 6),
            .init(name: "IneffectiveOnGround", rawValue: 7),
            .init(name: "IneffectiveOnFlying", rawValue: 8),
            .init(name: "IneffectiveOnNormal", rawValue: 9),
            .init(name: "Variable", rawValue: 10),
            .init(name: "VariableHiddenPower", rawValue: 11),
            .init(name: "IneffectiveOnDark", rawValue: 12),
            .init(name: "IneffectiveOnFire", rawValue: 13),
            .init(name: "VariableWeatherBall", rawValue: 14),
            .init(name: "AlwaysNeutral", rawValue: 15),
        ],
        propertyType: .uint8
    )

    /// Who follows the player after a story-checkpoint warp
    /// (`heroSetFollowerWithID`); `Girl` is the unnamed `girl_1000` model.
    public static let follower = Enum(
        name: "Follower",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "Jovi", rawValue: 1),
            .init(name: "Girl", rawValue: 2),
            .init(name: "Krane", rawValue: 3),
        ],
        propertyType: .uint8
    )

    /// What a treasure looks like. The game reads the top three bits
    /// (`_floorInitTresure`: 1 chest, 2 sparkle, 3 book); the low five are 4
    /// on every row and unread, so the whole byte is the enum, as with
    /// Colosseum's `RoomKind`.
    public static let treasureKind = Enum(
        name: "TreasureKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0x00),
            .init(name: "Chest", rawValue: 0x24),
            .init(name: "Sparkle", rawValue: 0x44),
            .init(name: "Book", rawValue: 0x64),
        ],
        propertyType: .uint8
    )

    /// A room's area. The game only compares areas for equality (moving to
    /// a new area clears flag level 2); the names come from the rooms'
    /// place-name messages.
    public static let area = Enum(
        name: "Area",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "OutskirtStand", rawValue: 1),
            .init(name: "PhenacCity", rawValue: 2),
            .init(name: "PyriteTown", rawValue: 3),
            .init(name: "AgateVillage", rawValue: 4),
            .init(name: "PokemonHQLab", rawValue: 5),
            .init(name: "GateonPort", rawValue: 6),
            .init(name: "CipherLab", rawValue: 7),
            .init(name: "MtBattle", rawValue: 8),
            .init(name: "SSLibra", rawValue: 9),
            .init(name: "RealgamTower", rawValue: 10),
            .init(name: "CipherKeyLair", rawValue: 11),
            .init(name: "CitadarkIsle", rawValue: 12),
            .init(name: "CitadarkIsleD7", rawValue: 13),
            .init(name: "System", rawValue: 14),
            .init(name: "SnagemHideout", rawValue: 15),
            .init(name: "KaminkosHouse", rawValue: 16),
            .init(name: "Pokespots", rawValue: 17),
            .init(name: "Prototype", rawValue: 18),
        ],
        propertyType: .uint8
    )

    /// A field camera's area: the camera code tests for 0 and treats
    /// anything else as a box.
    public static let cameraAreaShape = Enum(
        name: "CameraAreaShape",
        allowUnknownCases: true,
        values: [
            .init(name: "Circle", rawValue: 0),
            .init(name: "Box", rawValue: 1),
        ],
        propertyType: .uint8
    )

    /// What an offscreen texture renders: 0 opens a model, anything else
    /// plays a movie (`floorSetOffscreenIndex`).
    public static let offscreenSource = Enum(
        name: "OffscreenSource",
        allowUnknownCases: true,
        values: [
            .init(name: "Model", rawValue: 0),
            .init(name: "Movie", rawValue: 1),
        ],
        propertyType: .uint8
    )
}
