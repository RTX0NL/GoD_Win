import Structs
import GoDFoundation

/// Struct definitions for the floor tables in Colosseum's map RELs.
///
/// What each table *is* comes from `common.rel`'s `Rooms`: a room record
/// points at the DOL globals a map registers its render, character, warp,
/// camera and offscreen data into. Field layouts are the legacy GoD tool's
/// (`XGCharacter`, `XGMapEntryLocation`), which it used for both games, and
/// are identical to XD's — checked against every row on the US, PAL and JP
/// discs: 2,379 characters and 978 entry points. Bytes the legacy tool never
/// named are `unknown_*` fields so a CSV round-trips exactly.
///
/// Colosseum's map names none of the camera or offscreen routines and no
/// reader of them was located, so those two records are typed by matching
/// them to XD's: each field's description says whether it is confirmed, a
/// match to XD by position and value range, or unknown.
public extension ColosseumStructDefaults {

    /// Same size and fields as XD's, but the two flag bytes are packed
    /// differently. The getters are unnamed in Colosseum's map; they were found
    /// through its character-init and talk-check routines, which mirror XD's
    /// step for step. Colosseum has no load-init bit, so collision,
    /// head-follow and wall-through each sit one bit higher than XD's (6, 5,
    /// 4); the move type is byte 0's low three bits rather than byte 1's high
    /// three; and both talk types are byte 1's top four bits. The legacy tool
    /// read both games with XD's layout, so its Colosseum movement values were
    /// wrong.
    static let floorCharacterStruct = StructMap(
        name: "FloorCharacter",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .bits(name: "flags", description: "What the character is, how it reacts, and how it moves", fields: [
                .flag(name: "visible", bit: 0),
                .flag(name: "has_collision", bit: 1),
                .flag(name: "head_follows_player", bit: 2),
                .flag(name: "talk_through_walls", bit: 3),
                .flag(name: "unknown_4", bit: 4, description: "Unidentified; set on one character"),
                .number(name: "move_type", bits: 5...7, description: "0 stands, 2 random walk, 3 random rotation"),
            ]),
            .bits(name: "behavior", description: "How the character reacts to being talked to", fields: [
                .number(name: "talk_start", bits: 0...1, description: "0 doesn't react, 1 turns its head toward the player, 2 turns its whole body, 3 can't be talked to"),
                .number(name: "talk_end", bits: 2...3, description: "0 keeps facing the player, 1 turns back to its original facing"),
                .number(name: "unknown_4_7", bits: 4...7, description: "Read by nothing; 0 on disc"),
            ]),
            .uint8(name: "unknown_0x02", description: "0-4 on a handful of characters; no reader found"),
            .uint8(name: "unknown_0x03", description: "0 on every Colosseum character"),
            .int16(name: "angle", description: "Facing in degrees"),
            .uint16(name: "people_info_id", description: "Index into common.rel's character models — the people info that picks the model"),
            .uint16(name: "name_id", description: "Index into common.rel's PeopleIDs, which names the character"),
            .uint16(name: "unknown_0x0A", description: "Padding; 0 on every character"),
            .uint32(name: "unknown_0x0C", description: "1 on every character"),
            .uint32(name: "move_script_function", description: "Script function run continuously; 0 for none. On disc 0x01000000 + the function's index in the map's script"),
            .uint32(name: "talk_script_function", description: "Script function run when the character is talked to; 0 for none, same encoding"),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
        ],
        description: "A character placed in a map (0x24 bytes)"
    )

    static let floorEntryPointStruct = StructMap(
        name: "FloorEntryPoint",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .int16(name: "angle", description: "Facing in degrees on arrival"),
            .uint16(name: "unknown_0x02", description: "Padding; 0 on every entry point"),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
        ],
        description: "An entry point into a map — a warp lands the player here (0x10 bytes)"
    )

    /// The render setup a room points at (room `render_data_pointer` → this
    /// record): sun (+0), shadow light (+4) and eight shadow receivers, read
    /// by the routines that mirror XD's `floorDataBios` getters. XD's record
    /// starts the same way and continues.
    static let floorRenderDataStruct = StructMap(
        name: "FloorRenderData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "sun_res_id"),
            .uint32(name: "shadow_light_id"),
            .array(name: "shadow_receive_ids", count: 8, of: .uint32, description: "Resource ids of the models that receive shadows; 0 ends the list"),
        ],
        description: "A map's render setup (0x28 bytes)"
    )

    /// Six floats that line up, in order and value range, with XD's camera
    /// record from +0x04 to +0x18 — XD's record without the area, transition
    /// and field-of-view fields.
    static let floorFieldCameraStruct = StructMap(
        name: "FloorFieldCamera",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .float(name: "center_x", description: "Matched to XD by position"),
            .float(name: "center_y", description: "Matched to XD by position"),
            .float(name: "center_z", description: "Matched to XD by position"),
            .float(name: "distance", description: "Matched to XD; 100-141 on disc"),
            .float(name: "height", description: "Matched to XD; 24-97 on disc"),
            .float(name: "rotation_y", description: "Matched to XD; mostly 0"),
        ],
        description: "A field camera (0x18 bytes)"
    )

    static let floorOffscreenDataStruct = StructMap(
        name: "FloorOffscreenData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "texture_width", description: "256 on every entry, like XD's 256×256 offscreen textures"),
            .uint16(name: "texture_height", description: "256 on every entry"),
            .uint32(name: "id", description: "Matched to XD's entry id: small, distinct per map"),
            .uint32(name: "unknown_res_id_0x08", description: "A resource id; role not confirmed"),
            .uint32(name: "unknown_res_id_0x0C", description: "A resource id; role not confirmed"),
            .uint32(name: "unknown_0x10", description: "0-3 on disc"),
            .uint32(name: "unknown_res_id_0x14", description: "A resource id; role not confirmed"),
        ],
        description: "A model or movie rendered into a map texture (0x18 bytes)"
    )

    static let floorBerryStruct = StructMap(
        name: "FloorBerry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "item", typeName: "Items"),
            .uint16(name: "weight", description: "Inferred: a relative chance"),
        ],
        description: "A berry and its weight (4 bytes)"
    )
}
