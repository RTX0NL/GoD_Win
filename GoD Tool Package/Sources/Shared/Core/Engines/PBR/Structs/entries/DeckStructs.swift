import Foundation
import Structs

/// `deck.fsys` table formats: the Pokémon (`dckp`), trainer (`dckt`) and AI
/// (`dcka`) decks. Each deck file is a 0x10 header (`DCK?` magic, total size,
/// entry count at +0x08, reserved) followed by an entry array that tiles
/// exactly — no string pool or name/relocation tables.
///
/// Ported from the legacy tool's
/// `Revolution Tool CL/structs/DeckStructTable.swift`. All strides verified
/// against the PAL disc: dckp 0x38, dckt 0x98, dcka 0x24.
public extension PBRStructDefaults {

    /// The 0x10 header every `deck.fsys` table shares.
    static let deckHeaderStruct = StructMap(
        name: "PBRDeckHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .array(name: "magic", count: 4, of: .uint8),   // "DCKP"/"DCKT"/"DCKA"
            .uint32(name: "total_size"),
            .uint32(name: "entry_count"),
            .padding(length: 4)
        ],
        description: "Header of a deck.fsys table: magic, total size, entry count."
    )

    // MARK: - Trainer deck (dckt, 0x98)

    /// Four message-table ids for one line a trainer can say (0x10).
    static let trainerDeckMessagesStruct = StructMap(
        name: "PBRTrainerDeckMessages",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [.array(name: "variants", count: 4, of: .uint32)]
    )

    /// A trainer's customisation (0x0C).
    static let trainerDeckAppearanceStruct = StructMap(
        name: "PBRTrainerDeckAppearance",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "body"),
            .uint8(name: "head"), .uint8(name: "hair"), .uint8(name: "face"),
            .uint8(name: "top"), .uint8(name: "bottom"), .uint8(name: "shoes"),
            .uint8(name: "hands"), .uint8(name: "bag"), .uint8(name: "glasses"),
            .uint8(name: "badge")
        ]
    )

    /// One of a trainer's four Pokémon-pool selectors (0x08).
    static let trainerDeckPoolStruct = StructMap(
        name: "PBRTrainerDeckPool",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_flag_1"),
            .uint8(name: "unknown_flag_2"),
            .uint8(name: "number_of_pokemon"),
            .padding(length: 1),
            .uint16(name: "pokemon_pool_start"),
            .uint16(name: "pokemon_pool_end")
        ]
    )

    static let trainerDeckStruct = StructMap(
        name: "PBRTrainerDeck",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "index"),
            .uint16(name: "battle_pass_background"),
            .padding(length: 2),
            .uint16(name: "name_message_id"),
            .padding(length: 2),
            .uint16(name: "title_message_id"),
            .uint8(name: "unknown_3"), .uint8(name: "unknown_4"),
            .uint8(name: "unknown_5"), .uint8(name: "unknown_6"),
            .subStruct(name: "appearance", typeName: "PBRTrainerDeckAppearance"),
            .subStruct(name: "before_battle", typeName: "PBRTrainerDeckMessages"),
            .subStruct(name: "battle_start", typeName: "PBRTrainerDeckMessages"),
            .subStruct(name: "defeated", typeName: "PBRTrainerDeckMessages"),
            .subStruct(name: "victory", typeName: "PBRTrainerDeckMessages"),
            .uint8(name: "skin_tone"),
            .array(name: "unknown_value_lists", count: 3, of: .uint8),
            .array(name: "pokemon_themes", count: 4, of: .uint8),
            .subStruct(name: "pokemon_pool_1", typeName: "PBRTrainerDeckPool"),
            .subStruct(name: "pokemon_pool_2", typeName: "PBRTrainerDeckPool"),
            .subStruct(name: "pokemon_pool_3", typeName: "PBRTrainerDeckPool"),
            .subStruct(name: "pokemon_pool_4", typeName: "PBRTrainerDeckPool"),
            .array(name: "unknown_values_1", count: 4, of: .uint8),
            .uint16(name: "singles_ai"),
            .uint16(name: "doubles_ai"),
            .array(name: "unknown_values_2", count: 12, of: .uint8)
        ],
        description: "One trainer in the trainer deck: identity, appearance, battle quotes, team themes and pools."
    )

    // MARK: - Pokémon deck (dckp, 0x38)

    static let pokemonDeckStatsStruct = StructMap(
        name: "PBRPokemonDeckStats",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "hp"), .uint8(name: "attack"), .uint8(name: "defense"),
            .uint8(name: "speed"), .uint8(name: "special_attack"), .uint8(name: "special_defense")
        ]
    )

    static let pokemonDeckEVsStruct = StructMap(
        name: "PBRPokemonDeckEVs",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "ev_total"),
            .subStruct(name: "ratios", typeName: "PBRPokemonDeckStats")
        ]
    )

    static let pokemonDeckStruct = StructMap(
        name: "PBRPokemonDeck",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "id"),
            .uint16(name: "flags"),
            .uint16(name: "minimum_level"),
            .uint16(name: "species"),
            .array(name: "types", count: 2, of: .uint8),
            .uint8(name: "pokeball"),
            .uint8(name: "gender"),
            .uint8(name: "nature"),
            .uint8(name: "forme_id"),
            .uint8(name: "average_rank"),
            .uint8(name: "unknown_4"),
            .subStruct(name: "ivs", typeName: "PBRPokemonDeckStats"),
            .subStruct(name: "evs", typeName: "PBRPokemonDeckEVs"),
            .uint16(name: "unknown_5"),
            .array(name: "moves", count: 4, of: .uint16),
            .array(name: "items", count: 4, of: .uint16),
            .uint8(name: "unknown_6"),
            .padding(length: 3),
            .uint32(name: "unknown_7")
        ],
        description: "One Pokémon slot in a deck: species, level, IVs/EVs, moves and held items."
    )

    // MARK: - AI deck (dcka, 0x24)

    static let aiDeckStruct = StructMap(
        name: "PBRAIDeck",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .array(name: "parameters", count: 4, of: .uint8),
            .array(name: "values", count: 0x20, of: .uint8)
        ],
        description: "One AI behaviour entry (largely unmapped)."
    )
}
