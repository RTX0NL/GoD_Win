import Foundation
import Structs

/// Entry structs for the `common.fsys` tables the legacy tool never typed.
///
/// Layouts here come from three sources, cross-checked against each other:
///
///  1. **The game's own field accessors.** PBR reaches every common table
///     through a 33-slot pointer array at `0x8063CE34` (PAL). Each table has a
///     generated row-getter of the form
///     `row = table->entries; row += index * <stride>` — the stride is a
///     compile-time constant, which is what identifies the table — and a set
///     of one-line field getters that each `bl` the row-getter and then load
///     one field at a fixed offset and width. Mining those gives exact
///     offsets and widths; resolving each getter's call sites back to a
///     pointer-array slot gives the table. All 26 tables resolved this way
///     have a stride matching the disc's header word, which is what makes the
///     association trustworthy.
///  2. **Column analysis of the real PAL rows** — value ranges, float
///     plausibility, and the FSYS file-id encoding `(entryID << 16) | type`.
///  3. **The packer's `0xD0` alignment filler.** Every intra-entry alignment
///     gap in `common.fsys` is filled with `0xD0` rather than zero (14 of the
///     33 tables contain such runs). That distinguishes a genuine
///     unknown-but-used field from a hole, and is why several fields the
///     legacy tool called "Unknown" are modelled as padding here.
///
/// Where the evidence stops, so does the typing: fields no accessor reads and
/// whose meaning the data doesn't reveal stay as named byte arrays.
public extension PBRStructDefaults {

    // MARK: - Countries (table 1)

