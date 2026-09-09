import Structs
import GoDFoundation

/// Struct definitions for the data tables in Colosseum's `common.rel`.
///
/// Every stride below is the table's chunk length divided by the REL's own
/// count word, and it agrees on the US, PAL and JP discs. Field offsets come
/// from byte scans of all three discs (which bytes are always zero, which
/// carry relocations, how the value sets group into 16- and 32-bit fields)
/// checked against the legacy tool's Colosseum layouts and, where a
/// Colosseum routine could be identified by its stride, its loads. The
/// Colosseum disassembly's function names are positional matches from XD's
/// map, so a name is only cited where the body was read.
///
/// Three tables change stride on the PAL disc — `Rooms`, `Battles` and
/// `BattleFields` gain per-language copies of one field — so those get a
/// separate `…EU` definition that the PAL type map names.
public extension ColosseumStructDefaults {

    // MARK: - Small lookup tables

    static let legendaryPokemonStruct = StructMap(
        name: "LegendaryPokemon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "species", typeName: "PokemonSpecies"),
        ],
        description: "Species the game treats as legendary (2 bytes per entry; 0 ends the list)"
    )

    static let pokefaceStruct = StructMap(
        name: "Pokeface",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "crop_type", description: "0x40 crops the regular portrait, 0xC0 the shiny one"),
            .padding(length: 3),
            .uint32(name: "image_file_id", description: "File identifier in poke_face.fsys"),
        ],
        description: "Pokemon portrait image reference (8 bytes per entry)"
    )

    static let peopleIDStruct = StructMap(
        name: "PeopleID",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "person_id"),
            .padding(length: 2),
            .uint32(name: "name_id"),
        ],
        description: "Character ID to name mapping (8 bytes per entry)"
    )

    static let trainerClassStruct = StructMap(
        name: "TrainerClass",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "payout_multiplier"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "unknown", description: "Usually 5, occasionally 8"),
        ],
        description: "Trainer class name and payout (12 bytes per entry)"
    )

    static let keyboardCharacterStruct = StructMap(
        name: "KeyboardCharacter",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "character", description: "GS character code"),
        ],
        description: "One key of a naming-screen keyboard (2 bytes per entry)"
    )

    static let battleStyleStruct = StructMap(
        name: "BattleStyle",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "trainers_per_side"),
            .uint8(name: "pokemon_per_trainer"),
            .uint8(name: "active_pokemon_per_trainer"),
            .padding(length: 1),
            .uint32(name: "name_id"),
        ],
        description: "Battle participant layout (8 bytes per entry)"
    )

    static let multiplierStruct = StructMap(
        name: "Multiplier",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "numerator"),
            .uint8(name: "denominator"),
        ],
        description: "Fraction multiplier (2 bytes per entry)"
    )

    static let metLocationStruct = StructMap(
        name: "MetLocation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint16(name: "unknown_3"),
            .uint32(name: "name_id"),
        ],
        description: "Met-location string for a Pokemon's summary (8 bytes per entry)"
    )

    static let soundFileStruct = StructMap(
        name: "SoundFile",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "file_id", description: "File identifier in bgm_archive.fsys"),
            .label(name: "data_pointer", description: "Relocated to the sound's descriptor elsewhere in the module"),
        ],
        description: "Sound file reference (8 bytes per entry)"
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
        description: "AI move weight effect (0x14 bytes per entry)"
    )

    static let pokemonAIRoleStruct = StructMap(
        name: "PokemonAIRole",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "name_id"),
            .uint32(name: "unknown_1"),
            .uint8(name: "no_effect_weight"),
            .uint8(name: "attack_weight"),
            .uint8(name: "healing_weight"),
            .uint8(name: "stat_decrease_weight"),
            .uint8(name: "stat_increase_weight"),
            .uint8(name: "status_weight"),
            .uint8(name: "field_weight"),
            .uint8(name: "affect_opponent_move_weight"),
            .uint8(name: "ohko_weight"),
            .uint8(name: "multi_turn_weight"),
            .uint8(name: "misc_weight"),
            .uint8(name: "misc_2_weight"),
        ],
        description: "How much more or less likely an AI role is to pick each kind of move (0x14 bytes per entry)"
    )

    static let treasureStruct = StructMap(
        name: "Treasure",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "model_id"),
            .uint8(name: "quantity"),
            .int16(name: "angle"),
            .uint16(name: "room_id"),
            .uint16(name: "flag_id", description: "Set once the item has been collected"),
            .uint16(name: "unknown_1"),
            .padding(length: 2),
            .uint32(name: "item_id"),
            .float(name: "x_position"),
            .float(name: "y_position"),
            .float(name: "z_position"),
        ],
        description: "Treasure box location and contents (0x1C bytes per entry)"
    )

    static let doorStruct = StructMap(
        name: "Door",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .array(name: "unknown_values", count: 8, of: .int8),
            .uint8(name: "unknown_2"),
            .padding(length: 1),
            .uint16(name: "door_index"),
            .uint16(name: "room_id"),
            .uint16(name: "unknown_3"),
            .uint16(name: "unknown_4"),
            .padding(length: 2),
            .uint32(name: "model_id", description: "File identifier of the .rdat model; the low byte is the door animation index in it"),
        ],
        description: "Door collision and animation data (0x18 bytes per entry)"
    )

    static let interactionPointStruct = StructMap(
        name: "InteractionPoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "interaction_method"),
            .padding(length: 1),
            .uint16(name: "room_id"),
            .uint32(name: "collision_region_index", description: "Region in the room's .ccd collision file"),
            .uint16(name: "script_marker", description: "Whether the function is in the room's script or the common script"),
            .uint16(name: "script_function_index"),
            .array(name: "parameters", count: 4, of: .uint32),
        ],
        description: "Warp and object interaction point (0x1C bytes per entry)"
    )

    // MARK: - Battles

    static let battleTypeStruct = StructMap(
        name: "BattleType",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .boolean(name: "revert_changes_after_battle", description: "Teams and items go back to how they were before the battle"),
            .boolean(name: "enable_gym_badge_boosts"),
            .boolean(name: "count_pokemon_as_seen"),
            .boolean(name: "count_pokemon_as_caught"),
            .boolean(name: "enable_trainer_items"),
            .boolean(name: "can_call_pokemon"),
            .boolean(name: "can_run"),
            .boolean(name: "can_draw"),
            .boolean(name: "pokemon_gain_exp"),
            .boolean(name: "awards_prize_money"),
            .boolean(name: "add_prize_money_to_pool", description: "Banks the prize money in a flag to award at the end of a colosseum challenge"),
            .boolean(name: "pay_day_flag"),
            .boolean(name: "enable_friendship_gain"),
            .boolean(name: "can_trigger_pokerus"),
            .boolean(name: "enable_critical_hits"),
            .boolean(name: "enable_rui_ai_flag"),
            .boolean(name: "enable_rui_shadow_pokemon_reveal"),
            .boolean(name: "enable_soul_dew_effect"),
            .boolean(name: "boost_exp_gain", description: "Exp gain is raised by 50%"),
            .boolean(name: "is_boss_battle"),
            .boolean(name: "can_steal_items"),
            .boolean(name: "enable_pickup"),
            .boolean(name: "enable_hyper_mode"),
            .boolean(name: "enable_full_hud_layout"),
            .boolean(name: "display_opponent_dialog"),
            .boolean(name: "enable_battle_rules", description: "Whether rules like sleep clause and battle timers are checked"),
            .padding(length: 2),
            .uint32(name: "name_id"),
        ],
        description: "Battle rules (0x20 bytes per entry)"
    )

    private static var battleFieldHeadProperties: [StructMap.Property] {
        [
            .uint8(name: "unknown_1"),
            .padding(length: 1),
            .uint16(name: "unknown_2"),
            .uint32(name: "name_id"),
        ]
    }

    private static var battleFieldTailProperties: [StructMap.Property] {
        [
            .uint32(name: "unknown_4"),
            .uint32(name: "unknown_5"),
            .uint16(name: "unknown_6"),
            .uint16(name: "unknown_7"),
        ]
    }

    static let battleFieldStruct = StructMap(
        name: "BattleField",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleFieldHeadProperties + [
            .uint32(name: "unknown_string_id", description: "A message id: the PAL disc carries one per language"),
        ] + battleFieldTailProperties,
        description: "Battlefield properties, US and JP layout (0x18 bytes per entry)"
    )

    static let battleFieldEUStruct = StructMap(
        name: "BattleFieldEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleFieldHeadProperties + battleFieldTailProperties + [
            .uint32(name: "unknown_string_id_us_uk"),
            .uint32(name: "unknown_string_id_german"),
            .uint32(name: "unknown_string_id_french"),
            .uint32(name: "unknown_string_id_italian"),
            .uint32(name: "unknown_string_id_spanish"),
        ],
        description: "Battlefield properties, PAL layout: the message id moves to the end, one per language (0x28 bytes per entry)"
    )

    static let battlePlayerStruct = StructMap(
        name: "BattlePlayer",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "trainer_id", description: "Index into the Trainers table; 1 is the player"),
            .padding(length: 2),
            .abstraction(name: "controller", typeName: "BattleController"),
        ],
        description: "One of a battle's four participant slots (8 bytes)"
    )

    private static var battleHeadProperties: [StructMap.Property] {
        [
            .abstraction(name: "battle_kind", typeName: "BattleKind"),
            .abstraction(name: "battle_style", typeName: "BattleStyle"),
            .boolean(name: "unknown_flag"),
            .padding(length: 1),
            .uint16(name: "battle_field_index", description: "Index into the BattleFields table"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "bgm_id"),
            .uint32(name: "unknown_1"),
            .uint32(name: "colosseum_round_id", description: "Round announcement id, 0 outside colosseum challenges"),
        ]
    }

    static let battleStruct = StructMap(
        name: "Battle",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleHeadProperties + [
            .array(name: "players", count: 4, of: .subStruct(name: "BattlePlayer")),
        ],
        description: "Battle setup, US and JP layout (0x38 bytes per entry)"
    )

    static let battleEUStruct = StructMap(
        name: "BattleEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleHeadProperties + [
            .uint32(name: "colosseum_round_id_german"),
            .uint32(name: "colosseum_round_id_french"),
            .uint32(name: "colosseum_round_id_italian"),
            .uint32(name: "colosseum_round_id_spanish"),
            .array(name: "players", count: 4, of: .subStruct(name: "BattlePlayer")),
        ],
        description: "Battle setup, PAL layout: four more round ids, one per extra language (0x48 bytes per entry)"
    )

    // MARK: - Trainers

    static let trainerStruct = StructMap(
        name: "Trainer",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "gender", typeName: "Gender"),
            .padding(length: 1),
            .uint16(name: "trainer_class", description: "Index into the TrainerClasses table"),
            .uint16(name: "first_pokemon_index", description: "Index of the trainer's first Pokemon in the TrainerPokemonData table"),
            .uint16(name: "ai_index", description: "Index into the TrainerAIData table"),
            .uint32(name: "name_id"),
            .uint32(name: "battle_transition", description: "Effect used for the transition into the battle"),
            .uint32(name: "model_id"),
            .array(name: "items", count: 8, of: .enumeration(name: "Items"), description: "Items the trainer can use in battle"),
            .uint32(name: "pre_battle_text_id"),
            .uint32(name: "victory_text_id"),
            .uint32(name: "loss_text_id"),
            .uint32(name: "unknown_text_id", description: "A fourth message id; set for two trainers, the one after their loss text"),
        ],
        description: "Trainer (0x34 bytes per entry; 820 on every disc)"
    )

    static let pokemonIVsStruct = StructMap(
        name: "PokemonIVs",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "hp"),
            .uint8(name: "attack"),
            .uint8(name: "defense"),
            .uint8(name: "special_attack"),
            .uint8(name: "special_defense"),
            .uint8(name: "speed"),
        ],
        description: "Six IVs in HP/Atk/Def/SpA/SpD/Spe order (6 bytes)"
    )

    static let trainerPokemonMoveStruct = StructMap(
        name: "TrainerPokemonMove",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .padding(length: 4),
            .int16(name: "pp", description: "Usually 0"),
            .abstraction(name: "move", typeName: "Moves", description: "0xFFFF (Moves_65535) picks a random move"),
        ],
        description: "One move slot of a trainer's Pokemon (8 bytes)"
    )

    static let trainerPokemonStruct = StructMap(
        name: "TrainerPokemonData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int8(name: "ability_slot", description: "0 or 1; -1 for random"),
            .abstraction(name: "gender", typeName: "Gender"),
            .abstraction(name: "nature", typeName: "Nature"),
            .uint8(name: "shadow_id", description: "Index into the ShadowData table, 0 for a normal Pokemon"),
            .uint8(name: "level"),
            .uint8(name: "unknown_1", description: "Possibly the priority for sending this Pokemon out"),
            .uint8(name: "ai_role", description: "Index into the AIPokemonRoles table"),
            .padding(length: 1),
            .int16(name: "happiness"),
            .abstraction(name: "species", typeName: "PokemonSpecies"),
            .abstraction(name: "pokeball", typeName: "Items"),
            .padding(length: 2),
            .uint32(name: "held_item", description: "Item id; 0xFFFFFFFF for none"),
            .uint32(name: "name_id"),
            .uint32(name: "unknown_2"),
            .subStruct(name: "ivs", typeName: "PokemonIVs"),
            .subStruct(name: "evs", typeName: "PokemonBaseStats"),
            .padding(length: 2),
            .array(name: "moves", count: 4, of: .subStruct(name: "TrainerPokemonMove")),
        ],
        description: "A trainer's Pokemon (0x50 bytes per entry; a trainer's team is six consecutive entries)"
    )

    static let trainerAIDataStruct = StructMap(
        name: "TrainerAIData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .array(name: "unknown_flags_a", count: 6, of: .boolean),
            .array(name: "unknown_percentages_a", count: 3, of: .uint8),
            .array(name: "unknown_flags_b", count: 4, of: .boolean),
            .uint8(name: "unknown_percentage_b"),
            .boolean(name: "unknown_flag_c"),
            .array(name: "unknown_values_a", count: 2, of: .int8),
            .array(name: "unknown_flags_d", count: 5, of: .boolean),
            .uint8(name: "unknown_percentage_c"),
            .boolean(name: "unknown_flag_e"),
            .uint8(name: "unknown_percentage_d"),
            .uint8(name: "unknown_flags_f", description: "A bitfield"),
            .padding(length: 2),
            .uint32(name: "unknown_id"),
            .array(name: "unknown_values_b", count: 8, of: .int8),
        ],
        description: "Trainer AI behavior (0x28 bytes per entry)"
    )

    static let shadowPokemonFlagsStruct = StructMap(
        name: "ShadowPokemonFlags",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "unknown_1"),
            .uint16(name: "captured_flag", description: "Set once the Pokemon is caught"),
            .uint16(name: "unknown_2"),
            .uint16(name: "unknown_3"),
        ],
        description: "Flags set as a Shadow Pokemon is caught and purified (8 bytes)"
    )

    static let shadowDataStruct = StructMap(
        name: "ShadowData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "catch_rate", description: "Overrides the species catch rate"),
            .padding(length: 1),
            .abstraction(name: "species", typeName: "PokemonSpecies"),
            .uint16(name: "first_trainer_index", description: "Trainer of the first encounter"),
            .uint16(name: "alternative_first_trainer_index", description: "Trainer of the other possible first encounter"),
            .uint16(name: "heart_gauge", description: "How long purification takes"),
            .uint16(name: "index"),
            .uint16(name: "unknown_1"),
            .padding(length: 2),
            .subStruct(name: "flag_ids", typeName: "ShadowPokemonFlags"),
            .uint32(name: "unknown_2"),
            .uint16(name: "unknown_3"),
            .uint16(name: "unknown_4"),
            .uint32(name: "debug_name_id"),
            .array(name: "unknown_5", count: 6, of: .uint16),
            .array(name: "unknown_6", count: 2, of: .uint32),
        ],
        description: "Shadow Pokemon (0x38 bytes per entry)"
    )

    // MARK: - Rooms

    static let roomScriptFunctionStruct = StructMap(
        name: "RoomScriptFunction",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "script", description: "Whether the function is in the room's script or the common script"),
            .uint16(name: "function_index"),
        ],
        description: "A script function a room runs (4 bytes)"
    )

    private static var roomHeadProperties: [StructMap.Property] {
        [
            // The floor kind lives in bits 7:5 of this byte and the low five
            // bits are zero on every room of every disc, so the whole byte is
            // the `RoomKind` enum (raw values kind × 32). It is what the
            // engine reads to pick the shadow cutoff distance and shadow-map
            // size when a room loads: Field rooms use 70 units (0 — no cutoff
            // — for rooms 0x72–0x74) with a 384×384 shadow map, Battle and
            // MoveViewer rooms 80 units with a 640×480 map, and the other
            // kinds leave the previous value in place
            // (GSmodelSetShadowCutoffDist stores the square).
            .abstraction(name: "kind", typeName: "RoomKind", description: "Floor kind in bits 7:5 (low bits unused); selects the shadow cutoff distance and shadow-map size among other things"),
            .uint8(name: "area_id"),
        ]
    }

    private static var roomPointerProperties: [StructMap.Property] {
        [
            .label(name: "render_data_pointer", description: "DOL data: lighting, shadow and fog setup"),
            .label(name: "character_data_pointer"),
            .label(name: "warp_point_data_pointer"),
            .label(name: "camera_data_pointer"),
        ]
    }

    private static var roomTailProperties: [StructMap.Property] {
        [
            .padding(length: 4),
            .uint32(name: "name_id"),
            .array(name: "script_functions", count: 5, of: .subStruct(name: "RoomScriptFunction")),
            .label(name: "preprocess_function", description: "Called before the room loads"),
            .label(name: "main_function", description: "Called every frame in the room"),
            .label(name: "postprocess_function", description: "Called after the room unloads"),
            .label(name: "unknown_data_pointer", description: "DOL data; set for 12 rooms"),
        ]
    }

    static let roomStruct = StructMap(
        name: "Room",
        wordSize: 4,
        alignmentStyle: .none,
        properties: roomHeadProperties + [
            .padding(length: 4),
            .uint16(name: "fsys_id", description: "Group id of the room's FSYS archive"),
            .padding(length: 4),
            .uint32(name: "room_id"),
        ] + roomPointerProperties + roomTailProperties,
        description: "Room (floor) definition, US and JP layout (0x4C bytes per entry)"
    )

    static let roomEUStruct = StructMap(
        name: "RoomEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: roomHeadProperties + [
            .padding(length: 6),
            .uint32(name: "room_id"),
        ] + roomPointerProperties + roomTailProperties + [
            .uint32(name: "fsys_id_us_uk", description: "Group id of the room's FSYS archive"),
            .uint32(name: "fsys_id_german"),
            .uint32(name: "fsys_id_french"),
            .uint32(name: "fsys_id_italian"),
            .uint32(name: "fsys_id_spanish"),
        ],
        description: "Room (floor) definition, PAL layout: five fsys ids at the end instead of one up front (0x5C bytes per entry)"
    )

    // MARK: - Moves and natures

    static let moveStruct = StructMap(
        name: "Move",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int8(name: "priority"),
            .uint8(name: "base_pp"),
            .abstraction(name: "type", typeName: "Type"),
            .abstraction(name: "targets", typeName: "MoveTarget"),
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
            .uint8(name: "has_risk_flag"),
            .uint8(name: "contest_appeal_jam_index"),
            .abstraction(name: "contest_appeal_type", typeName: "ContestCategory"),
            .uint16(name: "base_power"),
            .uint32(name: "effect"),
            .uint16(name: "animation_id"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "unused_string_id"),
            .uint32(name: "exclamation_string_id"),
            .uint32(name: "description_id"),
            .padding(length: 2),
            .uint16(name: "animation_id_2"),
            .abstraction(name: "move_effect_type", typeName: "MoveEffectType"),
            .abstraction(name: "move_effect_type_2", typeName: "MoveEffectType"),
            .abstraction(name: "move_effect_type_3", typeName: "MoveEffectType"),
            .padding(length: 1),
        ],
        description: "Move properties (0x38 bytes per entry; wazaDataBiosGetPtr)"
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
            .uint8(name: "unknown_1", description: "100 on every nature"),
            .array(name: "unknown_2", count: 8, of: .uint8, description: "Values of 5, 10 and 20 — per-nature percentages of something"),
            .padding(length: 1),
            .uint32(name: "name_id"),
            .array(name: "unknown_3", count: 7, of: .uint8, description: "Values of 5…70 — per-nature percentages, likely flavor preferences"),
            .array(name: "unknown_4", count: 7, of: .uint8, description: "100 on every nature"),
            .padding(length: 2),
        ],
        description: "Nature stat multipliers and purification data (0x28 bytes per entry; pokemonSeikakuDataBiosGetPtr)"
    )

    // MARK: - Species data (PokemonStats)

    static let pokemonBaseStatsStruct = StructMap(
        name: "PokemonBaseStats",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "hp"),
            .uint16(name: "attack"),
            .uint16(name: "defense"),
            .uint16(name: "special_attack"),
            .uint16(name: "special_defense"),
            .uint16(name: "speed"),
        ],
        description: "Six stat values in HP/Atk/Def/SpA/SpD/Spe order (0x0C bytes)"
    )

    static let pokemonEvolutionStruct = StructMap(
        name: "PokemonEvolution",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "method", typeName: "EvolutionMethod"),
            .padding(length: 1),
            .uint16(name: "condition", description: "Level or item ID, depending on the method"),
            .abstraction(name: "evolved_species", typeName: "PokemonSpecies"),
        ],
        description: "One evolution slot (6 bytes)"
    )

    static let pokemonLevelUpMoveStruct = StructMap(
        name: "PokemonLevelUpMove",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "level"),
            .padding(length: 1),
            .abstraction(name: "move", typeName: "Moves"),
        ],
        description: "One level-up move slot (4 bytes)"
    )

    static let pokemonSpriteStruct = StructMap(
        name: "PokemonSprite",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "pokedex_color"),
            .padding(length: 1),
            .uint16(name: "face_index", description: "Index into the PokefaceTextures table"),
            .uint32(name: "body_file_id", description: "File identifier of the animated body texture in poke_body.fsys"),
        ],
        description: "Portrait and body art references for one coloration (8 bytes)"
    )

    static let pokemonStatStruct = StructMap(
        name: "PokemonStat",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "exp_rate", typeName: "ExpRate"),
            .uint8(name: "catch_rate"),
            .abstraction(name: "gender_ratio", typeName: "GenderRatio"),
            .uint8(name: "unknown_1", description: "5 for every real species, 0 for the dummy rows"),
            .uint8(name: "unknown_2"),
            .padding(length: 1),
            .uint16(name: "base_exp_yield"),
            .uint16(name: "base_friendship"),
            .uint16(name: "height", description: "PAL and JP: meters × 10. US: feet × 100 + inches (Bulbasaur is 204 for 2'04\")"),
            .uint16(name: "weight", description: "PAL and JP: kilograms × 10. US: pounds × 10"),
            .uint16(name: "cry_id"),
            .uint16(name: "national_dex_index"),
            .uint16(name: "unknown_3", description: "Sound related; the legacy tool called it the shout id"),
            .uint16(name: "pokedex_number", description: "Hoenn Pokédex order; species outside it are listed after Deoxys"),
            .uint16(name: "unknown_4"),
            .uint32(name: "name_id"),
            .uint32(name: "species_name_id", description: "The \"Seed Pokémon\" category string"),
            .uint32(name: "unknown_5", description: "0 on every disc"),
            .uint32(name: "unknown_6", description: "In XD this slot is the seen flag"),
            .uint32(name: "caught_flag_id"),
            .uint32(name: "model_index", description: "Index into the DOL's PKX model table"),
            .abstraction(name: "type_1", typeName: "Type"),
            .abstraction(name: "type_2", typeName: "Type"),
            .abstraction(name: "ability_1", typeName: "Abilities"),
            .abstraction(name: "ability_2", typeName: "Abilities"),
            .array(name: "learnable_tms", count: 50, of: .boolean, description: "TM01…TM50"),
            .array(name: "learnable_hms", count: 8, of: .boolean, description: "HM01…HM08"),
            .abstraction(name: "egg_group_1", typeName: "EggGroup"),
            .abstraction(name: "egg_group_2", typeName: "EggGroup"),
            .abstraction(name: "wild_item_1", typeName: "Items"),
            .abstraction(name: "wild_item_2", typeName: "Items"),
            .array(name: "egg_moves", count: 8, of: .enumeration(name: "Moves")),
            .subStruct(name: "base_stats", typeName: "PokemonBaseStats"),
            .subStruct(name: "ev_yields", typeName: "PokemonBaseStats"),
            .array(name: "evolutions", count: 5, of: .subStruct(name: "PokemonEvolution")),
            .array(name: "level_up_moves", count: 20, of: .subStruct(name: "PokemonLevelUpMove"), description: "No species on disc uses more than 13 slots"),
            .padding(length: 2),
            .subStruct(name: "sprites", typeName: "PokemonSprite"),
            .subStruct(name: "shiny_sprites", typeName: "PokemonSprite"),
        ],
        description: "Species data (0x11C bytes per entry; 413 on every disc)"
    )
}
