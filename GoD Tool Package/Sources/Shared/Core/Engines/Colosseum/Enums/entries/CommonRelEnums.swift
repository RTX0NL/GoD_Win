import Structs

/// Enums for the `common.rel` battle table. Colosseum numbers its battle
/// kinds differently from XD (1 is an admin battle here and unused there,
/// 10–16 are the e-Card and Battle Mode variants), so the game engine owns
/// the set. All use `allowUnknownCases: true` so a modded value still
/// round-trips.
public enum ColoCommonRelEnumDefaults {

    /// The row of the `BattleTypes` table that supplies a battle's rules.
    /// Names from the legacy tool's `XGBattleTypes`, Colosseum perspective.
    public static let battleKind = Enum(
        name: "BattleKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None",                          rawValue: 0),
            .init(name: "Admin",                         rawValue: 1),
            .init(name: "Story",                         rawValue: 2),
            .init(name: "ColosseumPreliminary",          rawValue: 3),
            .init(name: "Sample",                        rawValue: 4),
            .init(name: "ColosseumFinal",                rawValue: 5),
            .init(name: "PhenacColosseumPreliminary",    rawValue: 6),
            .init(name: "PhenacColosseumFinal",          rawValue: 7),
            .init(name: "MtBattle",                      rawValue: 8),
            .init(name: "MtBattleFinal",                 rawValue: 9),
            .init(name: "ECardPanelBattle",              rawValue: 10),
            .init(name: "ECardEndlessBattle",            rawValue: 11),
            .init(name: "BattleModeBattleNow",           rawValue: 12),
            .init(name: "BattleModeSoloColosseum",       rawValue: 13),
            .init(name: "BattleModeSoloColosseumFinal",  rawValue: 14),
            .init(name: "BattleModeMtBattle",            rawValue: 15),
            .init(name: "LinkBattle",                    rawValue: 16),
            .init(name: "ECardSpecialBattle",            rawValue: 17),
            .init(name: "BattleModeMtBattleFinal",       rawValue: 18),
        ],
        propertyType: .uint8
    )

    /// A battle's style: a row of the `BattleStyles` table, which the
    /// battle code looks the value up in (`fightTypeDataBiosGetPtr`). Not
    /// XD's "Pokémon out per side": Colosseum's rows are (trainers per side,
    /// Pokémon entered, Pokémon active), and its story battles are row 1.
    public static let battleStyle = Enum(
        name: "BattleStyle",
        allowUnknownCases: true,
        values: [
            .init(name: "Single",             rawValue: 0),
            .init(name: "Double",             rawValue: 1),
            .init(name: "Multi",              rawValue: 2),
            .init(name: "None",               rawValue: 3),
            .init(name: "SingleThreeEntered", rawValue: 4),
            .init(name: "DoubleFourEntered",  rawValue: 5),
            .init(name: "MultiTwoEntered",    rawValue: 6),
        ],
        propertyType: .uint8
    )

    /// A room's floor kind, stored in the top three bits of the `Rooms`
    /// record's first byte — so the raw values are the kind × 32. The low
    /// five bits are zero on every room of every disc and no routine reads
    /// them, so the whole byte is the enum; a modded value with low bits set
    /// still round-trips as `RoomKind_<n>`. The floor code branches on the
    /// kind everywhere a room is entered (lifecycle path, shadow cutoff and
    /// shadow-map size, fog, frame-rate mode), and the partition is the same
    /// as XD's. Named from the rooms that carry each value on the US disc;
    /// kinds 3 and 7 are handled by the code but no Colosseum room uses them.
    public static let roomKind = Enum(
        name: "RoomKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None",       rawValue: 0x00),  // room 0, fight_demo, auto_demo
            .init(name: "Field",      rawValue: 0x20),  // overworld maps the player walks in
            .init(name: "Battle",     rawValue: 0x40),  // colosseums and the per-town battle arenas
            .init(name: "Unused3",    rawValue: 0x60),
            .init(name: "MoveViewer", rawValue: 0x80),  // room 999, waza_viewer
            .init(name: "Scene",      rawValue: 0xA0),  // menus, logos, demos, the Snagem Hideout intro rooms
            .init(name: "SystemMenu", rawValue: 0xC0),  // title, top menu, battle-mode menu
            .init(name: "Unused7",    rawValue: 0xE0),
        ],
        propertyType: .uint8
    )

    /// Who drives a participant slot: the AI, or one of the four controller
    /// ports. Legacy `XGTrainerController`.
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

    /// A mart's kind (the pocket menu's shop switch on the mart list's
    /// +0x01): 0 runs the shop, 1 the vending machine, 2 and up the coupon
    /// exchange in that mode.
    public static let shopKind = Enum(
        name: "ShopKind",
        allowUnknownCases: true,
        values: [
            .init(name: "Shop",              rawValue: 0),
            .init(name: "VendingMachine",    rawValue: 1),
            .init(name: "MemoryCardCoupons", rawValue: 2),
            .init(name: "GBACoupons",        rawValue: 3),
            .init(name: "PokeCoupons",       rawValue: 4),
        ],
        propertyType: .uint8
    )

    /// How an interaction point triggers. The event code is called with a
    /// constant method and logs it as "pass", "touch", "check" or "menu
    /// event".
    public static let interactionMethod = Enum(
        name: "InteractionMethod",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "Pass", rawValue: 1),
            .init(name: "Touch", rawValue: 2),
            .init(name: "Check", rawValue: 3),
            .init(name: "Menu", rawValue: 4),
        ],
        propertyType: .uint8
    )

    /// A battlefield's terrain: a row of the DOL terrain table (camouflage
    /// type, Secret Power effect, Nature Power move). Gen III's terrains
    /// without Plain.
    public static let battleTerrain = Enum(
        name: "BattleTerrain",
        allowUnknownCases: true,
        values: [
            .init(name: "Grass", rawValue: 0),
            .init(name: "LongGrass", rawValue: 1),
            .init(name: "Sand", rawValue: 2),
            .init(name: "Underwater", rawValue: 3),
            .init(name: "Water", rawValue: 4),
            .init(name: "Pond", rawValue: 5),
            .init(name: "Mountain", rawValue: 6),
            .init(name: "Cave", rawValue: 7),
            .init(name: "Building", rawValue: 8),
        ],
        propertyType: .uint8
    )

    /// What a met-location record tells the Shadow Pokémon screens: the
    /// callers switch on it — 0 prints "???", 1 the location, 2 the
    /// trainer. Names are read from the branches.
    public static let shadowSightingState = Enum(
        name: "ShadowSightingState",
        allowUnknownCases: true,
        values: [
            .init(name: "Unknown", rawValue: 0),
            .init(name: "LocationKnown", rawValue: 1),
            .init(name: "TrainerKnown", rawValue: 2),
        ],
        propertyType: .uint8
    )

    /// A script builtin's argument type, as `callStandard` marshals it:
    /// 0 ends the list, 2 is a float, anything else an int.
    public static let scriptArgType = Enum(
        name: "ScriptArgType",
        allowUnknownCases: true,
        values: [
            .init(name: "End", rawValue: 0),
            .init(name: "Int", rawValue: 1),
            .init(name: "Float", rawValue: 2),
        ],
        propertyType: .uint8
    )

    /// Which loaded script a function lives in: the high half of a runtime
    /// script handle, matched against the u16 at +0 of each loaded script.
    /// The values are the scripts' own header ids.
    public static let scriptKind = Enum(
        name: "ScriptKind",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0x0000),
            .init(name: "Map", rawValue: 0x0100),
            .init(name: "Menu", rawValue: 0x0200),
            .init(name: "TitleMenu", rawValue: 0x0201),
            .init(name: "Battle", rawValue: 0x0300),
            .init(name: "Common", rawValue: 0x0596),
        ],
        propertyType: .uint16
    )

    /// A room's area. The game only compares areas for equality; the names
    /// come from the rooms in each.
    public static let area = Enum(
        name: "Area",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "OutskirtStand", rawValue: 1),
            .init(name: "PhenacCity", rawValue: 2),
            .init(name: "PyriteTown", rawValue: 3),
            .init(name: "AgateVillage", rawValue: 4),
            .init(name: "TheUnder", rawValue: 5),
            .init(name: "ShadowPokemonLab", rawValue: 6),
            .init(name: "MtBattle", rawValue: 7),
            .init(name: "RealgamTower", rawValue: 8),
            .init(name: "System", rawValue: 9),
            .init(name: "SnagemHideout", rawValue: 10),
        ],
        propertyType: .uint8
    )

    /// An item's held effect, in Gen III's `HOLD_EFFECT_*` order (pokeemerald
    /// `include/constants/hold_effects.h`). Evolution compares it with
    /// `PreventEvolve` (38) and friendship with `FriendshipUp` (27).
    public static let holdEffect = Enum(
        name: "HoldEffect",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "RestoreHP", rawValue: 1),
            .init(name: "CureParalysis", rawValue: 2),
            .init(name: "CureSleep", rawValue: 3),
            .init(name: "CurePoison", rawValue: 4),
            .init(name: "CureBurn", rawValue: 5),
            .init(name: "CureFreeze", rawValue: 6),
            .init(name: "RestorePP", rawValue: 7),
            .init(name: "CureConfusion", rawValue: 8),
            .init(name: "CureStatus", rawValue: 9),
            .init(name: "ConfuseSpicy", rawValue: 10),
            .init(name: "ConfuseDry", rawValue: 11),
            .init(name: "ConfuseSweet", rawValue: 12),
            .init(name: "ConfuseBitter", rawValue: 13),
            .init(name: "ConfuseSour", rawValue: 14),
            .init(name: "AttackUp", rawValue: 15),
            .init(name: "DefenseUp", rawValue: 16),
            .init(name: "SpeedUp", rawValue: 17),
            .init(name: "SpAttackUp", rawValue: 18),
            .init(name: "SpDefenseUp", rawValue: 19),
            .init(name: "CriticalUp", rawValue: 20),
            .init(name: "RandomStatUp", rawValue: 21),
            .init(name: "EvasionUp", rawValue: 22),
            .init(name: "RestoreStats", rawValue: 23),
            .init(name: "MachoBrace", rawValue: 24),
            .init(name: "ExpShare", rawValue: 25),
            .init(name: "QuickClaw", rawValue: 26),
            .init(name: "FriendshipUp", rawValue: 27),
            .init(name: "CureAttract", rawValue: 28),
            .init(name: "ChoiceBand", rawValue: 29),
            .init(name: "Flinch", rawValue: 30),
            .init(name: "BugPower", rawValue: 31),
            .init(name: "DoublePrize", rawValue: 32),
            .init(name: "Repel", rawValue: 33),
            .init(name: "SoulDew", rawValue: 34),
            .init(name: "DeepSeaTooth", rawValue: 35),
            .init(name: "DeepSeaScale", rawValue: 36),
            .init(name: "CanAlwaysRun", rawValue: 37),
            .init(name: "PreventEvolve", rawValue: 38),
            .init(name: "FocusBand", rawValue: 39),
            .init(name: "LuckyEgg", rawValue: 40),
            .init(name: "ScopeLens", rawValue: 41),
            .init(name: "SteelPower", rawValue: 42),
            .init(name: "Leftovers", rawValue: 43),
            .init(name: "DragonScale", rawValue: 44),
            .init(name: "LightBall", rawValue: 45),
            .init(name: "GroundPower", rawValue: 46),
            .init(name: "RockPower", rawValue: 47),
            .init(name: "GrassPower", rawValue: 48),
            .init(name: "DarkPower", rawValue: 49),
            .init(name: "FightingPower", rawValue: 50),
            .init(name: "ElectricPower", rawValue: 51),
            .init(name: "WaterPower", rawValue: 52),
            .init(name: "FlyingPower", rawValue: 53),
            .init(name: "PoisonPower", rawValue: 54),
            .init(name: "IcePower", rawValue: 55),
            .init(name: "GhostPower", rawValue: 56),
            .init(name: "PsychicPower", rawValue: 57),
            .init(name: "FirePower", rawValue: 58),
            .init(name: "DragonPower", rawValue: 59),
            .init(name: "NormalPower", rawValue: 60),
            .init(name: "UpGrade", rawValue: 61),
            .init(name: "ShellBell", rawValue: 62),
            .init(name: "LuckyPunch", rawValue: 63),
            .init(name: "MetalPowder", rawValue: 64),
            .init(name: "ThickClub", rawValue: 65),
            .init(name: "Stick", rawValue: 66),
        ],
        propertyType: .uint16
    )
}
