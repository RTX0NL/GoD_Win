import Structs
import GoDFoundation

public enum ColosseumStructDefaults {}

/// Colosseum overworld character model entry — **0x2C / 44 bytes**.
///
/// The stride is the `CharacterModels` chunk (6600 bytes) divided by the
/// REL's `NumberOfCharacterModels` word (150), identical on the US, PAL and
/// JP discs. An earlier derivation put it at 0xDC from a `mulli … 0xDC` in
/// `zz_018fd88_`; that routine indexes something else, and a 0xDC stride
/// leaves 120 of the 150 rows outside the chunk.
///
/// The layout differs from XD's 0x34-byte record in its head: three
/// unknown bytes and six signed bone/animation indices (-1 when unset) come
/// before the model id, which sits at 0x0C rather than 0x04. The float
/// block that follows matches the offsets the Colosseum accessors read —
/// `peopleInfoBiosGetColBallSize` loads 0x10, `peopleInfoBiosGetNeckUpLimit`
/// and `…NeckDownLimit` load 0x1C and 0x20 — and the remaining four floats
/// are named by value only (13, 4, -30 and 50 on a typical row).
public extension ColosseumStructDefaults {

    static let characterModelStruct = StructMap(
        name: "CharacterModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Flags bitfield, same bit layout as XD where an accessor
            // reads it: bits 7:5 talk sound-effect type (peopleInfoBiosGetTalkSe),
            // bits 3:2 collision type (peopleInfoBiosGetColType).
            .uint8(name: "flags"),
            .uint8(name: "unknown_1"),
            .uint8(name: "unknown_2"),
            .uint8(name: "unknown_3"),
            // 0x04: Six signed indices, -1 when unset. The legacy tool read
            // them as animation indices for predefined animation types.
            .array(name: "unknown_indices", count: 6, of: .int8),
            .padding(length: 2),
            // 0x0C: File identifier of the .dat model in people_archive.fsys.
            .uint32(name: "model_resource_id"),
            // 0x10: Collision bounding-sphere radius (peopleInfoBiosGetColBallSize).
            .float(name: "collision_radius"),
            .float(name: "unknown_float_1"),
            .float(name: "unknown_float_2"),
            // 0x1C / 0x20: Neck rotation limits (peopleInfoBiosGetNeckUpLimit /
            // …DownLimit, each scaled by a global gaze constant on read).
            .float(name: "neck_up_limit"),
            .float(name: "neck_down_limit"),
            .float(name: "unknown_float_3"),
            .float(name: "unknown_float_4"),
        ],
        description: "Overworld character model metadata (0x2C bytes per entry; 150 on every disc)"
    )
}
