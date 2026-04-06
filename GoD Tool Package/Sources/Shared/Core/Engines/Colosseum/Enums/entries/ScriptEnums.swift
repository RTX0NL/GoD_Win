import Structs

/// Script-related enums for the Colosseum engine.
/// These are small enums with hardcoded cases used by script built-in functions.
public enum ColoScriptEnumDefaults {

    public static let battleResult = Enum(
        name: "BattleResult",
        allowUnknownCases: true,
        values: [
            .init(name: "none", rawValue: 0),
            .init(name: "lost", rawValue: 1),
            .init(name: "won", rawValue: 2),
            .init(name: "tied", rawValue: 3),
        ],
        propertyType: .uint8
    )

    public static let transitionID = Enum(
        name: "TransitionID",
        allowUnknownCases: true,
        values: [
            .init(name: "none", rawValue: 0),
            .init(name: "fadeInBlack", rawValue: 2),
            .init(name: "fadeOutBlack", rawValue: 3),
            .init(name: "fadeInWhite", rawValue: 4),
            .init(name: "fadeOutWhite", rawValue: 5),
        ],
        propertyType: .uint8
    )

    public static let buttonInput = Enum(
        name: "ButtonInput",
        allowUnknownCases: true,
        values: [
            .init(name: "dPadLeft", rawValue: 0x1),
            .init(name: "dPadRight", rawValue: 0x2),
            .init(name: "dPadDown", rawValue: 0x4),
            .init(name: "dPadUp", rawValue: 0x8),
            .init(name: "triggerZ", rawValue: 0x10),
            .init(name: "triggerR", rawValue: 0x20),
            .init(name: "triggerL", rawValue: 0x40),
            .init(name: "buttonA", rawValue: 0x100),
            .init(name: "buttonB", rawValue: 0x200),
            .init(name: "buttonX", rawValue: 0x400),
            .init(name: "buttonY", rawValue: 0x800),
            .init(name: "buttonStart", rawValue: 0x1000),
        ],
        propertyType: .uint16
    )

    public static let language = Enum(
        name: "Language",
        allowUnknownCases: true,
        values: [
            .init(name: "japanese", rawValue: 0),
            .init(name: "englishUK", rawValue: 1),
            .init(name: "englishUS", rawValue: 2),
            .init(name: "german", rawValue: 3),
            .init(name: "french", rawValue: 4),
            .init(name: "italian", rawValue: 5),
            .init(name: "spanish", rawValue: 6),
        ],
        propertyType: .uint8
    )

    public static let yesNoIndex = Enum(
        name: "YesNoIndex",
        allowUnknownCases: false,
        values: [
            .init(name: "no", rawValue: 0),
            .init(name: "yes", rawValue: 1),
        ],
        propertyType: .uint8
    )

    public static let groupID = Enum(
        name: "GroupID",
        allowUnknownCases: true,
        values: [
            .init(name: "protagonists", rawValue: 0),
        ],
        propertyType: .uint16
    )

    public static let characterRID = Enum(
        name: "ResourceID",
        allowUnknownCases: true,
        values: [
            .init(name: "wes", rawValue: 100),
            .init(name: "rui", rawValue: 101),
        ],
        propertyType: .uint16
    )
}
