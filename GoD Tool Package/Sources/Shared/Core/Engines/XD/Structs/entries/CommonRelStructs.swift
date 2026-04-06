import Structs
import GoDFoundation

/// Struct definitions for data tables in common.rel
public extension XDStructDefaults {

    static let moveStruct = StructMap(
        name: "Move",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int8(name: "priority"),
            .uint8(name: "base_pp"),
            .uint8(name: "type"),
            .uint8(name: "targets"),
            .uint8(name: "base_accuracy"),
            .uint8(name: "effect_accuracy"),
            .uint8(name: "makes_contact"),
            .uint8(name: "can_be_protected"),
            .uint8(name: "can_be_reflected"),
            .uint8(name: "can_be_stolen"),
            .uint8(name: "can_be_copied_mirror_move"),
            .uint8(name: "gains_flinch_kings_rock"),
            .uint8(name: "callable_by_metronome"),
            .uint8(name: "copyable_by_mimic"),
            .uint8(name: "callable_by_assist"),
            .uint8(name: "callable_by_sleep_talk"),
            .uint8(name: "is_sound_based"),
            .uint8(name: "has_unspecified_target"),
            .uint8(name: "is_hm_move"),
            .uint8(name: "category"),
            .uint8(name: "has_risk_flag"),
            .uint8(name: "match_up_chart_type"),
            .uint8(name: "contest_appeal_jam_index"),
            .uint8(name: "contest_appeal_type"),
            .uint16(name: "base_power"),
            .padding(length: 2),
            .uint16(name: "effect"),
            .uint16(name: "animation_id"),
            .uint32(name: "name_id"),
            .uint32(name: "unused_string_id"),
            .uint32(name: "exclamation_string_id"),
            .uint32(name: "description_id"),
            .uint32(name: "animation_id_2"),
            .uint8(name: "move_effect_type"),
        ],
        description: "Move properties (XD, 0x39 bytes per entry)"
    )

    static let itemStruct = StructMap(
        name: "Item",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "bag_slot"),
            .uint8(name: "cannot_be_held"),
            .padding(length: 2),
            .uint8(name: "in_battle_use_id"),
            .padding(length: 1),
            .uint16(name: "price"),
            .uint16(name: "coupon_price"),
            .padding(length: 1),
            .uint8(name: "battle_hold_item_id"),
            .padding(length: 4),
            .uint32(name: "name_id"),
            .uint32(name: "description_id"),
            .padding(length: 3),
            .uint8(name: "parameter"),
            .label(name: "function_pointer_1"),
            .label(name: "function_pointer_2"),
            .uint8(name: "friendship_effect_1"),
            .uint8(name: "friendship_effect_2"),
            .uint8(name: "friendship_effect_3"),
            .padding(length: 1),
        ],
        description: "Item properties (0x28 bytes per entry)"
    )

    static let natureStruct = StructMap(
        name: "Nature",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "battle_purify_multiplier"),
            .uint8(name: "walking_purify_multiplier"),
            .uint8(name: "call_purify_multiplier"),
            .uint8(name: "daycare_purify_multiplier"),
            .uint8(name: "cologne_purify_multiplier"),
            .uint8(name: "stat_multiplier_atk"),
            .uint8(name: "stat_multiplier_def"),
            .uint8(name: "stat_multiplier_spa"),
            .uint8(name: "stat_multiplier_spd"),
            .uint8(name: "stat_multiplier_spe"),
            .padding(length: 9),
            .uint32(name: "name_id"),
            .padding(length: 12),
        ],
        description: "Nature stat multipliers and purification data (0x20 bytes)"
    )

    static let typeStruct = StructMap(
        name: "Type",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "category"),
            .padding(length: 1),
            .uint16(name: "icon_big_id"),
            .uint16(name: "icon_small_id"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .padding(length: 1),
            .array(name: "effectiveness", count: 18, of: .uint16),
        ],
        description: "Type matchup and properties (0x30 bytes)"
    )

    static let trainerClassStruct = StructMap(
        name: "TrainerClass",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "payout_multiplier"),
            .uint32(name: "name_id"),
            .uint32(name: "unknown"),
        ],
        description: "Trainer class name and payout (0x0A bytes)"
    )

    static let multiplierStruct = StructMap(
        name: "Multiplier",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "numerator"),
            .uint8(name: "denominator"),
        ],
        description: "Fraction multiplier (2 bytes)"
    )

    static let treasureStruct = StructMap(
        name: "Treasure",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "room_id"),
            .uint16(name: "flag_id"),
            .uint16(name: "item_id"),
            .uint16(name: "quantity"),
            .uint32(name: "model_id"),
            .uint32(name: "unknown_1"),
            .int32(name: "x_position"),
            .int32(name: "y_position"),
            .int32(name: "z_position"),
            .int16(name: "angle"),
            .padding(length: 10),
        ],
        description: "Treasure box location and contents (0x28 bytes)"
    )

    static let doorStruct = StructMap(
        name: "Door",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "room_id"),
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint32(name: "unknown_3"),
            .uint32(name: "unknown_4"),
            .int32(name: "x_position"),
            .int32(name: "y_position"),
            .int32(name: "z_position"),
            .uint32(name: "unknown_5"),
        ],
        description: "Door collision/animation data (0x20 bytes)"
    )

    static let interactionPointStruct = StructMap(
        name: "InteractionPoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "room_id"),
            .uint8(name: "interaction_type"),
            .uint8(name: "unknown_1"),
            .int32(name: "x_position"),
            .int32(name: "y_position"),
            .int32(name: "z_position"),
            .uint32(name: "parameter_1"),
            .uint32(name: "parameter_2"),
        ],
        description: "Warp and object interaction point (0x18 bytes)"
    )

    static let battleFieldStruct = StructMap(
        name: "BattleField",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "name_id"),
            .uint32(name: "unknown_1"),
            .uint32(name: "unknown_2"),
            .uint32(name: "unknown_3"),
            .uint32(name: "unknown_4"),
            .uint32(name: "unknown_5"),
        ],
        description: "Battlefield properties (0x18 bytes)"
    )

    static let battleLayoutStruct = StructMap(
        name: "BattleLayout",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "trainers_per_side"),
            .uint8(name: "pokemon_per_trainer"),
            .uint8(name: "active_pokemon_per_trainer"),
            .uint8(name: "unknown_1"),
            .uint32(name: "unknown_2"),
        ],
        description: "Battle participant layout (0x08 bytes)"
    )

    static let pokefaceStruct = StructMap(
        name: "Pokeface",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "crop_type"),
            .uint32(name: "image_file_id"),
        ],
        description: "Pokemon portrait image reference (0x05 bytes)"
    )

    static let aiWeightEffectStruct = StructMap(
        name: "AIWeightEffect",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int32(name: "effect"),
            .uint32(name: "task_name_id"),
            .uint32(name: "sub_task_name_id"),
            .uint32(name: "reason_name_id"),
            .uint32(name: "unknown"),
        ],
        description: "AI move weight effect (0x14 bytes)"
    )

    static let pokemonAIRoleStruct = StructMap(
        name: "PokemonAIRole",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "physical_attacker_weight"),
            .uint8(name: "special_attacker_weight"),
            .uint8(name: "physical_defender_weight"),
            .uint8(name: "special_defender_weight"),
            .uint8(name: "speed_weight"),
            .uint8(name: "hp_weight"),
            .uint8(name: "status_weight"),
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint8(name: "unknown_3"),
            .uint8(name: "unknown_4"),
            .uint8(name: "unknown_5"),
            .uint8(name: "unknown_6"),
        ],
        description: "Pokemon AI role weights (0x0D bytes)"
    )

    static let tutorMoveStruct = StructMap(
        name: "TutorMove",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "move_id"),
            .padding(length: 5),
            .uint8(name: "availability_flag"),
            .uint32(name: "already_taught_flag"),
        ],
        description: "Tutor move availability (0x0C bytes)"
    )

    static let validItemStruct = StructMap(
        name: "ValidItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "item_id"),
        ],
        description: "Valid item ID (2 bytes)"
    )

    static let soundFileStruct = StructMap(
        name: "SoundFile",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "fsys_id"),
            .uint32(name: "isd_file_id"),
            .uint32(name: "ish_file_id"),
        ],
        description: "Sound file reference (0x0C bytes)"
    )

    static let soundMetadataStruct = StructMap(
        name: "SoundMetadata",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown"),
            .uint16(name: "sound_sub_index"),
            .uint16(name: "sound_file_index"),
            .int32(name: "unknown_2"),
        ],
        description: "Sound metadata (0x0C bytes, actually 0x10 in legacy)"
    )

    static let peopleIDStruct = StructMap(
        name: "PeopleID",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "person_id"),
            .uint32(name: "name_id"),
        ],
        description: "Character ID to name mapping (6 bytes)"
    )

    static let battleTypeStruct = StructMap(
        name: "BattleType",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown_1"),
            .uint32(name: "unknown_2"),
            .uint32(name: "unknown_3"),
            .uint32(name: "unknown_4"),
            .uint32(name: "unknown_5"),
            .uint32(name: "unknown_6"),
            .uint32(name: "unknown_7"),
            .uint32(name: "unknown_8"),
        ],
        description: "Battle type rules (0x20 bytes)"
    )

    static let rgbaColourStruct = StructMap(
        name: "RGBAColour",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "red"),
            .uint8(name: "green"),
            .uint8(name: "blue"),
            .uint8(name: "alpha"),
        ],
        description: "RGBA colour value (4 bytes)"
    )

    static let pokemonMenuAnimationStruct = StructMap(
        name: "PokemonMenuAnimation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "animation_id"),
            .uint16(name: "species_id"),
        ],
        description: "Pokemon summary screen animation override (3 bytes)"
    )
}
