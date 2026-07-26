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

    /// In-game language id. Disasm-confirmed: `japanese=1`, `englishUS=2`
    /// (the legacy `XGLanguages` had `japanese=0` — WRONG for these
    /// games; slot 1 is Japanese, so there is no separate `englishUK`).
    /// European ids follow the legacy order at their legacy values:
    /// german=3, french=4, italian=5, spanish=6. Used for the Config
    /// `gcLanguage` byte (which holds a real language on single-language
    /// builds; PAL's Config byte is a `langAreaId`=8 grouping → dumps as
    /// `Language_8`) and the Pokémon `language` byte.
    public static let language = Enum(
        name: "Language",
        allowUnknownCases: true,
        values: [
            .init(name: "japanese",  rawValue: 1),
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
    /// build's `AreaId` (the Config/GamedataAttest byte the disasm names
    /// `areaId`, PKHeX calls `originalRegion`). Confirmed from the
    /// new-game routine's country-code switch (`gamedataAttestCreate`
    /// branches): **jp=1, us=2, pal=3** — matches real saves (US=2,
    /// JP=1). NOTE: the *other* region byte (`genId`, PKHeX
    /// `currentRegion`) is a hardcoded constant 3 on every build and is
    /// NOT a region. (Unknown values round-trip as `Region_<n>`.)
    public static let region = Enum(
        name: "Region",
        allowUnknownCases: true,
        values: [
            .init(name: "japan",  rawValue: 1),
            .init(name: "us",     rawValue: 2),
            .init(name: "pal",    rawValue: 3),
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
