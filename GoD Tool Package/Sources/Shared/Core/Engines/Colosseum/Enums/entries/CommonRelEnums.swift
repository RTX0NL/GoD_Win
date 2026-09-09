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

    /// Single, double or multi battle. Legacy `XGBattleStyles`.
    public static let battleStyle = Enum(
        name: "BattleStyle",
        allowUnknownCases: true,
        values: [
            .init(name: "None",   rawValue: 0),
            .init(name: "Single", rawValue: 1),
            .init(name: "Double", rawValue: 2),
            .init(name: "Multi",  rawValue: 3),
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
}
