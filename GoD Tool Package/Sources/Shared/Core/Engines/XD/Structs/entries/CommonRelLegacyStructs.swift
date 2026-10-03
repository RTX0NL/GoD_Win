import Structs
import GoDFoundation

/// `common.rel` tables the legacy GoD tool declared, re-derived from the
/// game's readers: `bingo_bios` (BattleBingo), `deckDataVirtualDB_*`
/// (BattleCDs), the `undertaker` module (MirorBData), `flag_etc`
/// (StoryProgressFlags) and `WorldMap::SearchData` (WorldMapLocations).
/// Reference: `Documentation/File Formats/XD/common.rel Tables.md`.
public extension XDStructDefaults {

    static let battleBingoPokemonStruct = StructMap(
        name: "BattleBingoPokemon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "type_slot", description: "Which of the species' two types the panel shows (getPanelType)"),
            .boolean(name: "ability_slot", description: "pokemonSetTokuseiFlag: the second ability when set"),
            .abstraction(name: "nature", typeName: "Nature"),
            .abstraction(name: "gender", typeName: "Gender"),
            .abstraction(name: "species", typeName: "PokemonSpecies"),
            .abstraction(name: "move", typeName: "Moves", description: "Its only move"),
            .uint16(name: "ev_bonus", description: "Bits 15-12 the EV stat (1-6, HP…Speed), bits 7-0 the amount; bits 11-8 ignored; 0 none"),
        ],
        description: "A Battle Bingo panel (0xA bytes)"
    )

    static let battleBingoMysteryPanelStruct = StructMap(
        name: "BattleBingoMysteryPanel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "kind", typeName: "BattleBingoMysteryPanelKind"),
            .uint8(name: "grid_position", description: "Cell of the 4x4 board, 0-15"),
        ],
        description: "A Battle Bingo mystery panel (2 bytes)"
    )

    /// `bingo_data`. The menu prints a card's name and description from its
    /// own copy in the DOL, not from these ids.
    static let battleBingoStruct = StructMap(
        name: "BattleBingo",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "card_number", description: "getNo: 1-11; its clear state and DOL text are keyed by it"),
            .uint8(name: "difficulty", description: "Unread; 0-3"),
            .uint8(name: "index_in_difficulty", description: "Unread"),
            .uint8(name: "pokemon_level", description: "getLevel: every panel's level"),
            .uint8(name: "unknown_0x04", description: "Unread; 2 on every card"),
            .uint8(name: "master_ball_count", description: "getBall: Master Balls the card starts with"),
            .uint8(name: "pokemon_count", description: "Unread (the code assumes 14)"),
            .uint8(name: "mystery_panel_count", description: "Unread (the code assumes 3)"),
            .uint32(name: "name_id", description: "Unread"),
            .uint32(name: "description_id", description: "Unread"),
            .array(name: "score", count: 10, of: .uint16, description: "getScore: coupons per number of lines"),
            .array(name: "pokemon", count: 14, of: .subStruct(name: "BattleBingoPokemon"), description: "Panel 1 is the player's starter"),
            .array(name: "mystery_panels", count: 3, of: .subStruct(name: "BattleBingoMysteryPanel")),
            .padding(length: 2),
        ],
        description: "A Battle Bingo card (bingo_data, 0xB8 bytes)"
    )

    static let battleCDItemStruct = StructMap(
        name: "BattleCDItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "quantity"),
            .padding(length: 1),
            .uint16(name: "item_data_id", description: "Item data id lent to the player (heroItemAddItemDataId); 0 an empty slot"),
        ],
        description: "An item a Battle CD lends (4 bytes)"
    )

    /// `deckdata_virtual`. A Battles row reaches it through its Battle CD
    /// index (Battles +0x08).
    static let battleCDStruct = StructMap(
        name: "BattleCD",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "unknown_0x00", description: "Unread; 0x00, 0x40 or 0x80"),
            .uint8(name: "turn_limit", description: "0 none"),
            .abstraction(name: "battle_style", typeName: "BattleStyle"),
            .padding(length: 1),
            .uint16(name: "battle_field_index", description: "A BattleFields row replacing the battle's own; 0 keeps it"),
            .padding(length: 2),
            .abstraction(name: "player_deck", typeName: "Deck"),
            .uint16(name: "player_trainer_id"),
            .abstraction(name: "opponent_deck", typeName: "Deck"),
            .uint16(name: "opponent_trainer_id"),
            .uint32(name: "name_id"),
            .uint32(name: "description1_id"),
            .uint32(name: "description2_id"),
            .uint32(name: "clear_flag", description: "GeneralFlags id set when the CD is cleared"),
            .array(name: "player_status", count: 6, of: .enumeration(name: "StatusCondition"), description: "Status condition each party slot starts with"),
            .array(name: "opponent_status", count: 6, of: .enumeration(name: "StatusCondition")),
            .array(name: "items", count: 4, of: .subStruct(name: "BattleCDItem")),
        ],
        description: "A Battle CD (deckdata_virtual, 0x3C bytes)"
    )

    static let mirorBPlaceStruct = StructMap(
        name: "MirorBPlace",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "weight", description: "Chance of this place, out of the seven weights' sum"),
            .uint16(name: "room_id"),
            .uint32(name: "name_id", description: "What the radar calls the place"),
        ],
        description: "A place Miror B can appear (8 bytes). Rows are also special-cased by position"
    )

    /// `undertakerdata`: Miror B's radar. The flags are GeneralFlags ids used
    /// as counters.
    static let mirorBStruct = StructMap(
        name: "MirorB",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "steps_per_check", description: "Steps between rolls of the radar signal"),
            .uint16(name: "signal_up_chance", description: "Out of chance_range"),
            .uint16(name: "signal_down_chance", description: "Out of chance_range, after the up chance"),
            .uint16(name: "chance_range"),
            .uint16(name: "signal_max", description: "He appears once the signal reaches this minus 1"),
            .uint16(name: "stay_steps", description: "Steps he stays before leaving"),
            .uint32(name: "start_flag", description: "The radar runs only while set"),
            .uint32(name: "step_counter_flag"),
            .uint32(name: "signal_flag"),
            .uint32(name: "place_flag", description: "The room he's in; 0 absent"),
            .uint32(name: "stay_counter_flag"),
            .uint32(name: "end_flag", description: "Set turns the radar off for good"),
            .uint32(name: "radar_display_flag"),
            .uint32(name: "pause_start_story_index", description: "StoryProgressFlags row: between these two checkpoints he doesn't appear"),
            .uint32(name: "pause_end_story_index"),
            .uint32(name: "random_bit_flag", description: "Set to a random bit whenever he appears"),
            .array(name: "places", count: 7, of: .subStruct(name: "MirorBPlace")),
        ],
        description: "Miror B's radar settings (undertakerdata, 0x6C bytes)"
    )

    /// `flag_etc`: story checkpoints. The debug menu warps to one; the game
    /// compares its story_progress with flag 0x3C4 at fixed rows, so row
    /// order matters.
    static let storyCheckpointStruct = StructMap(
        name: "StoryCheckpoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "follower", typeName: "Follower", description: "heroSetFollowerWithID"),
            .padding(length: 1),
            .uint16(name: "room_id", description: "0 stays on the current floor"),
            .uint16(name: "money"),
            .padding(length: 2),
            .uint32(name: "story_progress", description: "The value of story flag 0x3C4 at this point"),
            .uint32(name: "script_function", description: "Common-script function run on warping; 0 none"),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
            .uint32(name: "name_id", description: "Debug menu label"),
        ],
        description: "A story checkpoint (flag_etc, 0x20 bytes)"
    )

    /// `worldmapXD_data`. Fixed rows are read by position, so order matters.
    static let worldMapLocationStruct = StructMap(
        name: "WorldMapLocation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int16(name: "camera_id"),
            .uint16(name: "npc_id", description: "Character named in the info panel; 0 none"),
            .uint32(name: "unlock_flag", description: "0 always available"),
            .uint32(name: "menu_item_id", description: "World-map menu item enabled when unlocked"),
            .uint32(name: "model_id"),
            .uint32(name: "snap_texture_id", description: "Low half: the preview sprite"),
            .uint32(name: "move_demo_model_id"),
            .uint32(name: "name_id", description: "Unread"),
            .uint32(name: "room_id", description: "The floor travelled to"),
            .uint32(name: "info_msg_id"),
        ],
        description: "A world-map location (worldmapXD_data, 0x24 bytes)"
    )
}