    /// One country entry (0x76 / 118 bytes).
    ///
    /// The sub-region array is the giveaway: only 18 of the 234 countries
    /// populate it, and each populated row's `subregion_count` equals the
    /// number of non-zero message ids in it (25 for one country, 8 for
    /// another, …). The name ids are contiguous across the table
    /// (5705…5938), one per country.
    static let countryStruct = StructMap(
        name: "PBRCountry",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: Message id of the country's name.
            .uint16(name: "name_message_id"),

            // 0x02: Message ids for the country's states / provinces /
            // prefectures, packed from the front and zero-filled. Zero
            // throughout for countries with no sub-regions.
            .array(name: "subregion_name_message_ids", count: 52, of: .uint16),

            // 0x6A: Five 2-byte values, one per PAL language slot. Both
            // bytes are small (0…54, with 0xFF as a "none" marker on the
            // blank first row); their exact meaning isn't established.
            .array(name: "per_language_values", count: 10, of: .uint8),

            // 0x74: Number of populated entries in the sub-region array.
            .uint8(name: "subregion_count"),

            // 0x75: Alignment filler (0xD0).
            .padding(length: 1),
        ],
        description: "One country: its name, its states/provinces, and per-language values. Sub-region list is populated for only 18 of 234 countries."
    )

    // MARK: - Colosseum quote table (table 3)

    /// One group of alternative lines (0x20 / 32 bytes).
    static let colosseumQuoteSetStruct = StructMap(
        name: "PBRColosseumQuoteSet",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // Message ids packed from the front, zero-filled. Real rows use
            // between 1 and 6 of the 16 slots.
            .array(name: "message_ids", count: 16, of: .uint16),
        ],
        description: "Up to 16 alternative message ids for one situation; packed from the front and zero-filled."
    )

    /// One entry of the table the legacy tool called "colosseums unknown"
    /// (0xBA / 186 bytes). Present on US and PAL discs only.
    ///
    /// Each row carries five independent groups of message ids, keyed by a
    /// group index — the shape of a dialogue set (several situations, each
    /// with a few interchangeable lines). The leading index is contiguous
    /// across the table (182…287).
    static let colosseumsUnknownStruct = StructMap(
        name: "PBRColosseumsUnknown",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Contiguous entry index.
            .uint16(name: "index"),
            // 0x02: A message id (0x4707…0x4D54 across the table).
            .uint16(name: "message_id"),
            // 0x04: Zero on every row.
            .padding(length: 4),

            // 0x08: Five groups of alternative lines.
            .array(name: "quote_sets", count: 5, of: .subStruct(name: "PBRColosseumQuoteSet")),

            // 0xA8: Zero on every row.
            .padding(length: 16),

            // 0xB8: Group index (17…54) — several rows share one value.
            .uint8(name: "group_index"),
            // 0xB9: 0x81 on all but four rows, which use 0x82.
            .uint8(name: "flags"),
        ],
        description: "Five groups of alternative message ids keyed by a group index — dialogue sets. Legacy tool left this table untyped."
    )

    // MARK: - Model bindings (tables 7, 10, 26, 31)

    /// Per-model effect parameters (0x14 / 20 bytes). Only two rows exist on
    /// the disc and no field accessor reads it, so the layout is unresolved;
    /// only the trailing alignment filler is known.
    static let pokemonModelEffectStruct = StructMap(
        name: "PBRPokemonModelEffect",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "raw_data", count: 0x13, of: .uint8),
            // 0x13: Alignment filler (0xD0).
            .padding(length: 1),
        ],
        description: "Per-model effect parameters. Only 2 rows on the disc and no field accessors — layout not established."
    )

    /// One Poké Ball's model binding (0x20 / 32 bytes).
    ///
    /// Six FSYS file ids in the `(entryID << 16) | type` encoding: the first
    /// is a model (type 0x0400), the other five share type 0x0A00. 17 rows —
    /// one per ball type.
    static let ballModelStruct = StructMap(
        name: "PBRBallModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Ball model, file type 0x0400 (`.sdr`).
            .uint32(name: "model_file_id"),
            // 0x04: Five further files, all type 0x0A00 — throw/open/capture
            // effect resources.
            .array(name: "effect_file_ids", count: 5, of: .uint32),
            // 0x18: Two small ids (0…1556), most likely message ids.
            .uint32(name: "name_message_id"),
            .uint32(name: "description_message_id"),
        ],
        description: "The model and effect resources for one Poké Ball type."
    )

    /// One trainer archetype's model set (0x2C / 44 bytes).
    ///
    /// Named in the table's own name pool by archetype — `NormalBoy`,
    /// `CoolGirl`, `DPBoy`, `Boss3` — and the first row is the `null` entry,
    /// which is entirely zero.
    static let trainerEventStruct = StructMap(
        name: "PBRTrainerEvent",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Eight model file ids, all file type 0x0400.
            .array(name: "model_file_ids", count: 7, of: .uint32),
            // 0x1C: Two scalars — 1.0, 1.5, 2.0, 2.33 and similar.
            .float(name: "scale_1"),
            .float(name: "scale_2"),
            // 0x24: One further model file id, same encoding.
            .uint32(name: "extra_model_file_id"),
            // 0x28: Small index (0…1).
            .uint8(name: "kind"),
            // 0x29: Alignment filler (0xD0).
            .padding(length: 3),
        ],
        description: "Model set and scale factors for one trainer archetype. Rows are named by archetype in the table's name pool."
    )

    /// One tutorial step (0x1C / 28 bytes).
    static let tutorialDataStruct = StructMap(
        name: "PBRTutorialData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Six FSYS file ids. The pair at +0x00/+0x0C use file type
            // 0x0800; the four at +0x04/+0x08/+0x10/+0x14 use 0x0C00.
            .uint32(name: "file_id_1"),
            .uint32(name: "file_id_2"),
            .uint32(name: "file_id_3"),
            .uint32(name: "file_id_4"),
            .uint32(name: "file_id_5"),
            .uint32(name: "file_id_6"),
            // 0x18: Step category, 1…6.
            .uint8(name: "category"),
            // 0x19: Alignment filler (0xD0).
            .padding(length: 3),
        ],
        description: "Resources for one tutorial step, plus its category."
    )

    // MARK: - Battle AI (tables 12, 13, 14, 15, 16)

    /// One battle-pass AI profile (0x0C / 12 bytes).
    static let fightAIBattlePassStruct = StructMap(
        name: "PBRFightAIBattlePass",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Two scalars, 0…12 and 0…6.
            .float(name: "weight_1"),
            .float(name: "weight_2"),
            // 0x08: Four small values; the last is 0…2.
            .array(name: "unknown_values", count: 4, of: .uint8),
        ],
        description: "AI tuning profile attached to a battle pass. Field meanings not established."
    )

    /// Per-species AI expectation data (0x2C / 44 bytes). Rows are named by
    /// species in the table's own name pool (`NOKOTTI`, `BAKUHUUN`, …), and
    /// there is one per species. Only the byte at +0x2A has a field accessor.
    static let fightAIExpectDataStruct = StructMap(
        name: "PBRFightAIExpectData",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "raw_data", count: 0x2A, of: .uint8),
            // 0x2A: The one field the game reads through a generated accessor.
            .uint8(name: "value"),
            // 0x2B: Alignment filler (0xD0).
            .padding(length: 1),
        ],
        description: "Per-species AI expectation data, named by species in the table's name pool. Only the +0x2A field is resolved."
    )

    /// AI per-Pokémon part data (0x0E / 14 bytes). Every byte is in 0…100,
    /// which reads as a set of percentage weights, but no field accessor
    /// reads this table so the split into fields isn't established.
    static let fightAIPokemonPartDataStruct = StructMap(
        name: "PBRFightAIPokemonPartData",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "weights", count: 14, of: .uint8),
        ],
        description: "Fourteen values in 0…100 — percentage weights. Field split not established."
    )

    /// One AI tuning value (0x04 / 4 bytes). The whole row is a single signed
    /// word: the game's accessor loads it as one `lwz`, and the 1253 rows hold
    /// only 33 distinct values, including negatives.
    static let fightAIValueStruct = StructMap(
        name: "PBRFightAIValue",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int32(name: "value"),
        ],
        description: "One signed AI tuning value. The table is a flat array of 1253 of them."
    )

    /// Per-move AI data (0x06 / 6 bytes). One row per move — the row count
    /// matches the move table exactly.
    static let fightAIMoveDataStruct = StructMap(
        name: "PBRFightAIMoveData",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: AI category for the move, 0…196.
            .uint16(name: "category"),
            // 0x02: Two small enums, 0…13.
            .uint8(name: "value_1"),
            .uint8(name: "value_2"),
            .uint8(name: "value_3"),
            // 0x05: Boolean.
            .uint8(name: "flag"),
        ],
        description: "AI classification for one move; indexed in parallel with the move table."
    )

    // MARK: - Flags (table 17)

    /// One save-flag descriptor (0x0C / 12 bytes).
    ///
    /// PBR keeps the same two-layer flag design as Colosseum and XD — raw bit
    /// banks in the save, described by a table in the executable — except the
    /// descriptor table ships as a `common.fsys` member rather than being
    /// embedded in the DOL or a REL. `bit_width` takes exactly the values a
    /// bitfield width would (1…6, 8, 16, 24, 32), which is what identifies it.
    static let flagIDStruct = StructMap(
        name: "PBRFlagID",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Flag kind, 0…5.
            .uint32(name: "kind"),
            // 0x04: Zero on every row.
            .padding(length: 4),
            // 0x08: Width of the flag's field in bits.
            .uint8(name: "bit_width"),
            // 0x09: Boolean.
            .uint8(name: "flag"),
            // 0x0A: Alignment filler (0xD0).
            .padding(length: 2),
        ],
        description: "Descriptor for one save flag: its kind and how many bits it occupies in the save's bit bank."
    )

    // MARK: - Venue and menu tables (18, 20, 25)

    /// Per-battlefield configuration (0x20 / 32 bytes). Rows are named after
    /// the battlefield archives (`bf_00`…`bf_10`) in the table's name pool.
    static let floorEventStruct = StructMap(
        name: "PBRFloorEvent",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Six ids. The first two are small and contiguous across
            // the table; the rest look like message or event ids.
            .array(name: "event_ids", count: 6, of: .uint32),
            // 0x18: 0.3 … 0.6 on every row.
            .float(name: "rate"),
            // 0x1C: Two small values; the second is 40 or 50.
            .uint8(name: "value_1"),
            .uint8(name: "value_2"),
            // 0x1E: Alignment filler (0xD0).
            .padding(length: 2),
        ],
        description: "Per-battlefield event configuration. Rows are named by battlefield archive in the table's name pool."
    )

    /// One selectable battle rule preset (0x0E / 14 bytes).
    ///
    /// Eight presets. Seven of the eight are level 100 / 600 seconds; the odd
    /// one is level 5 / 30 seconds. `format` and `flags` are what distinguish
    /// the rest from each other.
    static let menuBattleRuleStruct = StructMap(
        name: "PBRMenuBattleRule",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: 1 on every row.
            .uint16(name: "enabled"),
            // 0x02: Level cap — 100, or 5 on the short preset.
            .uint16(name: "level_cap"),
            // 0x04: Time limit in seconds — 600, or 30 on the short preset.
            .uint16(name: "time_limit"),
            // 0x06: Format id — 0, 4 or 7.
            .uint16(name: "format"),
            // 0x08: Zero on every row.
            .padding(length: 4),
            // 0x0C: Bit flags — 0xF000/0xF080/0xF100/0xF180 on six presets,
            // 0x3200 and 0x0D00 on the other two.
            .uint16(name: "flags"),
        ],
        description: "One battle rule preset as offered in the menus: level cap, time limit, format and flags."
    )

    /// One trainer part category (0x06 / 6 bytes).
    ///
    /// A half-open range into `TrainerCustomParts`: `first_part_index` and
    /// `last_part_index` are both bounded by that table's 744 rows, and the
    /// upper bound reaches exactly its last index.
    static let trainerCustomTableEntryStruct = StructMap(
        name: "PBRTrainerCustomTableEntry",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: First row of `TrainerCustomParts` in this category.
            .uint16(name: "first_part_index"),
            // 0x02: Last row of `TrainerCustomParts` in this category.
            .uint16(name: "last_part_index"),
            // 0x04: Zero on every row, but the game reads it.
            .uint16(name: "value"),
        ],
        description: "A range of rows in TrainerCustomParts forming one category of interchangeable parts."
    )
}
