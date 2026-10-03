import Structs
import GoDFoundation

/// Struct definitions for the floor tables in XD's map RELs.
///
/// Named after the game's own registration globals (`floorCharTbl_<map>`,
/// `floor_pos_list_<map>`, `floor_resource_data_<map>`). Field names come from
/// the game's accessors — `floorCharacterBios*` for characters,
/// `floorDataBios*` for positions and the resource record — and every field
/// was checked against every row of every map on the US, PAL and JP discs.
/// A field nothing in the game reads stays `unknown_*`, so a CSV round-trips
/// exactly. The legacy tool's "group id" at resource +8 was the top half of
/// the first shadow-receive resource id.
public extension XDStructDefaults {

    /// One NPC or object placed in a map. Shared with Colosseum byte for byte.
    static let floorCharacterStruct = StructMap(
        name: "FloorCharacter",
        wordSize: 4,
        alignmentStyle: .none,
        properties: floorCharacterProperties,
        description: "A character placed in a map (floorCharTbl, 0x24 bytes)"
    )

    /// A point the player can enter the map at. Shared with Colosseum.
    static let floorPositionStruct = StructMap(
        name: "FloorPosition",
        wordSize: 4,
        alignmentStyle: .none,
        properties: floorPositionProperties,
        description: "An entry point into a map (floor_pos_list, 0x10 bytes)"
    )

    static let floorRenderDataStruct = StructMap(
        name: "FloorRenderData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: floorRenderDataProperties(trailingWords: 2),
        description: "A map's lighting, shadow and fog setup (floor_resource_data, 0x48 bytes)"
    )

