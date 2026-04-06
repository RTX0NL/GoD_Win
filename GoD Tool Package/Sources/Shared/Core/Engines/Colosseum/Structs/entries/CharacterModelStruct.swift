import Structs
import GoDFoundation

public enum ColosseumStructDefaults {}

/// Colosseum character model entry (0x2C / 44 bytes).
/// Different layout from XD: no neck/chest bone IDs, no interaction radius,
/// unknown bytes instead of bone indices, unknown IDs array before model ID.
public extension ColosseumStructDefaults {

    static let characterModelStruct = StructMap(
        name: "CharacterModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // Offset 0x00: Flags bitfield (same bit layout as XD)
            .uint8(name: "flags"),
            // Offset 0x01-0x03: Unknown bytes (XD has neck/chest bone here)
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint8(name: "unknown_3"),
            // Offset 0x04-0x09: Unknown IDs (6 bytes)
            .array(name: "unknown_ids", count: 6, of: .uint8),
            // Offset 0x0A: Padding
            .padding(length: 2),
            // Offset 0x0C: FSYS resource ID for .dat model file in people_archive.fsys
            .uint32(name: "model_resource_id"),
            // Offset 0x10: Walk animation cycle length
            .float(name: "walk_length"),
            // Offset 0x14: Run animation cycle length
            .float(name: "run_length"),
            // Offset 0x18: Collision bounding sphere radius
            .float(name: "collision_radius"),
            // Offset 0x1C: Neck left rotation limit
            .float(name: "neck_left_limit"),
            // Offset 0x20: Neck right rotation limit
            .float(name: "neck_right_limit"),
            // Offset 0x24: Neck up rotation limit
            .float(name: "neck_up_limit"),
            // Offset 0x28: Neck down rotation limit
            .float(name: "neck_down_limit"),
            // No interaction radius in Colosseum (total: 0x2C)
        ],
        description: "Colosseum overworld character model metadata (0x2C bytes). Differs from XD: no bone IDs, no interaction radius."
    )
}
