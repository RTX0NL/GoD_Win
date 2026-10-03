import Structs
import GoDFoundation

/// Struct definitions for the data tables Colosseum keeps in `main.dol`.
///
/// Colosseum splits its tables between `common.rel` and the DOL differently
/// from XD: the species, move and trainer tables live in `common.rel` (see
/// `CommonRelStructs`), while items, types, abilities, TMs, status effects
/// and every model/animation reference table live here. Layouts were taken
/// from the legacy tool's per-region table definitions and then checked
/// against the retail US, PAL and JP discs — every table below tiles its
/// declared entry count exactly into the space between its own label and the
/// next one.
public extension ColosseumStructDefaults {

    /// 0x0C. Identical to XD's, down to the message ids: ability 1 is name
    /// 0xC1D / description 0xCE5 on both games and all six discs. The
    /// leading word is never written on disc.
    static let abilityStruct = StructMap(
        name: "Ability",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .padding(length: 4),
            .uint32(name: "name_id"),
            .uint32(name: "description_id"),
        ],
        description: "Ability name and description IDs (78 entries)"
    )

    /// 0x14, the same record XD uses — but Colosseum declares **86** of them
    /// where XD declares 87. Entry 86 on a Colosseum disc is already the
    /// pointer array that follows, on all three regions.
    static let statusEffectStruct = StructMap(
        name: "StatusEffect",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // Names from XD's accessors (joutaiDataBiosGet*); Colosseum's
            // record and getters are the same.
            .abstraction(name: "owner", typeName: "StatusEffectOwner", description: "GetStatusKind: the object the status lives on"),
            .uint8(name: "slot", description: "GetUseBanme"),
            .abstraction(name: "write_mode", typeName: "StatusWriteMode", description: "GetWriteMode"),
            .uint8(name: "max_count", description: "GetMaxCount: the stack limit for Stack"),
            .uint8(name: "turn_count_id", description: "GetKaisuuDataId: a row of the turn-count table, not a count"),
            .uint8(name: "unknown_flag_1"),
            .uint8(name: "unknown_flag_2"),
            .uint8(name: "unknown_flag_3"),
            .uint16(name: "status_id", description: "GetStatus: the selector passed to the owner's status routine"),
            .uint16(name: "same_status_id", description: "GetSameJoutai: a StatusEffects row treated as the same status (the weathers)"),
            .uint32(name: "padding", description: "Filled at runtime"),
            .uint32(name: "name_id"),
        ],
        description: "Status condition properties (86 entries)"
    )

    /// 0x08. 50 TMs then 8 HMs, the same shape as XD's.
    static let tmStruct = StructMap(
        name: "TM",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .boolean(name: "is_hm"),
            .padding(length: 5),
            .abstraction(name: "move_id", typeName: "Moves"),
        ],
        description: "TM/HM to move ID mapping (58 entries)"
    )

    /// 0x2C. XD's is 0x30: it carries a large *and* a small icon id where
    /// Colosseum carries one, so the matchup array starts at +0x08 here and
    /// +0x0C there.
    static let typeStruct = StructMap(
        name: "Type",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "category", typeName: "MoveCategory", description: "A type's damage class; Counter checks 1 and Mirror Coat 2"),
            .padding(length: 1),
            .uint16(name: "icon_id"),
            .uint32(name: "name_id"),
            .array(name: "effectiveness", count: 18, of: .enumeration(name: "TypeEffectiveness"),
                   description: "One entry per defending type, in type order; on disc 0x3F is neutral, 0x41 super effective, 0x42 not very effective, 0x43 no effect"),
        ],
        description: "Type matchup and properties (18 entries, 0x2C bytes)"
    )

    /// 0x28 — the same record XD keeps in `common.rel`, field for field, so
    /// the names come from XD's own accessors (`itemDataBiosGet*`). The one
    /// difference is where the two function pointers live: in a REL they are
    /// relocations, here they are addresses stored on disc, which the game
    /// overwrites at load. An item that carries one keeps it.
    static let itemStruct = StructMap(
        name: "Item",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "bag_slot", typeName: "ItemPocket"),
            .boolean(name: "cannot_be_held", description: "Key items"),
            .boolean(name: "useful_flag", description: "Set for 7 items on the US disc, as in XD"),
            .boolean(name: "can_be_deposited", description: "May go into the PC"),
            .uint8(name: "in_battle_use_id"),
            .padding(length: 1),
            .uint16(name: "price"),
            .uint16(name: "coupon_price"),
            .abstraction(name: "hold_effect", typeName: "HoldEffect", description: "Effect while held in battle"),
            .uint16(name: "battle_use_effect_id", description: "0 for every item on disc"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "description_id"),
            .uint32(name: "parameter", description: "Effect strength"),
            .label(name: "field_use_function", description: "Routine run when used from the bag; set at runtime, but a value on disc is kept"),
            .label(name: "battle_use_function", description: "Routine run when used in battle; set at runtime, but a value on disc is kept"),
            .int8(name: "friendship_effect_1", description: "Friendship change below 100"),
            .int8(name: "friendship_effect_2", description: "Friendship change from 100 to 199"),
            .int8(name: "friendship_effect_3", description: "Friendship change at 200 and above"),
            .padding(length: 1),
        ],
        description: "Item properties (397 entries, 0x28 bytes)"
    )

    /// One item id. Two tables of these follow the item table: a 1220-entry
    /// list and a 548-entry one, both dense runs of ids.
    static let validItemStruct = StructMap(
        name: "ValidItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "item_id", typeName: "Items"),
        ],
        description: "One item id in a valid-item list"
    )

    /// 0x0C — the crop rectangle and file id for one menu sprite in one
    /// language.
    static let textureInfoStruct = StructMap(
        name: "TextureInfo",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "crop_x"),
            .uint16(name: "crop_y"),
            .uint16(name: "crop_width"),
            .uint16(name: "crop_height"),
            .uint32(name: "file_id"),
        ],
        description: "Texture crop and file reference"
    )

    /// 0x18 — one language. The US and JP discs ship a single language, so a
    /// menu sprite carries one `TextureInfo`. Both strides come from the
    /// game's own accessor, which multiplies the row index by 0x18 on US and
    /// JP and by 0x48 on PAL.
    static let textureStruct = StructMap(
        name: "Texture",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown"),
            .uint32(name: "unknown_2"),
            .subStruct(name: "info", typeName: "TextureInfo"),
            .uint32(name: "unknown_3"),
        ],
        description: "Single-language texture metadata (US/JP, 0x18 bytes)"
    )

    /// 0x48 — the PAL disc's five languages. (XD is the other way round: its
    /// US build is the multi-language one and only JP is single.)
    static let textureEUStruct = StructMap(
        name: "TextureEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown"),
            .uint32(name: "unknown_2"),
            .subStruct(name: "english_info", typeName: "TextureInfo"),
            .subStruct(name: "german_info", typeName: "TextureInfo"),
            .subStruct(name: "french_info", typeName: "TextureInfo"),
            .subStruct(name: "italian_info", typeName: "TextureInfo"),
            .subStruct(name: "spanish_info", typeName: "TextureInfo"),
            .uint32(name: "unknown_3"),
        ],
        description: "Multi-language texture metadata (PAL, 0x48 bytes)"
    )

    /// 0x1C. A linked list rather than a flat table: `next_entry_index`
    /// points at the next sprite of the same screen.
    static let textureRenderingStruct = StructMap(
        name: "TextureRenderingInfo",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .bits(name: "flags", fields: [
                .flag(name: "unknown_0", bit: 0, description: "0x80; unidentified"),
                .flag(name: "terminates_chain", bit: 1, description: "0x40; last sprite of this screen"),
                .number(name: "unknown_2_7", bits: 2...7, description: "Read by nothing"),
            ]),
            .uint8(name: "alpha"),
            .int16(name: "x_position"),
            .int16(name: "y_position"),
            .int16(name: "width"),
            .int16(name: "height"),
            .int16(name: "texture_index", description: "Row of the texture table"),
            .array(name: "unknowns", count: 8, of: .uint8),
            .label(name: "draw_function", description: "Set at runtime"),
            .uint16(name: "next_entry_index", description: "Row of this table"),
            .padding(length: 2),
        ],
        description: "One drawn menu sprite (0x1C bytes)"
    )

    /// 0x0C. XD's is 0x08 — Colosseum's carries the model's name id too.
    static let pkxModelStruct = StructMap(
        name: "PKXModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
            .uint32(name: "name_id"),
        ],
        description: "PKX model reference (fsys ID, file identifier, name ID)"
    )

    /// 0x08 — the Unown table has no name id, so it is not a `PKXModel`.
    static let unownPKXModelStruct = StructMap(
        name: "UnownPKXModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
        ],
        description: "Unown PKX model reference (28 entries)"
    )

    /// 0x0C. The species id is followed by two bytes of padding so the two
    /// ids stay word-aligned, exactly as in XD.
    static let shinyPKXModelStruct = StructMap(
        name: "ShinyPKXModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "species_id", typeName: "PokemonSpecies"),
            .padding(length: 2),
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
        ],
        description: "Shiny PKX model reference with species ID (35 entries)"
    )

    /// 0x1C. XD stores three indices into its own animation table (6 bytes);
    /// Colosseum stores the three fsys references outright, plus a name id.
    static let wzxMoveAnimationStruct = StructMap(
        name: "WZXMoveAnimation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "name_id"),
            .uint32(name: "attack_fsys_id"),
            .uint32(name: "attack_file_identifier"),
            .uint32(name: "damage_fsys_id"),
            .uint32(name: "damage_file_identifier"),
            .uint32(name: "special_fsys_id"),
            .uint32(name: "special_file_identifier"),
        ],
        description: "Move animation references (356 entries, 0x1C bytes)"
    )
}
