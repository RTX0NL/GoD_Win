import Structs
import GoDFoundation

/// Struct definitions for the overworld character model metadata table in common.rel.
/// Field layout confirmed by disassembly of peopleInfoBios* accessor functions.
public extension XDStructDefaults {

    /// XD character model entry (0x34 / 52 bytes).
    /// Located in common.rel at CommonIndexes.CharacterModels (index 84).
    /// Count at CommonIndexes.NumberOfCharacterModels (index 85).
    static let characterModelStruct = StructMap(
        name: "CharacterModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // Offset 0x00: Flags bitfield
            // Bits 7:5 = talk sound effect type (3 bits, 0-7)
            // Bit 4    = bound check enabled (boolean)
            // Bits 3:2 = collision type (2 bits, 0-3)
            // Bit 1    = unknown flag
            // Bit 0    = unknown flag
            .uint8(name: "flags"),

            // Offset 0x01: Index of the neck bone in the model's skeleton.
            // Used for head-tracking (looking toward player/objects).
            .uint8(name: "neck_bone_index"),

            // Offset 0x02: Index of the chest bone in the model's skeleton.
            .uint8(name: "chest_bone_index"),

            // Offset 0x03: Padding
            .padding(length: 1),

            // Offset 0x04: FSYS resource ID for the .dat model file in people_archive.fsys.
            .uint32(name: "model_resource_id"),

            // Offset 0x08: Walk animation cycle length (possibly distance per cycle, not frame count).
            .float(name: "walk_length"),

            // Offset 0x0C: Run animation cycle length.
            .float(name: "run_length"),

            // Offset 0x10: Collision bounding sphere radius.
            .float(name: "collision_radius"),

            // Offset 0x14: Maximum leftward neck rotation (radians).
            .float(name: "neck_left_limit"),

            // Offset 0x18: Maximum rightward neck rotation (radians).
            .float(name: "neck_right_limit"),

            // Offset 0x1C: Maximum upward neck rotation (radians).
            .float(name: "neck_up_limit"),

            // Offset 0x20: Maximum downward neck rotation (radians).
            .float(name: "neck_down_limit"),

            // Offset 0x24: Interaction/talk trigger distance.
            .float(name: "talk_distance"),

            // Offset 0x28: Unknown — copied as floats by collision code.
            .float(name: "unknown_float_1"),
            .float(name: "unknown_float_2"),

            // Offset 0x30: Unknown halfwords — accessed by GScolsys2Hit/GScolsys2Thru collision code.
            .uint16(name: "unknown_id_1"),
            .uint16(name: "unknown_id_2"),
        ],
        description: "Overworld character model metadata. Each model's collision, bone tracking, animation, and interaction properties. Confirmed by peopleInfoBios* disassembly."
    )
}
