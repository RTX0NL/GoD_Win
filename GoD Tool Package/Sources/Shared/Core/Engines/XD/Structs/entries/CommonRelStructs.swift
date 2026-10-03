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
            .abstraction(name: "type", typeName: "Type"),
            .abstraction(name: "targets", typeName: "MoveTarget"),
            .uint8(name: "base_accuracy"),
            .uint8(name: "effect_accuracy"),
            .boolean(name: "makes_contact"),
            .boolean(name: "can_be_protected"),
            .boolean(name: "can_be_reflected"),
            .boolean(name: "can_be_stolen"),
            .boolean(name: "can_be_copied_mirror_move"),
            .boolean(name: "gains_flinch_kings_rock"),
            .boolean(name: "callable_by_metronome"),
            .boolean(name: "copyable_by_mimic"),
            .boolean(name: "callable_by_assist"),
            .boolean(name: "callable_by_sleep_talk"),
            .boolean(name: "is_sound_based"),
            .boolean(name: "has_unspecified_target"),
            .boolean(name: "is_hm_move"),
            .abstraction(name: "category", typeName: "MoveCategory"),
            .boolean(name: "has_risk_flag"),
            .abstraction(name: "matchup_display", typeName: "MoveMatchupDisplay", description: "The status screen's matchup sprite (wazaDB_GetCompatible)"),
            .uint8(name: "contest_appeal_jam_index"),
            .abstraction(name: "contest_appeal_type", typeName: "ContestCategory"),
            .uint16(name: "base_power"),
            .uint16(name: "battle_effect_id", description: "fightKoukaDataId; 0 for every move on disc"),
            .uint16(name: "effect", description: "seqId — the battle sequence that implements the move"),
            .uint16(name: "animation_id", description: "wazaFuncDataId — the move's function set (WZX type and variation, AI value/hit/damage)"),
            .uint32(name: "name_id"),
            .uint32(name: "unused_string_id"),
            .uint32(name: "exclamation_string_id"),
            .uint32(name: "description_id"),
            .uint32(name: "wzx_data_id", description: "FSYS id of the move's animation data"),
            // wazaDataBiosGetTypeId(waza, i) reads 0x34 + i for i in 0…2:
            // three effect-type slots, most moves using only the first.
            .abstraction(name: "move_effect_type", typeName: "MoveEffectType"),
            .abstraction(name: "move_effect_type_2", typeName: "MoveEffectType"),
            .abstraction(name: "move_effect_type_3", typeName: "MoveEffectType"),
            .padding(length: 1),
        ],
        description: "Move properties (0x38 bytes per entry; wazaDataBiosGetPtr)"
    )

    static let itemStruct = StructMap(
        name: "Item",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "bag_slot", typeName: "ItemPocket"),
            .boolean(name: "cannot_be_held", description: "itemDataBiosGetImportant — key items"),
            .boolean(name: "useful_flag", description: "itemDataBiosGetUseful; set for 7 items on the US disc"),
            .boolean(name: "can_be_deposited", description: "itemDataBiosGetDeposit — may go into the PC"),
            .uint8(name: "in_battle_use_id", description: "itemDataBiosGetItemEffectParam"),
            .padding(length: 1),
            .uint16(name: "price"),
            .uint16(name: "coupon_price"),
            .uint16(name: "hold_effect_id", description: "itemDataBiosGetItemSoubiDataId — effect while held in battle"),
            .uint16(name: "battle_use_effect_id", description: "itemDataBiosGetFightUseKoukaDataId; 0 for every item on disc"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "description_id"),
            .uint32(name: "parameter", description: "itemDataBiosGetBuff — effect strength"),
            .label(name: "field_use_function", description: "Relocated to the DOL routine run when used from the bag"),
            .label(name: "battle_use_function", description: "Relocated to the DOL routine run when used in battle"),
            .int8(name: "friendship_effect_1", description: "Friendship change below 100"),
            .int8(name: "friendship_effect_2", description: "Friendship change from 100 to 199"),
            .int8(name: "friendship_effect_3", description: "Friendship change at 200 and above"),
            .padding(length: 1),
        ],
        description: "Item properties (0x28 bytes per entry; itemDataBiosGetPtr)"
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

    static let typeStruct = StructMap(
        name: "Type",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // A type's damage class (Gen III types are wholly physical or
            // special). The same value space as a move's category:
            // `waza_GetZokuseiKindData` returns one or the other, and the AI's
            // Counter and Mirror Coat handlers compare it with 1 and 2.
            .abstraction(name: "category", typeName: "MoveCategory"),
            .padding(length: 1),
            .uint16(name: "icon_big_id"),
            .uint16(name: "icon_small_id"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .array(name: "effectiveness", count: 18, of: .enumeration(name: "TypeEffectiveness"), description: "One entry per defending type, in type order; on disc 0x3F is neutral, 0x41 super effective, 0x42 not very effective, 0x43 no effect"),
        ],
        description: "Type matchup and properties (0x30 bytes per entry)"
    )

    /// `fight_trainer_kind_data`, stride 0xC (`fightTrainerKindDataBiosGetPtr`).
    static let trainerClassStruct = StructMap(
        name: "TrainerClass",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "payout_multiplier", description: "GetSyoukinBairitu"),
            .padding(length: 2),
            .uint32(name: "name_id", description: "GetPrefixName: the class name before a trainer's own"),
            .uint32(name: "bgm_id", description: "GetBgmSndId"),
        ],
        description: "Trainer class name, payout and music (0x0C bytes)"
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
            .abstraction(name: "kind", typeName: "TreasureKind", description: "_floorInitTresure reads bits 7:5"),
            .uint8(name: "quantity"),
            .int16(name: "angle"),
            .uint16(name: "room_id"),
            .uint16(name: "flag_id", description: "Set once the item has been collected"),
            .padding(length: 4),
            .uint32(name: "item_id"),
            .float(name: "x_position"),
            .float(name: "y_position"),
            .float(name: "z_position"),
        ],
        description: "Treasure box location and contents (0x1C bytes per entry; NumberOfTreasureBoxes)"
    )

    /// `floor_door_list`, stride 0x18 (`_floorInitDoor`,
    /// `floorEventCtrlDoor`, `floorEventCtrlElevator*`). Bytes 0-8 are read
    /// one at a time; only the door kind is understood so far.
    static let doorStruct = StructMap(
        name: "Door",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_0x00"),
            .uint8(name: "unknown_0x01"),
            .uint8(name: "unknown_0x02"),
            .uint8(name: "unknown_0x03"),
            .uint8(name: "unknown_0x04"),
            .uint8(name: "unknown_0x05"),
            .uint8(name: "unknown_0x06"),
            .uint8(name: "door_kind", description: "Switched on by the door code: 0, 1, 2, up to 6"),
            .uint8(name: "unknown_0x08"),
            .padding(length: 1),
            .int16(name: "unknown_0x0A"),
            .uint16(name: "room_id", description: "Compared with the current floor"),
            .uint16(name: "flag_id", description: "GSflagTest"),
            .uint16(name: "unknown_0x10"),
            .padding(length: 2),
            .uint32(name: "unknown_0x14", description: "Tested for non-zero"),
        ],
        description: "A door or elevator (floor_door_list, 0x18 bytes)"
    )

    /// `floor_event_list`, stride 0x1C (`floorEventExecScript`).
    static let interactionPointStruct = StructMap(
        name: "InteractionPoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "event_kind", description: "Compared with the kind of event being run"),
            .padding(length: 1),
            .uint16(name: "room_id", description: "Compared with GSfloorGetCurrent"),
            .uint32(name: "event_id", description: "The collision/event id; passed to scriptSetEventColID"),
            .uint32(name: "script_function", description: "Run through floorExecScriptInteger; 0 skips the row"),
            .uint32(name: "parameter_1"),
            .uint32(name: "parameter_2"),
            .uint32(name: "parameter_3"),
            .uint32(name: "parameter_4"),
        ],
        description: "A map event: script run on touching or checking something (floor_event_list, 0x1C bytes)"
    )

    /// `fight_floor_data`, stride 0x18 on US/JP (`fightFloorDataBiosGetPtr`).
    static let battleFieldStruct = StructMap(
        name: "BattleField",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "terrain", description: "GetTikeiDataId"),
            .padding(length: 1),
            .uint16(name: "room_id", description: "GetFloorDataId"),
            .uint32(name: "name_id"),
            .uint32(name: "intro_wzx_id", description: "GetSyoukaiWzxDataId"),
            .uint32(name: "bgm_id"),
            .uint32(name: "environment_sound_id"),
            .array(name: "side_ids", count: 2, of: .uint16, description: "BattleSideData rows (GetFightSideDataId)"),
        ],
        description: "A battlefield (fight_floor_data, 0x18 bytes)"
    )

    /// PAL widens the record by four per-language intro WZX ids, in the same
    /// language order as `BattleEU` (stride 0x28 in PAL's own accessor).
    static let battleFieldEUStruct = StructMap(
        name: "BattleFieldEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "terrain"),
            .padding(length: 1),
            .uint16(name: "room_id"),
            .uint32(name: "name_id"),
            .uint32(name: "intro_wzx_id_english"),
            .uint32(name: "intro_wzx_id_german"),
            .uint32(name: "intro_wzx_id_french"),
            .uint32(name: "intro_wzx_id_italian"),
            .uint32(name: "intro_wzx_id_spanish"),
            .uint32(name: "bgm_id"),
            .uint32(name: "environment_sound_id"),
            .array(name: "side_ids", count: 2, of: .uint16),
        ],
        description: "A battlefield, PAL layout (fight_floor_data, 0x28 bytes)"
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

    /// `poke_face`, stride 8 (`_menuFaceBiosGetPtr`).
    static let pokefaceStruct = StructMap(
        name: "Pokeface",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "flags", description: "Bit 7 shiny (menuFaceBiosGetRareFlag); bit 6 set on nearly every row, no reader found"),
            .padding(length: 3),
            .uint32(name: "image_file_id", description: "menuFaceBiosGetTexID"),
        ],
        description: "Pokemon portrait image reference (8 bytes)"
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

    /// `fight_trainer_pokemon_part_data`, stride 0x18
    /// (`fightTrainerPokemonPartDataBiosGetPtr`).
    static let pokemonAIRoleStruct = StructMap(
        name: "PokemonAIRole",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "name_id", description: "fightTrainerPokemonPartDB_GetName"),
            .uint32(name: "unknown_0x04", description: "No reader found"),
            .array(name: "move_type_weights", count: 14, of: .uint8, description: "fightTrainerPokemonPartDB_GetWazaTypeRevise"),
            .padding(length: 2),
        ],
        description: "Pokemon AI role (0x18 bytes)"
    )

    static let tutorMoveStruct = StructMap(
        name: "TutorMove",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "move_id", typeName: "Moves"),
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
            .abstraction(name: "item_id", typeName: "Items"),
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

    /// `char_name`, stride 8 (`charNameBiosGet*`).
    static let peopleIDStruct = StructMap(
        name: "PeopleID",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "hear_flag_id", description: "charNameBiosGetHearFlag"),
            .padding(length: 2),
            .uint32(name: "name_id", description: "charNameBiosGetNameID; searched by charNameBiosSearchIndex"),
        ],
        description: "Character name (8 bytes)"
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

    static let rgbaColorStruct = StructMap(
        name: "RGBAColor",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "red"),
            .uint8(name: "green"),
            .uint8(name: "blue"),
            .uint8(name: "alpha"),
        ],
        description: "RGBA color value (4 bytes)"
    )

    /// `pokemon_menu_animation`, stride 4
    /// (`menuModelGetPokemonAnimationIndexByID`).
    static let pokemonMenuAnimationStruct = StructMap(
        name: "PokemonMenuAnimation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "animation_id", description: "Returned minus 1"),
            .padding(length: 1),
            .abstraction(name: "species_id", typeName: "PokemonSpecies", description: "The search key"),
        ],
        description: "Pokemon summary screen animation override (4 bytes)"
    )

    // MARK: - Species data (PokemonStats)
    //
    // Layout from the `pokemonDataBiosGet*` accessors in
    // `text1/pokemonBios/` — stride 0x124 (`pokemonDataBiosGetPtr`), every
    // field offset below is the one an accessor reads. See
    // `Documentation/Assembly Analysis/Data Structures/PokemonData.md`.

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
        description: "Six stat values in HP/Atk/Def/SpA/SpD/Spe order (0x0C bytes; pokemonDataBiosGetBasisStatusPtr)"
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
        description: "One evolution slot (6 bytes; pokemonDataBiosGetSinkaPtr)"
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
        description: "One level-up move slot (4 bytes; pokemonDataBiosGetGetWazaPtr)"
    )

    static let pokemonSpriteStruct = StructMap(
        name: "PokemonSprite",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "pokedex_color", typeName: "PokedexColor"),
            .padding(length: 1),
            .uint16(name: "face_index", description: "Index into the PokefaceTextures table"),
            .uint32(name: "body_file_id", description: "File identifier of the animated body texture in poke_dance.fsys"),
        ],
        description: "Portrait and body art references for one coloration (8 bytes; pokemonDataBiosGetCgDataPtr)"
    )

    static let pokemonStatStruct = StructMap(
        name: "PokemonStat",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "exp_rate", typeName: "ExpRate"),
            .uint8(name: "catch_rate"),
            .abstraction(name: "gender_ratio", typeName: "GenderRatio"),
            .padding(length: 1),
            .uint16(name: "base_exp_yield"),
            .uint16(name: "base_friendship"),
            .uint16(name: "height", description: "Meters × 10"),
            .uint16(name: "weight", description: "Kilograms × 10"),
            .uint16(name: "cry_id"),
            .uint16(name: "national_dex_index"),
            .uint16(name: "unknown_1", description: "Sound related; 1356–1360 on the US disc"),
            .uint16(name: "pokemon_number", description: "National number again, 0 for the entries without a Strategy Memo page (pokemonDataBiosGetNumPokemon)"),
            .uint16(name: "pokedex_number", description: "Hoenn Pokédex order; species outside it are listed after Deoxys (pokemonDataBiosGetNumZukan)"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "species_name_id", description: "The \"Seed Pokémon\" category string, in pda_menu"),
            .uint32(name: "description_id", description: "Always 0 on disc; read by pokemonDataBiosGetDoc"),
            .uint32(name: "seen_flag_id"),
            .uint32(name: "caught_flag_id"),
            .uint32(name: "model_index", description: "Index into the DOL's PKXModel table"),
            .abstraction(name: "type_1", typeName: "Type"),
            .abstraction(name: "type_2", typeName: "Type"),
            .abstraction(name: "ability_1", typeName: "Abilities"),
            .abstraction(name: "ability_2", typeName: "Abilities"),
            .array(name: "learnable_tms", count: 50, of: .boolean, description: "TM01…TM50"),
            .array(name: "learnable_hms", count: 8, of: .boolean, description: "HM01…HM08"),
            .array(
                name: "learnable_tutor_moves", count: 12, of: .boolean,
                description: "In the game's internal tutor order, not the TutorMoves table's: "
                    + "1 Mimic, 2 Thunder Wave, 3 Seismic Toss, 4 Icy Wind, 5 Substitute, 6 Dream Eater, "
                    + "7 Swagger, 8 Body Slam, 9 Nightmare, 10 Sky Attack, 11 Double-Edge, 12 Self-Destruct "
                    + "(pokemonDB_GetTeachWaza)"
            ),
            .abstraction(name: "wild_item_1", typeName: "Items"),
            .abstraction(name: "wild_item_2", typeName: "Items"),
            .array(name: "egg_moves", count: 8, of: .enumeration(name: "Moves")),
            .subStruct(name: "base_stats", typeName: "PokemonBaseStats"),
            .subStruct(name: "ev_yields", typeName: "PokemonBaseStats"),
            .array(name: "evolutions", count: 5, of: .subStruct(name: "PokemonEvolution")),
            .array(name: "level_up_moves", count: 20, of: .subStruct(name: "PokemonLevelUpMove"), description: "The accessor allows 20 slots; no species on disc uses more than 18"),
            .subStruct(name: "sprites", typeName: "PokemonSprite"),
            .subStruct(name: "shiny_sprites", typeName: "PokemonSprite"),
        ],
        description: "Species data (0x124 bytes per entry; pokemonDataBiosGetPtr)"
    )

    // MARK: - Battles
    //
    // `fightEncountData`: layout from `text1/fightEncountBios/`, stride 0x3C
    // (`fightEncountDataBiosGetPtr`). The PAL build inserts four words of
    // per-language intro ids after the English one, so it is a separate
    // definition that the PAL type map names. See
    // `Documentation/Assembly Analysis/Data Structures/FightEncountData.md`.

    static let battlePlayerStruct = StructMap(
        name: "BattlePlayer",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "deck", typeName: "Deck"),
            .uint16(name: "trainer_id", description: "Index into the deck's trainer table; 5000 with deck DarkPokemon is the player"),
            .abstraction(name: "controller", typeName: "BattleController"),
        ],
        description: "One of a battle's four participant slots (8 bytes; fightEncountDataBiosGetFightTrainerInfoPtr)"
    )

    private static var battleHeadProperties: [StructMap.Property] {
        [
            .abstraction(name: "battle_kind", typeName: "BattleKind"),
            .uint8(name: "trainers_per_side"),
            .abstraction(name: "battle_style", typeName: "BattleStyle"),
            .uint8(name: "pokemon_per_trainer"),
            .boolean(name: "blackout_on_loss", description: "Losing ends the game rather than the encounter (fightEncountDataBiosGetZenmetuFlag)"),
            .padding(length: 1),
            .uint16(name: "battle_field_index", description: "Index into the BattleFields table"),
            .uint16(name: "battle_cd_id", description: "Set at run time; 0 on disc"),
            .padding(length: 2),
            .uint32(name: "name_id"),
            .uint32(name: "bgm_id"),
            .uint32(name: "wipe_id", description: "Screen transition into the battle"),
            .uint32(name: "intro_wzx_id", description: "Colosseum round announcement: 0x95 round 1, 0x96 round 2, 0x9B semifinal, 0x9C final, 0 otherwise"),
        ]
    }

    static let battleStruct = StructMap(
        name: "Battle",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleHeadProperties + [
            .array(name: "players", count: 4, of: .subStruct(name: "BattlePlayer")),
        ],
        description: "Battle setup, US and JP layout (0x3C bytes per entry; fightEncountDataBiosGetPtr)"
    )

    static let battleEUStruct = StructMap(
        name: "BattleEU",
        wordSize: 4,
        alignmentStyle: .none,
        properties: battleHeadProperties + [
            .uint32(name: "intro_wzx_id_german"),
            .uint32(name: "intro_wzx_id_french"),
            .uint32(name: "intro_wzx_id_italian"),
            .uint32(name: "intro_wzx_id_spanish"),
            .array(name: "players", count: 4, of: .subStruct(name: "BattlePlayer")),
        ],
        description: "Battle setup, PAL layout: four more intro ids, one per extra language (0x4C bytes per entry)"
    )

    // MARK: - Pokespots
    //
    // `esaba` (餌場, "feeding ground"): the descriptor's fields are all
    // flag ids, read through GSflagGet with a stride of 0x1C; the encounter
    // entries are the 0xC-byte records `_esabaAppearPokemonSub2` walks. See
    // `Documentation/Assembly Analysis/Data Structures/EsabaData.md`.

    static let pokespotStruct = StructMap(
        name: "Pokespot",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "snack_count_flag_id", description: "Flag holding the number of snacks on the ground"),
            .uint32(name: "unknown_flag_id_1", description: "Cleared when the snacks run out"),
            .uint32(name: "unknown_flag_id_2", description: "Cleared when the snacks run out or a Pokémon appears"),
            .uint32(name: "spawned_species_flag_id", description: "Flag holding the species currently at the spot"),
            .uint32(name: "spawned_pid_flag_id", description: "Flag holding that Pokémon's personality value"),
            .uint32(name: "unknown_flag_id_3"),
            .label(name: "encounter_table_pointer", description: "Relocated to the DOL's encounter list for this spot"),
        ],
        description: "Pokespot save-flag bindings (0x1C bytes per entry; esabaGet*)"
    )

    static let pokespotEncounterStruct = StructMap(
        name: "PokespotEncounter",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "min_level"),
            .uint8(name: "max_level"),
            .abstraction(name: "species", typeName: "PokemonSpecies"),
            .uint32(name: "encounter_rate", description: "Percent; a spot's entries sum to 100"),
            .uint32(name: "steps_per_snack", description: "Steps the Pokémon takes to eat one snack (esabaGetDigestRate)"),
        ],
        description: "One Pokespot encounter (0x0C bytes per entry; PokespotRock/Oasis/Cave/All)"
    )

    // MARK: - Rooms
    //
    // `FloorData`: layout from `text1/floorDataBios/`, stride 0x40
    // (`floorDataBiosGetPtr`). The pointer fields are 0 on disc and carry a
    // relocation to a DOL address where set. The JP build has a single
    // fsys id at +0x04 instead of five at the end, so it is a separate
    // definition that the JP type map names. See
    // `Documentation/Assembly Analysis/Data Structures/FloorData.md`.

    private static var roomHeadProperties: [StructMap.Property] {
        [
            .abstraction(name: "area", typeName: "Area", description: "Compared for equality only: a change of area clears flag level 2"),
            .abstraction(name: "kind", typeName: "RoomKind", description: "floorKind — which lifecycle, shadow, fog and control path the floor code takes"),
            .uint16(name: "room_id"),
        ]
    }

    private static var roomRuntimeProperties: [StructMap.Property] {
        [
            .uint32(name: "map_file_id", description: "Set at run time; 0 on disc"),
            .label(name: "render_data_pointer", description: "Lighting, shadow and fog setup"),
            .label(name: "character_data_pointer"),
            .label(name: "warp_point_data_pointer"),
            .label(name: "camera_data_pointer"),
            .uint32(name: "name_id"),
            .label(name: "preprocess_function", description: "Called before the room loads"),
            .label(name: "main_function", description: "Called every frame in the room"),
            .label(name: "postprocess_function", description: "Called after the room unloads"),
            .label(name: "unknown_data_pointer", description: "DOL data; set for 16 rooms"),
        ]
    }

    static let roomStruct = StructMap(
        name: "Room",
        wordSize: 4,
        alignmentStyle: .none,
        properties: roomHeadProperties + roomRuntimeProperties + [
            .uint32(name: "fsys_id_us_uk", description: "Group id of the room's FSYS archive"),
            .uint32(name: "fsys_id_german"),
            .uint32(name: "fsys_id_french"),
            .uint32(name: "fsys_id_italian"),
            .uint32(name: "fsys_id_spanish"),
        ],
        description: "Room (floor) definition, US and PAL layout (0x40 bytes per entry; floorDataBiosGetPtr)"
    )

    static let roomJPStruct = StructMap(
        name: "RoomJP",
        wordSize: 4,
        alignmentStyle: .none,
        properties: roomHeadProperties + [
            .uint32(name: "fsys_id", description: "Group id of the room's FSYS archive"),
        ] + roomRuntimeProperties,
        description: "Room (floor) definition, JP layout: one fsys id, before the run-time fields (0x30 bytes per entry)"
    )

    /// One entry of `common.rel`'s **`GeneralFlags`** table — the schema half
    /// of XD's flag system (2324 × 6 bytes). The values live in save section
    /// 8; nothing in the save says where one flag ends and the next begins,
    /// so this table is what makes the banks readable. Full write-up in
    /// `Documentation/Assembly Analysis/Data Structures/Flags.md`.
    ///
    /// Byte-identical on US, PAL and JP — one table serves every build.
    static let generalFlagStruct = StructMap(
        name: "GeneralFlag",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // +0x0 packs two fields. `GSflagGet` masks it one way for the
            // bank, `_flagGet` the other for the width.
            .bits(name: "bankAndBitLength", description: "Which bank the flag lives in, and how wide it is", fields: [
                .number(name: "bank", bits: 0...1, description: "1-3; 0 would mean the flag has no storage, which nothing uses"),
                .number(name: "bitLength", bits: 2...7, description: "1-32; 149 of the 2324 flags are wider than one bit"),
            ]),
            .uint8(name: "reserved", description: "0 in all 2324 entries"),
            // +0x2 is scratch on disc: `GSflagInitBitPos` fills it at boot
            // with the bank's running bit total over all lower-numbered
            // flags. Zero in every entry of every region's table.
            .uint16(name: "bitPosition", description: "computed at boot by GSflagInitBitPos; 0 on disc"),
            // +0x4 threads every flag into one list for the debug menu
            // (`_dbgMenuFlagGetID` walks it). From entry 0 it visits all 2324
            // exactly once and ends at -1.
            .int16(name: "nextFlagID", description: "next flag in the debug-menu chain, -1 ends"),
        ],
        description: "GeneralFlags entry: XD's flag descriptor (bank + bit width + debug-menu link)"
    )
}
