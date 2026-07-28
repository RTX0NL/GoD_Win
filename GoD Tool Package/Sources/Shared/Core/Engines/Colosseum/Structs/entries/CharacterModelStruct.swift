import Structs
import GoDFoundation

public enum ColosseumStructDefaults {}

/// Colosseum overworld character model entry — **0xDC / 220 bytes**.
///
/// Layout re-derived from the Colosseum disassembly (`peopleInfoBios*`
/// accessors, `peopleSearchID`, and the index accessor `zz_018fd88_`, whose
/// `mulli r3, 0xDC` fixes the stride). The shared 0x00–0x27 header is
/// byte-for-byte identical to XD at every offset a Colosseum accessor reads
/// (flags @0x00, model resource id @0x04, collision radius @0x10, neck
/// up/down @0x1C/0x20); Colosseum then appends a large engine-specific tail
/// (0x28–0xDB, 180 bytes) that XD (0x34 stride) does not have.
///
/// Confidence per field is noted inline:
///   * CONFIRMED — an offset a Colosseum accessor demonstrably loads.
///   * INFERRED  — same offset as the XD struct but no dedicated Colosseum
///                 accessor was found; named by XD analogy.
public extension ColosseumStructDefaults {

    static let characterModelStruct = StructMap(
        name: "CharacterModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Flags bitfield. CONFIRMED bits (same layout as XD):
            //   bits 7:5 = talk sound-effect type  (peopleInfoBiosGetTalkSe:  (b >> 5) & 0x7)
            //   bits 3:2 = collision type          (peopleInfoBiosGetColType: (b >> 2) & 0x3)
            // bit 4 (XD bound-check) and bits 1:0 have no Colosseum accessor — unconfirmed.
            .uint8(name: "flags"),

            // 0x01: Neck bone index (head-tracking). INFERRED — XD offset; Colosseum
            // runs neck updates (_peopleDoNeckUpdate) but exposes no GetNeckIndex accessor.
            // Signed in XD (extsb, default -1).
            .int8(name: "neck_bone_index"),

            // 0x02: Chest bone index. INFERRED (XD offset; no Colosseum accessor).
            .int8(name: "chest_bone_index"),

            // 0x03: Padding.
            .padding(length: 1),

            // 0x04: FSYS resource ID of the .dat model in people_archive.fsys. CONFIRMED —
            // peopleInfoBiosGetModelResID reads 0x04; it is also the search key in
            // peopleSearchID / the pointer-search accessor.
            .uint32(name: "model_resource_id"),

            // 0x08: Walk animation cycle length. INFERRED (XD offset; no Colosseum accessor).
            .float(name: "walk_length"),

            // 0x0C: Run animation cycle length. INFERRED (XD offset; no Colosseum accessor).
            .float(name: "run_length"),

            // 0x10: Collision bounding-sphere radius. CONFIRMED — peopleInfoBiosGetColBallSize.
            .float(name: "collision_radius"),

            // 0x14: Neck left rotation limit. INFERRED (XD offset; no dedicated Colosseum
            // accessor, but symmetric with the confirmed up/down pair below).
            .float(name: "neck_left_limit"),

            // 0x18: Neck right rotation limit. INFERRED (as above).
            .float(name: "neck_right_limit"),

            // 0x1C: Neck up rotation limit. CONFIRMED — peopleInfoBiosGetNeckUpLimit
            // (stored value is multiplied by a global gaze-scale constant on read).
            .float(name: "neck_up_limit"),

            // 0x20: Neck down rotation limit. CONFIRMED — peopleInfoBiosGetNeckDownLimit.
            .float(name: "neck_down_limit"),

            // 0x24: Interaction/talk trigger distance. INFERRED (XD offset; no Colosseum accessor).
            .float(name: "talk_distance"),

            // 0x28–0xDB: Colosseum-specific tail (180 bytes). Not read by any peopleInfoBios
            // accessor; contents undecoded. Kept as a raw byte array so it round-trips intact.
            .array(name: "unknown_tail", count: 180, of: .uint8),
            // Total: 0xDC (220 bytes).
        ],
        description: "Colosseum overworld character model metadata (0xDC/220 bytes). Shares XD's 0x00–0x27 header (confirmed at every Colosseum-read offset) plus a 180-byte engine-specific tail. Stride and offsets confirmed by peopleInfoBios* / peopleSearchID / zz_018fd88_ disassembly."
    )
}
