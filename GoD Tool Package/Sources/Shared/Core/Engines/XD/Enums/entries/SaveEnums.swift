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
}