    /// The leftover Colosseum-format maps' resource record: Colosseum's
    /// render record — sun, shadow light and eight shadow receivers — and
    /// nothing after.
    static let floorRenderDataColosseumFormatStruct = StructMap(
        name: "FloorRenderDataColosseumFormat",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "sun_res_id"),
            .uint32(name: "shadow_light_id"),
            .array(name: "shadow_receive_ids", count: 8, of: .uint32),
        ],
        description: "A leftover Colosseum-format map's render setup (0x28 bytes)"
    )

    /// The prototype maps' resource record — `TEST000`–`004`, `B1_2/3/6`,
    /// `tv_test`, `waza_viewer`, and on JP also `B1_1` and `peopleViewer001` —
    /// is one word longer.
    static let floorRenderData4CStruct = StructMap(
        name: "FloorRenderData4C",
        wordSize: 4,
        alignmentStyle: .none,
        properties: floorRenderDataProperties(trailingWords: 3),
        description: "A prototype map's render setup (floor_resource_data, 0x4C bytes)"
    )

    static var floorCharacterProperties: [StructMap.Property] {
        [
            // Colosseum packs these same two bytes differently (see its
            // own `FloorCharacter`), which is what the legacy tool got
            // wrong by reading both with XD's layout.
            .bits(name: "flags", description: "What the character is and how it reacts", fields: [
                .flag(name: "visible", bit: 0, description: "floorCharacterBiosGetVisibility → peopleSetDisp"),
                .flag(name: "placed_on_load", bit: 1, description: "Placed when the floor loads; otherwise a script places it (GetLoadInit)"),
                .flag(name: "has_collision", bit: 2, description: "GetIsHit → peopleSetCollision"),
                .flag(name: "head_follows_player", bit: 3, description: "peopleMoveNeckTargetHero"),
                .flag(name: "talk_through_walls", bit: 4, description: "GetTalkWallThrough"),
                .flag(name: "animation_blending", bit: 5, description: "GSmodelEnableAnimBlend"),
                .number(name: "unknown_6_7", bits: 6...7, description: "Read by nothing"),
            ]),
            .bits(name: "behavior", description: "How the character moves, and how it reacts to being talked to", fields: [
                .number(name: "move_type", bits: 0...2, description: "GetMoveType: 0 stands, 2 random walk, 3 random rotation; 1 and 4 start nothing when placed"),
                .number(name: "talk_start", bits: 3...4, description: "GetTalkStartType: 0 doesn't react, 1 turns its head toward the player, 2 turns its whole body, 3 can't be talked to"),
                .number(name: "talk_end", bits: 5...6, description: "GetTalkEndType: 0 keeps facing the player, 1 turns back to its original facing. Only matters with talk start 2; a head turn always relaxes"),
                .number(name: "unknown_7", bits: 7...7, description: "Read by nothing"),
            ]),
            .uint8(name: "unknown_0x02", description: "Read by nothing; 0 on every XD character"),
            .uint8(name: "animation_id", description: "Starting animation (setAnimIndex in peopleSetInfo); 3 on most characters, and any other value also marks the character as animated"),
            .int16(name: "angle", description: "Facing in degrees (GetRot)"),
            .uint16(name: "people_info_id", description: "Index into common.rel's character models — the people info that picks the model (GetPeopleInfoPtr)"),
            .uint16(name: "name_id", description: "Index into common.rel's PeopleIDs, which names the character (GetNameID)"),
            .uint16(name: "unknown_0x0A", description: "Padding: the game's own record copy skips it. 0 on every character"),
            .uint32(name: "unknown_0x0C", description: "Read by nothing; 1 on every map character, 0 for the three built-in ones"),
            .uint32(name: "move_script_function", description: "Script function run continuously (GetMoveSctID → peopleExecMoveScript); 0 for none. On disc it is 0x01000000 + the function's index in the map's script"),
            .uint32(name: "talk_script_function", description: "Script function run when the character is talked to (GetTalkSctID); 0 for none, same encoding"),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
        ]
    }

    static var floorPositionProperties: [StructMap.Property] {
        [
            .int16(name: "angle", description: "Facing in degrees on arrival (floorDataBiosGetPosListData)"),
            .uint16(name: "unknown_0x02", description: "Padding: read by nothing, 0 on every entry point"),
            .float(name: "x"),
            .float(name: "y"),
            .float(name: "z"),
        ]
    }

    /// The render setup a room points at (room +0x08 → this record), as the
    /// `floorDataBios` getters read it.
    private static func floorRenderDataProperties(trailingWords: Int) -> [StructMap.Property] {
        [
            .uint32(name: "sun_res_id", description: "floorDataBiosGetSunResID"),
            .uint32(name: "shadow_light_id", description: "floorDataBiosGetShadowLightID"),
            .array(name: "shadow_receive_ids", count: 8, of: .uint32, description: "Resource ids of the models that receive shadows (GetShadowReciveID/Num; 0 ends the list)"),
            .array(name: "secondary_render_ids", count: 3, of: .uint32, description: "GetSecondaryRenderID/Num; 0 ends the list"),
            .array(name: "fog_exempt_model_ids", count: 3, of: .uint32, description: "Models drawn without the map's fog (floorDataBiosModelIDGetFogState)"),
            .array(name: "unknown_0x40", count: trailingWords, of: .uint32, description: "Read by nothing found"),
        ]
    }

    /// A field camera: while the player is inside its area, the camera sits
    /// at this distance, height and angle. Read by `floorFieldCamera`
    /// (`_floorFieldCameraCalculatePathParams`/`…BlendParams`,
    /// `_floorFieldCameraDetectMode`, `_floorFieldCameraSetParams`).
    static let floorFieldCameraStruct = StructMap(
        name: "FloorFieldCamera",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "area_shape", typeName: "CameraAreaShape", description: "0: a circle of radius area_size around the centre. Otherwise a box area_size wide and area_size × area_depth_ratio deep, rotated by area_rotation"),
            .padding(length: 3),
            .float(name: "center_x"),
            .float(name: "center_y", description: "Not used by the area test, which is flat"),
            .float(name: "center_z"),
            .float(name: "distance", description: "Camera distance (cameraSetDistance)"),
            .float(name: "height", description: "Camera height (cameraSetHeight)"),
            .float(name: "rotation_y", description: "Camera yaw in radians (cameraSetRotY)"),
            .float(name: "area_size", description: "Circle radius, or the box's half-width"),
            .float(name: "area_depth_ratio", description: "Box only: half-depth = area_size × this"),
            .float(name: "area_rotation", description: "Box only: rotation in radians"),
            .float(name: "transition_easing", description: "Exponent of the ease curve when blending into this camera"),
            .float(name: "transition_time", description: "Seconds to blend into this camera. A negative value on any camera keeps the floor in path mode"),
            .float(name: "fov", description: "Field of view in degrees (cameraSetFov)"),
        ],
        description: "A field camera and the area it applies in (floor_field_camera_list, 0x34 bytes)"
    )

    /// Something rendered into a texture that replaces a map model's texture —
    /// a TV screen, a monitor. Read by `floorSetOffscreenIndex`.
    static let floorOffscreenDataStruct = StructMap(
        name: "FloorOffscreenData",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "source_kind", typeName: "OffscreenSource", description: "0: an animated model (floorOpenModel). Otherwise a movie (GSmoviePlay)"),
            .uint8(name: "animation", description: "Model: its animation index. Movie: non-zero loops it"),
            .uint16(name: "id", description: "What floorSetOffscreenIndex selects this entry by"),
            .uint16(name: "texture_width"),
            .uint16(name: "texture_height"),
            .uint32(name: "target_model_res_id", description: "Model whose texture is replaced (GSmodelSetTextureChange)"),
            .uint32(name: "source_res_id", description: "The model or movie rendered into the texture"),
            .uint32(name: "held_res_id", description: "A resource fetched and held while the entry is active; nothing else reads it"),
        ],
        description: "A model or movie rendered into a map texture (floor_offscreen_data_list, 0x14 bytes)"
    )

    /// One entry of a berry list (`kinomiData`, carried only by M3_out). No
    /// reader was found; the item is unambiguous (every value is a berry),
    /// the weight is inferred from its values (83–333).
    static let floorBerryStruct = StructMap(
        name: "FloorBerry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "item", typeName: "Items"),
            .uint16(name: "weight", description: "Inferred: a relative chance"),
        ],
        description: "A berry and its weight (kinomiData, 4 bytes)"
    )
}
