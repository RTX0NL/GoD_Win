//
//  PokemonMoveEnums.swift
//  Pokemon
//
//  The small fixed-cardinality enums that describe *how* a move or item
//  behaves, as opposed to which one it is. Ported from the legacy GoD tool's
//  enumerables (see Documentation/Credits & References.md) and checked against
//  the discs where the games disagree.
//
//  Split col/xd vs pbr because the two generations genuinely differ:
//  Colosseum and XD number move targets sequentially while Battle Revolution
//  uses a bitmask, and the two move-category schemes don't line up at all.
//

import Structs

public extension PokemonEnumDefaults {

    // MARK: - Colosseum / XD

    /// Sequential in the GameCube games, one value per targeting mode.
    static let coloXdMoveTargetEnum = Enum(
        name: "MoveTarget",
        allowUnknownCases: true,
        values: [
            .init(name: "SelectedTarget", rawValue: 0x00),
            .init(name: "DependsOnMove", rawValue: 0x01),
            .init(name: "AllPokemon", rawValue: 0x02),
            .init(name: "Random", rawValue: 0x03),
            .init(name: "BothFoes", rawValue: 0x04),
            .init(name: "User", rawValue: 0x05),
            .init(name: "BothFoesAndAlly", rawValue: 0x06),
            .init(name: "OpponentField", rawValue: 0x07),
        ],
        propertyType: .uint8
    )

    /// Generation III ordering, where 0 means "no damage" (status).
    static let coloXdMoveCategoryEnum = Enum(
        name: "MoveCategory",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "Physical", rawValue: 1),
            .init(name: "Special", rawValue: 2),
        ],
        propertyType: .uint8
    )

    static let coloXdMoveEffectTypeEnum = Enum(
        name: "MoveEffectType",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0x00),
            .init(name: "Attack", rawValue: 0x01),
            .init(name: "Healing", rawValue: 0x02),
            .init(name: "StatNerf", rawValue: 0x03),
            .init(name: "StatBuff", rawValue: 0x04),
            .init(name: "StatusEffect", rawValue: 0x05),
            .init(name: "FieldEffect", rawValue: 0x06),
            .init(name: "AffectsIncomingMove", rawValue: 0x07),
            .init(name: "OHKO", rawValue: 0x08),
            .init(name: "MultiTurn", rawValue: 0x09),
            .init(name: "Misc", rawValue: 0x0A),
            .init(name: "Misc2", rawValue: 0x0B),
            .init(name: "Misc3", rawValue: 0x0C),
            .init(name: "Misc4", rawValue: 0x0D),
            .init(name: "Unknown", rawValue: 0x0E),
        ],
        propertyType: .uint8
    )

    static let coloXdContestCategoryEnum = Enum(
        name: "ContestCategory",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "Cool", rawValue: 1),
            .init(name: "Beauty", rawValue: 2),
            .init(name: "Cute", rawValue: 3),
            .init(name: "Smart", rawValue: 4),
            .init(name: "Tough", rawValue: 5),
        ],
        propertyType: .uint8
    )

    /// Bag pockets. Colosseum has seven (0...6); XD adds Battle CDs at 7, so
    /// one list covers both — the extra case simply never occurs in Colosseum
    /// data.
    static let coloXdItemPocketEnum = Enum(
        name: "ItemPocket",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "PokeBalls", rawValue: 1),
            .init(name: "Items", rawValue: 2),
            .init(name: "Berries", rawValue: 3),
            .init(name: "TMs", rawValue: 4),
            .init(name: "KeyItems", rawValue: 5),
            .init(name: "Colognes", rawValue: 6),
            .init(name: "BattleCDs", rawValue: 7),
        ],
        propertyType: .uint8
    )

    // MARK: - Battle Revolution

    /// A bitmask rather than a sequence, and 16 bits wide. Every move on the
    /// PAL disc carries exactly one flag (12 distinct values across 468 rows),
    /// so an enum reads correctly; a combined value would fall back to its
    /// integer, which still round-trips.
    static let pbrMoveTargetEnum = Enum(
        name: "MoveTarget",
        allowUnknownCases: true,
        values: [
            .init(name: "SelectedTarget", rawValue: 0x000),
            .init(name: "DependsOnMove", rawValue: 0x001),
            .init(name: "Random", rawValue: 0x002),
            .init(name: "BothFoes", rawValue: 0x004),
            .init(name: "BothFoesAndAlly", rawValue: 0x008),
            .init(name: "User", rawValue: 0x010),
            .init(name: "BothAllies", rawValue: 0x020),
            .init(name: "AllPokemon", rawValue: 0x040),
            .init(name: "OpponentField", rawValue: 0x080),
            .init(name: "Ally", rawValue: 0x100),
            .init(name: "UserOrAlly", rawValue: 0x200),
            .init(name: "SelectedFoe", rawValue: 0x400),
        ],
        propertyType: .uint16
    )

    /// Generation IV's physical/special split, which renumbers the field
    /// entirely: 0 is Physical here but "no damage" in Colosseum and XD.
    ///
    /// The legacy tool declares only Physical and Special; the PAL disc has a
    /// third value used 170 times, and named moves settle it — Tackle, Body
    /// Slam and Earthquake are 0, Ember, Surf and Thunderbolt are 1, Growl and
    /// Swords Dance are 2.
    static let pbrMoveCategoryEnum = Enum(
        name: "MoveCategory",
        allowUnknownCases: true,
        values: [
            .init(name: "Physical", rawValue: 0),
            .init(name: "Special", rawValue: 1),
            .init(name: "Status", rawValue: 2),
        ],
        propertyType: .uint8
    )

    static let pbrMoveEffectTypeEnum = Enum(
        name: "MoveEffectType",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "RegularAttack", rawValue: 1),
            .init(name: "Buff", rawValue: 2),
            .init(name: "FixedDamage", rawValue: 3),
            .init(name: "LeechSeed", rawValue: 4),
            .init(name: "Poison", rawValue: 5),
            .init(name: "Paralyse", rawValue: 6),
            .init(name: "Fissure", rawValue: 7),
            .init(name: "NightShade", rawValue: 8),
            .init(name: "VariableMove", rawValue: 9),
            .init(name: "HiddenPower", rawValue: 10),
            .init(name: "PsywaveMirrorCoat", rawValue: 11),
            .init(name: "Burn", rawValue: 12),
            .init(name: "WeatherBall", rawValue: 13),
            .init(name: "Nerf", rawValue: 14),
            .init(name: "ItemBasedType", rawValue: 15),
            .init(name: "Unknown", rawValue: 16),
        ],
        propertyType: .uint8
    )
}
