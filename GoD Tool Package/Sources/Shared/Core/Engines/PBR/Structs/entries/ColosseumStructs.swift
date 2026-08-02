import Foundation
import Structs

/// Colosseum (battle venue) tables in `common.fsys`, and the Poké Coupon
/// shop. "Colosseum" here is a PBR battle venue, unrelated to the GameCube
/// game of the same name.
///
/// Ported from the legacy tool's
/// `Revolution Tool CL/structs/ColosseumsTable.swift` and
/// `SmallStructTables.swift`.
public extension PBRStructDefaults {

    /// A colosseum's trainer deck binding (0x10 / 16 bytes).
    static let colosseumTrainerDeckStruct = StructMap(
        name: "PBRColosseumTrainerDeck",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .array(name: "unused", count: 3, of: .uint8),
            // 0x03: Index within the deck of this venue's first trainer;
            // later rounds use consecutive indexes from there.
            .int8(name: "first_trainer_index"),
            // 0x04: Files in `deck.fsys`.
            .uint32(name: "deck_file_id"),
            .uint32(name: "ai_deck_file_id"),
            // 0x0C
            .uint8(name: "unknown_2"),
            // 0x0D: Alignment filler (0xD0 on every row of both deck slots).
            .padding(length: 3),
        ],
        description: "Which trainer deck a colosseum draws from, and where in it this venue's roster starts."
    )

    /// A colosseum's Pokémon deck pair (0x08 / 8 bytes).
    static let colosseumPokemonDecksStruct = StructMap(
        name: "PBRColosseumPokemonDecks",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "main_deck_file_id"),
            .uint32(name: "boss_deck_file_id"),
        ],
        description: "The regular and boss Pokémon decks for one colosseum format."
    )

    /// One colosseum (0x5C / 92 bytes). Most of the tail is undocumented —
    /// the legacy tool named only the rules message id there.
    static let colosseumStruct = StructMap(
        name: "PBRColosseum",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00
            .subStruct(name: "boss_trainer_deck", typeName: "PBRColosseumTrainerDeck"),
            // 0x10
            .subStruct(name: "main_trainer_deck", typeName: "PBRColosseumTrainerDeck"),
            // 0x20
            .subStruct(name: "singles_pokemon_decks", typeName: "PBRColosseumPokemonDecks"),
            // 0x28
            .subStruct(name: "doubles_pokemon_decks", typeName: "PBRColosseumPokemonDecks"),

            // 0x30
            .uint16(name: "unknown_1"),
            .uint16(name: "unknown_2"),
            .uint16(name: "unknown_3"),
            .uint16(name: "unknown_4"),
            .uint16(name: "unknown_5"),
            .uint16(name: "unknown_6"),
            .uint16(name: "unknown_7"),
            .padding(length: 2),

            // 0x40
            .int8(name: "unknown_8"),
            // 0x41: Alignment filler (0xD0 on every row).
            .padding(length: 1),
            .uint16(name: "unknown_10"),
            .padding(length: 2),
            .int8(name: "unknown_11"),
            // 0x47: Alignment filler (0xD0 on every row).
            .padding(length: 1),

            // 0x48: Message id for the venue's rules text.
            .uint16(name: "rules_message_id"),
            .array(name: "unknown_values", count: 15, of: .uint8),
            // 0x59: Alignment filler (0xD0 on every row).
            .padding(length: 3),
        ],
        description: "One battle venue: the trainer and Pokémon decks it draws from, plus its rules text."
    )

    /// One Poké Coupon shop reward (0x0C / 12 bytes).
    static let pokeCouponRewardStruct = StructMap(
        name: "PBRPokeCouponReward",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: Price in thousands of coupons — multiply by 1000.
            .int16(name: "price_in_thousands"),
            // 0x02: Species id or item id, per the `is_pokemon` flag below.
            .uint16(name: "pokemon_or_item_id"),
            .uint16(name: "name_message_id"),
            .uint16(name: "description_message_id"),
            .uint16(name: "unknown_id"),
            // 0x0A: Bit 7 (the most significant) marks the reward as a
            // Pokémon rather than an item.
            .uint8(name: "flags"),
            .padding(length: 1),
        ],
        description: "One purchasable Poké Coupon reward: price, what it grants, and its menu strings."
    )
}
