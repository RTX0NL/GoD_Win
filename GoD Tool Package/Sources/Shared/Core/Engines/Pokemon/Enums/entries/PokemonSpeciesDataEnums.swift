import Structs

/// Enums for fields of the per-species data record. Both are the GBA-era
/// encodings that Colosseum and XD inherited unchanged, so they sit beside
/// the other fixed cross-game enums rather than in a game engine.
public extension PokemonEnumDefaults {

    /// Gender ratio byte (`sexRatio`): the chance of a female, in 256ths,
    /// with the two sentinels for single-gender and genderless species.
    /// Values from the legacy tool's `XGGenderRatios`; the XD species table
    /// carries every one of them and nothing else.
    static let genderRatiosEnum = Enum(
        name: "GenderRatio",
        allowUnknownCases: true,
        values: [
            .init(name: "MaleOnly",   rawValue: 0x00),
            .init(name: "Male87_5",   rawValue: 0x1F),
            .init(name: "Male75",     rawValue: 0x3F),
            .init(name: "Male50",     rawValue: 0x7F),
            .init(name: "Female75",   rawValue: 0xBF),
            .init(name: "Female87_5", rawValue: 0xDF),
            .init(name: "FemaleOnly", rawValue: 0xFE),
            .init(name: "Genderless", rawValue: 0xFF),
        ],
        propertyType: .uint8
    )

    /// Evolution method (`sinkaKind`, 進化 = "evolution"). What the
    /// companion `condition` field means depends on the method: a level for
    /// the level-based methods, an item id for the item-based ones, nothing
    /// for the rest. Values from the legacy tool's `XGEvolutionMethods`.
    static let evolutionMethodsEnum = Enum(
        name: "EvolutionMethod",
        allowUnknownCases: true,
        values: [
            .init(name: "None",                  rawValue: 0x00),
            .init(name: "MaxHappiness",          rawValue: 0x01),
            .init(name: "HappinessDay",          rawValue: 0x02),
            .init(name: "HappinessNight",        rawValue: 0x03),
            .init(name: "LevelUp",               rawValue: 0x04),
            .init(name: "Trade",                 rawValue: 0x05),
            .init(name: "TradeWithItem",         rawValue: 0x06),
            .init(name: "EvolutionStone",        rawValue: 0x07),
            .init(name: "LevelUpAttackHigher",   rawValue: 0x08),
            .init(name: "LevelUpAttackEqual",    rawValue: 0x09),
            .init(name: "LevelUpDefenseHigher",  rawValue: 0x0A),
            .init(name: "LevelUpSilcoon",        rawValue: 0x0B),
            .init(name: "LevelUpCascoon",        rawValue: 0x0C),
            .init(name: "LevelUpNinjask",        rawValue: 0x0D),
            .init(name: "LevelUpShedinja",       rawValue: 0x0E),
            .init(name: "MaxBeauty",             rawValue: 0x0F),
            .init(name: "LevelUpWithKeyItem",    rawValue: 0x10),
        ],
        propertyType: .uint8
    )
}
