import Structs
import GoDFoundation

/// `common.rel` tables named from the code that reads them.
///
/// The legacy tool named most of these by pointer index and nothing more.
/// Each table was found from the DOL global its `_prolog` registers it into
/// (read through `r13`, base 0x804EFE20) — never from the symbol map's names
/// for those globals, which are misplaced by a slot in places — and every
/// field was checked against every row on the US, PAL and JP discs. Layouts
/// and row counts are identical on all three. A field nothing reads is
/// `unknown_*`; a description says when a name rests on data alone.
public extension XDStructDefaults {

    /// `contest_data`: one Gen-3 contest effect per row. A move's +0x16 indexes it.
    static let contestEffectStruct = StructMap(
        name: "ContestEffect",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "appeal", description: "Data: matches the Gen-3 contest effect table row for row; nothing in XD reads it"),
            .uint8(name: "jam", description: "Data, as appeal"),
            .padding(length: 5),
            .uint8(name: "unknown_0x07", description: "1 on rows 1-50, 0 on row 0; unread"),
        ],
        description: "A contest effect (contest_data, 8 bytes)"
    )

    /// `esabaappdata`: when a Pokémon appears at a Pokéspot
    /// (`_esabaCallBackAppFunc`, `_esabaAppearPokemon`).
    static let pokespotAppearanceStruct = StructMap(
        name: "PokespotAppearance",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "appear_step_min", description: "Below this many steps nothing appears"),
            .uint16(name: "appear_step_guaranteed", description: "At this many steps a Pokémon always appears"),
            .uint16(name: "roll_step_interval", description: "Between the two, a roll is made every this many steps"),
            .uint16(name: "roll_chance_divisor", description: "A roll succeeds 1 time in this many"),
            .uint16(name: "extra_list_spot_state", description: "When the spot's state flag equals this (and the story check passes), the Bonsly/Munchlax list is used instead of the spot's own"),
            .uint16(name: "unknown_0x0A", description: "Unread; equals the extra list's first rate"),
            .uint16(name: "unknown_0x0C", description: "Unread; equals the extra list's second rate"),
            .uint16(name: "unknown_0x0E", description: "Unread; 0"),
            .uint32(name: "extra_list_story_step", description: "Index into StoryProgressFlags; story progress below that row's value always uses the spot's own list"),
            .uint32(name: "unknown_0x14", description: "Unread; a value in the Pokéspot flag-id range"),
        ],
        description: "Pokéspot appearance settings (esabaappdata, 0x18 bytes)"
    )

    /// `fight_orre_data`: the Orre Colosseum's battles, 7 colosseums × 4 rounds.
    static let orreColosseumBattleStruct = StructMap(
        name: "OrreColosseumBattle",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "battle_id", description: "Data: rows of the Battles table (87-114, the Orre Colosseum battles); 0 on row 0. Unread"),
            .uint32(name: "unknown_0x04", description: "0 on every row; unread"),
        ],
        description: "An Orre Colosseum battle (fight_orre_data, 8 bytes)"
    )

    /// `fight_side_data` (`fightSideDataBios*`).
    static let battleSideStruct = StructMap(
        name: "BattleSide",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "yrot", description: "Which way the side faces (fightSideDataBiosGetYrot)"),
            .uint16(name: "unknown_0x02", description: "0; unread"),
            .array(name: "trainer_status_menu_ids", count: 2, of: .uint32, description: "fightSideDataBiosGetFightTrainerStatusMenuDataId"),
            .array(name: "pokemon_status_menu_ids", count: 2, of: .uint32, description: "fightSideDataBiosGetFightoutPokemonStatusMenuDataId"),
        ],
        description: "A battle side's layout (fight_side_data, 0x14 bytes)"
    )

    /// `legendPokemonData`: species the game treats as legendary.
    static let legendaryPokemonStruct = StructMap(
        name: "LegendaryPokemon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "species", typeName: "PokemonSpecies", description: "Compared with pokemonBiosGetPokemonDataId; 0 ends the list"),
        ],
        description: "A legendary species (legendPokemonData, 2 bytes)"
    )

    /// `mball_data` — the legacy "MasterBallPokemon" — is the menu sprite of
    /// each Poké Ball, indexed by ball (`mballBiosGetSpriteID`).
    static let ballSpriteStruct = StructMap(
        name: "BallSprite",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "sprite_id", description: "Menu sprite for the ball (mballBiosGetSpriteID); 0 for none. JP's ids are 3 higher"),
        ],
        description: "A Poké Ball's menu sprite (mball_data, 2 bytes)"
    )

    /// `pokemon_dp_filter_data`: base heart-gauge change per purification
    /// kind — battle, walk, Call, daycare, cologne, other
    /// (`pokemonDpFilterDataBiosGetValue`).
    static let heartGaugeChangeStruct = StructMap(
        name: "HeartGaugeChange",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int8(name: "change", description: "Rows: battle, walk, Call (overridden by a constant), daycare, cologne (× the item's strength), other (overridden)"),
        ],
        description: "A base heart-gauge change (pokemon_dp_filter_data, 1 byte)"
    )

    /// `deoxys_pokemon_data`: Deoxys rows in Colosseum's 0x11C `PokemonStat`
    /// layout rather than XD's 0x124, with US imperial height and weight on
    /// every region. Unread by XD's code.
    static let colosseumFormatPokemonStatStruct = StructMap(
        name: "ColosseumFormatPokemonStat",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "exp_rate", typeName: "ExpRate"),
            .uint8(name: "catch_rate"),
            .abstraction(name: "gender_ratio", typeName: "GenderRatio"),
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .padding(length: 1),
            .uint16(name: "base_exp_yield"),
            .uint16(name: "base_friendship"),
            .uint16(name: "height", description: "Feet × 100 + inches, as on the US Colosseum disc, on every region"),
            .uint16(name: "weight", description: "Pounds × 10, on every region"),
            .uint16(name: "cry_id"),
            .uint16(name: "national_dex_index"),
            .uint16(name: "unknown_3"),
            .uint16(name: "pokedex_number"),
            .uint16(name: "unknown_4"),
            .uint32(name: "name_id"),
            .uint32(name: "species_name_id"),
            .uint32(name: "unknown_5"),
            .uint32(name: "unknown_6"),
            .uint32(name: "caught_flag_id"),
            .uint32(name: "model_index"),
            .abstraction(name: "type_1", typeName: "Type"),
            .abstraction(name: "type_2", typeName: "Type"),
            .abstraction(name: "ability_1", typeName: "Abilities"),
            .abstraction(name: "ability_2", typeName: "Abilities"),
            .array(name: "learnable_tms", count: 50, of: .boolean),
            .array(name: "learnable_hms", count: 8, of: .boolean),
            .abstraction(name: "egg_group_1", typeName: "EggGroup"),
            .abstraction(name: "egg_group_2", typeName: "EggGroup"),
            .abstraction(name: "wild_item_1", typeName: "Items"),
            .abstraction(name: "wild_item_2", typeName: "Items"),
            .array(name: "egg_moves", count: 8, of: .enumeration(name: "Moves")),
            .subStruct(name: "base_stats", typeName: "PokemonBaseStats"),
            .subStruct(name: "ev_yields", typeName: "PokemonBaseStats"),
            .array(name: "evolutions", count: 5, of: .subStruct(name: "PokemonEvolution")),
            .array(name: "level_up_moves", count: 20, of: .subStruct(name: "PokemonLevelUpMove")),
            .padding(length: 2),
            .subStruct(name: "sprites", typeName: "PokemonSprite"),
            .subStruct(name: "shiny_sprites", typeName: "PokemonSprite"),
        ],
        description: "A species record in Colosseum's layout (deoxys_pokemon_data, 0x11C bytes)"
    )

    /// `menu_se`: one sound set per menu (`menuSeBiosGetPtr` / `GetSndId`).
    static let menuSoundsStruct = StructMap(
        name: "MenuSounds",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "open_sound", description: "Event 4 (windowOpen)"),
            .uint16(name: "close_sound", description: "Event 5"),
            .uint16(name: "cursor_sound", description: "Event 1"),
            .uint16(name: "decide_sound", description: "Event 2"),
            .uint16(name: "cancel_sound", description: "Event 3"),
            .uint16(name: "page_sound", description: "Event 6 (L/R page change)"),
        ],
        description: "A menu's sound effects (menu_se, 0xC bytes)"
    )

    /// `message_se`: searched by key, not indexed (`_msgMainSub`, `GSmsgKill`)
    /// — keys must stay unique.
    static let messageSoundStruct = StructMap(
        name: "MessageSound",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "message_se_type", description: "The key a message window looks its sound up by"),
            .uint16(name: "sound_id"),
        ],
        description: "A message window's sound (message_se, 4 bytes)"
    )

    /// The debug sound test's lists (`dbgMenuSoundTest*`).
    static let soundTestEntryStruct = StructMap(
        name: "SoundTestEntry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "sound_id"),
        ],
        description: "A sound-test entry (2 bytes)"
    )

    /// `table_res`: the resources `tableResBiosGetResPtr` hands out by slot —
    /// the font list, the message tables and the script. JP fills only
    /// slots 1, 3 and 7.
    static let tableResEntryStruct = StructMap(
        name: "TableResEntry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .label(name: "resource", description: "Empty for an unused slot"),
        ],
        description: "A table-resource slot (table_res, 4 bytes)"
    )

    /// `floorsoundTbl`: which BGM / ambient sound a room plays (`floorSound_*`).
    /// Searched by room, not indexed; a room can have several flag-gated rows.
    static let roomSoundStruct = StructMap(
        name: "RoomSound",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "env_timing", description: "floorSound_playEnvSound plays a row only when this matches its argument (1 at floor init); 1 on every row"),
            .uint8(name: "volume"),
            .uint16(name: "room_id", description: "The room this row applies to (compared with floorGetCurrent)"),
            .uint16(name: "sound_id", description: "Index into SoundsMetaData"),
            .uint16(name: "fade_in_time"),
            .uint16(name: "env_fade_out_time", description: "Ambient sounds only; the BGM path uses a fixed fade"),
            .uint16(name: "flag_id", description: "The row plays only while this GeneralFlags flag is set; 0 always plays"),
        ],
        description: "A room's background sound (floorsoundTbl, 0xC bytes)"
    )

    static let ribbonStruct = StructMap(
        name: "Ribbon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "unknown_0x00", description: "Unread; a sequential id, 3 higher on PAL and JP"),
            .uint16(name: "unknown_0x02", description: "0; unread"),
            .uint32(name: "description_msg_id", description: "getRibbonMsgID; 0 for the event ribbons, which the status screen takes from ExRibbon"),
        ],
        description: "A ribbon (ribbon_data, 8 bytes)"
    )

    /// `relivehall_data`: the Purification Chamber's settings — one record.
    static let purificationChamberSettingsStruct = StructMap(
        name: "PurificationChamberSettings",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "offscreen_alpha", description: "renderOffscreenData"),
            .uint8(name: "unknown_0x01", description: "0; unread"),
            .uint16(name: "steps_per_purification", description: "heroWalkReliveCallBack: every this many steps a Shadow Pokémon in a set loses the set's flow from its heart gauge"),
            .uint16(name: "pokemon_scale_percent", description: "Hologram Pokémon scale (modelPokemonSetScale)"),
            .array(name: "stage_part_indices", count: 0x44, of: .uint8, description: "Model part and material indices stageAllModelLoad looks up through two DOL tables"),
            .padding(length: 2),
        ],
        description: "Purification Chamber settings (relivehall_data, 0x4C bytes)"
    )

    /// `tutorialdata`: the Battle CDs offered by the tutorial menu
    /// (`menuScriptTutorial*`). The last row is CANCEL whatever its value.
    static let tutorialEntryStruct = StructMap(
        name: "TutorialEntry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "battle_cd_id", description: "Row of BattleCDs; 0 on the final, CANCEL row"),
        ],
        description: "A tutorial menu entry (tutorialdata, 2 bytes)"
    )

    // Colosseum's flag tables, carried over unused: XD's 6-byte flag
    // descriptor dropped the index bytes that pointed into them, and nothing
    // in XD reads them. Their roles are Colosseum's.

    static let flagItemStruct = StructMap(
        name: "FlagItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "unknown_0x00", description: "Unread in XD. Colosseum: an item id its debug flag routine grants"),
            .uint16(name: "unknown_0x02", description: "Unread in XD. Colosseum: an item id (item-grant path)"),
        ],
        description: "Unused in XD (flag_item, 4 bytes)"
    )

    static let flagPartyStruct = StructMap(
        name: "FlagParty",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_0x00", description: "Unread in XD. Colosseum: enables party member 0"),
            .uint8(name: "unknown_0x01", description: "Unread in XD. Colosseum: enables party member 1"),
        ],
        description: "Unused in XD (flag_party, 2 bytes)"
    )

    static let flagValueStruct = StructMap(
        name: "FlagValue",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "unknown_0x00", description: "Unread in XD. Colosseum: the value its debug routine writes into a flag"),
        ],
        description: "Unused in XD (flag_value, 4 bytes)"
    )
}
