import Structs

/// Enums for XD save-slot struct fields — small, universal value sets
/// that read better as strings than opaque integer indexes. All use
/// `allowUnknownCases: true` so a modded/out-of-range value still
/// round-trips (it's carried as a reversible `<Enum>_<n>` case) rather
/// than failing to rebuild.
public enum XDSaveEnumDefaults {

    /// Trainer / OT gender (`sexDataId`). Values from the legacy tool's
    /// `XGGenders`.
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

    /// GameCube system language (`gcLanguage`). Values from the legacy
    /// tool's `XGLanguages`.
    public static let language = Enum(
        name: "Language",
        allowUnknownCases: true,
        values: [
            .init(name: "japanese",  rawValue: 0),
            .init(name: "englishUK", rawValue: 1),
            .init(name: "englishUS", rawValue: 2),
            .init(name: "german",    rawValue: 3),
            .init(name: "french",    rawValue: 4),
            .init(name: "italian",   rawValue: 5),
            .init(name: "spanish",   rawValue: 6),
        ],
        propertyType: .uint8
    )

    /// Build region (`currentRegion` / `originalRegion`). **TENTATIVE**:
    /// the region id is a per-build hardcoded constant returned by a
    /// region function in the DOL; confirming the exact mapping needs all
    /// three regional builds disassembled. jp/us/pal = 1/3/2 is the
    /// working assumption (a real US save's currentRegion reads 3, i.e.
    /// us=3) — override in engine data once confirmed. (Unknown values
    /// round-trip as `Region_<n>`.)
    public static let region = Enum(
        name: "Region",
        allowUnknownCases: true,
        values: [
            .init(name: "japan",  rawValue: 1),
            .init(name: "us",     rawValue: 3),
            .init(name: "pal",    rawValue: 2),
        ],
        propertyType: .uint8
    )

    /// Origin game / game index (`gcGameIndex`). Values from the legacy
    /// tool's `GenIIIGames` — the GC games mark 11 (colosseumXD); GBA
    /// migrations carry their own value.
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

    /// Non-volatile status condition (`condition`). Values from the
    /// legacy tool's `XGNonVolatileStatusEffects`.
    public static let statusCondition = Enum(
        name: "StatusCondition",
        allowUnknownCases: true,
        values: [
            .init(name: "none",       rawValue: 0),
            .init(name: "poison",     rawValue: 3),
            .init(name: "badPoison",  rawValue: 4),
            .init(name: "paralysis",  rawValue: 5),
            .init(name: "burn",       rawValue: 6),
            .init(name: "freeze",     rawValue: 7),
            .init(name: "sleep",      rawValue: 8),
        ],
        propertyType: .uint8
    )
}
