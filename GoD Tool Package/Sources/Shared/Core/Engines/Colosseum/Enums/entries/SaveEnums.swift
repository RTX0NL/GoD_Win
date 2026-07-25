import Structs

/// Enums for Colosseum save-slot struct fields. (`Language` already
/// lives in `ColoScriptEnumDefaults`.) `allowUnknownCases: true` keeps
/// modded/out-of-range values round-trippable.
public enum ColoSaveEnumDefaults {

    /// OT gender. Values from the legacy tool's `XGGenders`.
    public static let gender = Enum(
        name: "Gender",
        allowUnknownCases: true,
        values: [
            .init(name: "male",       rawValue: 0),
            .init(name: "female",     rawValue: 1),
            .init(name: "genderless", rawValue: 2),
        ],
        propertyType: .uint8
    )

    /// Build region (`currentRegion` / `originalRegion`). **TENTATIVE**
    /// jp/us/pal = 1/3/2 — per-build region id, confirm via disassembly
    /// of all three regional builds; override in engine data if needed.
    public static let region = Enum(
        name: "Region",
        allowUnknownCases: true,
        values: [
            .init(name: "japan", rawValue: 1),
            .init(name: "us",    rawValue: 3),
            .init(name: "pal",   rawValue: 2),
        ],
        propertyType: .uint8
    )

    /// Origin game (`version` / `gcGameIndex`). Values from the legacy
    /// tool's `GenIIIGames`.
    public static let gameVersion = Enum(
        name: "GameVersion",
        allowUnknownCases: true,
        values: [
            .init(name: "none",        rawValue: 0),
            .init(name: "fireRed",     rawValue: 1),
            .init(name: "leafGreen",   rawValue: 2),
            .init(name: "sapphire",    rawValue: 8),
            .init(name: "ruby",        rawValue: 9),
            .init(name: "emerald",     rawValue: 10),
            .init(name: "colosseumXD", rawValue: 11),
        ],
        propertyType: .uint8
    )

    /// Which of a species' two abilities is active (`abilityBit`).
    public static let abilitySlot = Enum(
        name: "AbilitySlot",
        allowUnknownCases: true,
        values: [
            .init(name: "ability1", rawValue: 0),
            .init(name: "ability2", rawValue: 1),
        ],
        propertyType: .uint8
    )
}
