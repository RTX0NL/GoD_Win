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
}
