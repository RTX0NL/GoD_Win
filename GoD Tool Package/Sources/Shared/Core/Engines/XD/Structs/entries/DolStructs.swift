import Structs
import GoDFoundation

/// Struct definitions for data tables found in the XD DOL (start.dol)
public extension XDStructDefaults {

    static let abilityStruct = StructMap(
        name: "Ability",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .uint32(name: "unused"),
            .uint32(name: "name_id"),
            .uint32(name: "description_id"),
        ],
        description: "Ability name and description IDs"
    )

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
        description: "Status condition properties (87 entries)"
    )

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

    static let menuDataStruct = StructMap(
        name: "MenuData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint8(name: "unknown_3"),
            .uint8(name: "display_max"),
            .uint8(name: "unknown_4"),
            .uint8(name: "unknown_5"),
            .uint8(name: "unknown_6"),
            .uint8(name: "unknown_7"),
            .uint16(name: "x_position"),
            .uint16(name: "y_position"),
            .label(name: "callback_1"),
            .label(name: "callback_2"),
            .label(name: "callback_3"),
            .label(name: "callback_4"),
        ],
        description: "Menu rendering configuration (288 entries)"
    )

    static let pkxModelStruct = StructMap(
        name: "PKXModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
        ],
        description: "PKX model reference (fsys ID + file identifier)"
    )

    static let shinyPKXModelStruct = StructMap(
        name: "ShinyPKXModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "species_id", typeName: "PokemonSpecies"),
            // The species id is followed by two zero bytes so the two ids
            // stay word-aligned — 35 entries of 12 bytes on every build.
            // Without this the rows after the first read two bytes late.
            .padding(length: 2),
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
        ],
        description: "Shiny PKX model reference with species ID (12 bytes per entry)"
    )

    static let wzxAnimationStruct = StructMap(
        name: "WZXAnimation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "fsys_id"),
            .uint32(name: "wzx_file_id"),
        ],
        description: "WZX animation reference"
    )

    static let wzxMoveAnimationStruct = StructMap(
        name: "WZXMoveAnimation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "attack_animation"),
            .uint16(name: "damage_animation"),
            .uint16(name: "special_animation"),
        ],
        description: "Move animation indices into WZX table"
    )

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

    static let textureStruct = StructMap(
        name: "Texture",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown"),
            .uint32(name: "unknown_2"),
            .subStruct(name: "us_uk_info", typeName: "TextureInfo"),
            .subStruct(name: "german_info", typeName: "TextureInfo"),
            .subStruct(name: "french_info", typeName: "TextureInfo"),
            .subStruct(name: "italian_info", typeName: "TextureInfo"),
            .subStruct(name: "spanish_info", typeName: "TextureInfo"),
            .uint32(name: "unknown_3"),
        ],
        description: "Multi-language texture metadata (US/EU, 0x48 bytes)"
    )

    /// The Japanese build ships one language, so a menu sprite carries one
    /// `TextureInfo` rather than five and the entry is 0x18 rather than 0x48.
    /// Both strides come from the game's own accessor: `menuSpriteBiosGetPtr`
    /// multiplies the row index by 0x48 on US and PAL and by 0x18 on JP.
    static let textureJPStruct = StructMap(
        name: "TextureJP",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown"),
            .uint32(name: "unknown_2"),
            .subStruct(name: "jp_info", typeName: "TextureInfo"),
            .uint32(name: "unknown_3"),
        ],
        description: "Single-language texture metadata (JP, 0x18 bytes)"
    )
}
