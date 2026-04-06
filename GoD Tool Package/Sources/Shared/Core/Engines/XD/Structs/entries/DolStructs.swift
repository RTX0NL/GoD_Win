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
            .uint8(name: "effect_type"),
            .uint8(name: "sub_index"),
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint8(name: "number_of_turns", description: "0 for infinite"),
            .uint8(name: "unknown_flag_1"),
            .uint8(name: "unknown_flag_2"),
            .uint8(name: "unknown_flag_3"),
            .uint16(name: "unknown_3"),
            .uint16(name: "base_weather_id", description: "Non-permanent weather status effect"),
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
            .uint8(name: "is_hm"),
            .padding(length: 5),
            .uint16(name: "move_id"),
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
            .uint16(name: "species_id"),
            .uint32(name: "fsys_id"),
            .uint32(name: "file_identifier"),
        ],
        description: "Shiny PKX model reference with species ID"
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
        description: "Multi-language texture metadata (US/EU, 0x58 bytes)"
    )
}
