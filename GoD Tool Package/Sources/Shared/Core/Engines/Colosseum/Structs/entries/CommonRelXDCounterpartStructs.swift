import Structs
import GoDFoundation

/// Colosseum `common.rel` tables whose XD counterparts are typed: the same
/// record size, the same count word and the same value patterns on all three
/// discs. Where Colosseum's layout differs (contest effects, story
/// checkpoints, the 8-byte flag descriptor) the difference is in the data and
/// noted per field. The flag tables are where Colosseum is the *better*
/// evidence — its flag code reads them through the descriptor's index bytes,
/// where XD's only carries them. Reference:
/// `Documentation/File Formats/Colosseum/common.rel Tables.md`.
public extension ColosseumStructDefaults {

    /// The flag descriptor table (3593 × 8). XD's is 6 bytes; Colosseum's
    /// carries three index bytes into the tables below that XD dropped.
    static let generalFlagStruct = StructMap(
        name: "GeneralFlag",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "bankAndBitLength", description: "bits 6-7 bank, bits 0-5 bit length"),
            .uint8(name: "valueIndex", description: "Row of FlagValues the debug set-flag routine writes"),
            .uint8(name: "itemIndex", description: "Row of FlagItemData the debug set-flag routine grants"),
            .uint8(name: "storyCheckpointIndex", description: "Row of StoryProgressFlags the debug set-flag routine applies"),
            .uint16(name: "bitPosition", description: "computed at boot; 0 on disc"),
            .int16(name: "nextFlagID", description: "next flag in the debug chain, -1 ends"),
        ],
        description: "GeneralFlags entry: Colosseum's flag descriptor (8 bytes)"
    )

    static let flagItemStruct = StructMap(
        name: "FlagItem",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "item_1", typeName: "Items", description: "Granted by the debug set-flag routine (second call)"),
            .abstraction(name: "item_2", typeName: "Items", description: "Granted by the debug set-flag routine (first call)"),
        ],
        description: "Items a flag grants in the debug set-flag routine (flag_item, 4 bytes)"
    )

    static let flagPartyStruct = StructMap(
        name: "FlagParty",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .boolean(name: "member_1_enabled"),
            .boolean(name: "member_2_enabled"),
        ],
        description: "Which party members a story checkpoint enables (flag_party, 2 bytes)"
    )

    static let flagValueStruct = StructMap(
        name: "FlagValue",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "value", description: "Written into the flag, clamped to its width"),
        ],
        description: "A value the debug set-flag routine writes (flag_value, 4 bytes)"
    )

    /// `flag_etc`. Shorter than XD's 0x20: no story-progress or script word.
    static let storyCheckpointStruct = StructMap(
        name: "StoryCheckpoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "party_index", description: "Row of FlagPartyData"),
            .padding(length: 1),
            .uint16(name: "room_id", description: "0 stays on the current floor"),
            .uint16(name: "money"),
            .padding(length: 2),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
            .uint32(name: "name_id", description: "Debug menu label"),
        ],
        description: "A story checkpoint (flag_etc, 0x18 bytes)"
    )

    static let battleSideStruct = StructMap(
        name: "BattleSide",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "yrot", description: "Which way the side faces (XD: fightSideDataBiosGetYrot)"),
            .uint16(name: "unknown_0x02", description: "0 everywhere"),
            .array(name: "trainer_status_menu_ids", count: 2, of: .uint32),
            .array(name: "pokemon_status_menu_ids", count: 2, of: .uint32),
        ],
        description: "A battle side's layout (fight_side_data, 0x14 bytes; XD's layout and pattern)"
    )

    static let heartGaugeChangeStruct = StructMap(
        name: "HeartGaugeChange",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int8(name: "change", description: "XD rows: battle, walk, Call, daycare, cologne, other"),
        ],
        description: "A base heart-gauge change (pokemon_dp_filter_data, 1 byte; XD's values)"
    )

    /// `contest_data`. XD zeroes +6; Colosseum stores each effect's
    /// description message there.
    static let contestEffectStruct = StructMap(
        name: "ContestEffect",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "appeal"),
            .uint8(name: "jam"),
            .padding(length: 4),
            .uint16(name: "description_msg_id", description: "Data: sequential message ids from row 1; 0 on row 0"),
        ],
        description: "A contest effect (contest_data, 8 bytes)"
    )

    static let tableResEntryStruct = StructMap(
        name: "TableResEntry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .label(name: "resource", description: "An embedded font, string table or script"),
        ],
        description: "A table-resource slot (table_res, 4 bytes)"
    )
}
