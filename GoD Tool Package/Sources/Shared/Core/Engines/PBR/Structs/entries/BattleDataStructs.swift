import Foundation
import Structs

/// Battle-system tables in `common.fsys`: moves, items, TMs, the type
/// matchup chart and the experience curves.
///
/// Ported from the legacy tool's `Revolution Tool CL/structs/*.swift`, with
/// the implicit C-style alignment pads written out explicitly.
public extension PBRStructDefaults {

    /// One move (0x18 / 24 bytes).
    static let moveStruct = StructMap(
        name: "PBRMove",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Secondary effect id.
            .uint16(name: "effect"),
            // 0x02: Which battlers the move may target.
            .uint16(name: "targets"),
            // 0x04: Unused as far as the legacy tool could tell.
            .uint16(name: "unknown"),
            // 0x06: Contest appeal category, carried over from the handheld
            // games' move data.
            .uint8(name: "contest_appeal"),
            // 0x07: Alignment pad before the message ids.
            .padding(length: 1),

            // 0x08: Message-table ids. Two description ids: the short form
            // shown in the move list and the long form.
            .uint16(name: "name_message_id"),
            .uint16(name: "description_message_id"),
            .uint16(name: "description_message_id_2"),

            // 0x0E: Physical / special / status.
            .uint8(name: "category"),
            .uint8(name: "base_power"),
            .uint8(name: "type"),
            .uint8(name: "base_accuracy"),
            .uint8(name: "base_pp"),
            // 0x13: Probability the secondary effect fires.
            .uint8(name: "effect_accuracy"),
            .uint8(name: "priority"),

            // 0x15: Flag bits, most significant first:
            //   7 unknown, 6 unknown, 5 can add King's Rock flinch,
            //   4 copyable by Mirror Move, 3 stolen by Snatch,
            //   2 reflected by Magic Coat, 1 blocked by Protect,
            //   0 makes contact.
            .uint8(name: "flags"),

            // 0x16: Broad effect category — damaging, stat boost and so on.
            // Believed to be what the AI strategises on.
            .uint8(name: "effect_type"),
            // 0x17: Alignment filler (0xD0 on every row), not the unknown
            // field the legacy tool declared here.
            .padding(length: 1),
        ],
        description: "One move's battle data: power, accuracy, typing, targeting, flags and message ids."
    )

    /// One item (0x28 / 40 bytes). Several fields are only meaningful to
    /// the assembly that reads them; the legacy tool's names for those are
    /// kept so the two tools stay cross-referenceable.
    static let itemStruct = StructMap(
        name: "PBRItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00
            .uint16(name: "price"),
            .uint16(name: "name_message_id"),
            .uint16(name: "description_message_id"),
            .uint16(name: "unknown_1"),

            // 0x08: Item-type identifier referenced by the battle assembly.
            .uint8(name: "hold_item_id"),
            // 0x09: How strong the item's effect is.
            .int8(name: "parameter"),
            .array(name: "unknown_values", count: 2, of: .uint8),

            // 0x0C
            .uint8(name: "fling_base_power"),
            .uint8(name: "unknown_2"),
            .uint8(name: "unknown_3"),
            .uint8(name: "unknown_4"),

            // 0x10: Identifier used for the item in the overworld.
            .uint8(name: "field_id"),
            // 0x11: Identifier used for the item in battle.
            .uint8(name: "battle_id"),
            .uint8(name: "unknown_flag"),
            .padding(length: 1),

            // 0x14: Secondary parameter referenced by the assembly.
            .uint8(name: "sub_parameter"),
            .uint8(name: "unknown_5"),

            // 0x16: The legacy tool inferred C-style alignment padding here,
            // at +0x1A and at +0x1C. The disc disagrees — all three regions
            // carry values on real rows — so they are modelled as live fields.
            // (`PBRCommonTableRealCorpusTests` pins this: intra-entry filler
            // in `common.fsys` is 0xD0, and none of these are.)
            .array(name: "unknown_6", count: 2, of: .uint8),

            // 0x18
            .uint8(name: "unknown_7"),
            .uint8(name: "sub_id"),
            .uint8(name: "unknown_8"),

            // 0x1B: Five signed bytes, every one of them 0, +10 or −10 across
            // the whole table — the shape of a per-tier delta, like the
            // happiness triple below, but for something not yet identified.
            .array(name: "unknown_deltas", count: 5, of: .int8),

            // 0x20
            .uint8(name: "unknown_9"),
            // 0x21: HP restored. Real values are 10/20/50/60/80/100/200 plus
            // 253–255, which read as "full restore"-style sentinels.
            .uint8(name: "healing_parameter"),
            // 0x22: PP restored — 10, or 127 for "all".
            .uint8(name: "pp_parameter"),
            // 0x23: Happiness change from using the item, one signed value
            // per happiness tier. Real values are 0, ±1, ±5, ±10, −15.
            .array(name: "happiness_effects", count: 3, of: .int8),
            // 0x26: Zero on every row.
            .padding(length: 2),
        ],
        description: "One item: price, message ids, and the parameters the battle and field code read."
    )

    /// One TM/HM slot (0x04 / 4 bytes).
    static let tmStruct = StructMap(
        name: "PBRTM",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "move"),
            // 0x02: Weight for random move selection on generated NPC
            // Pokémon; 0 means never selected.
            .uint8(name: "random_selection_chance"),
            .padding(length: 1),
        ],
        description: "The move a TM or HM teaches, and its weight in random NPC moveset generation."
    )

    /// One row of the type matchup chart (0x12 / 18 bytes).
    ///
    /// The row index is the attacking type and each byte is the multiplier
    /// against the defending type at that position, in the games' internal
    /// type order. Modelled as an array rather than 18 named fields because
    /// PBR's type ids haven't been confirmed against the data here — the
    /// legacy tool generated names from its own type enum.
    static let typeMatchupStruct = StructMap(
        name: "PBRTypeMatchup",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "effectiveness_by_defending_type", count: 18, of: .uint8),
        ],
        description: "One attacking type's effectiveness against each of the 18 defending type slots."
    )

    /// One experience curve (0x194 / 404 bytes).
    static let experienceTableStruct = StructMap(
        name: "PBRExperienceTable",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Level 0 — present so the array below can be indexed by
            // level directly from 1.
            .uint32(name: "experience_for_level_0"),
            // 0x04: Cumulative experience needed for levels 1…100.
            .array(name: "experience_for_level", count: 100, of: .uint32),
        ],
        description: "Cumulative experience required at each level for one growth rate. Table row index is the growth rate."
    )
}
