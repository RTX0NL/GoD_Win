import Foundation
import Structs

/// Trainer-facing tables in `common.fsys`: model bindings, the customisable
/// parts catalogue, and title/quote message ids.
///
/// Ported from the legacy tool's
/// `Revolution Tool CL/structs/TrainerModelsTables.swift` and
/// `SmallStructTables.swift`.
public extension PBRStructDefaults {

    /// One trainer model (0x54 / 84 bytes).
    ///
    /// Mirrors the Pokémon model table's shape at the top — a packed
    /// parameters byte with constant filler, then archive/file id pairs —
    /// but binds two models rather than a normal/shiny pair: a low-detail
    /// one and a high-detail one, selected by context.
    static let trainerModelStruct = StructMap(
        name: "PBRTrainerModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Packed parameters.
            //   bit  7   — this trainer's appearance is customisable.
            //   bits 6:4 — which `TrainerCustomParts` table the customiser
            //              draws from.
            .uint8(name: "parameters"),
            // 0x01: Alignment filler (0xD0 on every row), same as the Pokémon
            // model table.
            .padding(length: 3),

            // 0x04
            .uint32(name: "low_quality_fsys_id"),
            .uint32(name: "low_quality_file_id"),
            // 0x0C
            .uint32(name: "high_quality_fsys_id"),
            .uint32(name: "high_quality_file_id"),

            // 0x14: Layout not yet documented.
            .array(name: "unknown_values", count: 0x40, of: .uint8),
        ],
        description: "Binds a trainer to its low- and high-detail models, and marks whether the trainer is customisable."
    )

    /// One customisable-parts set (0x3C / 60 bytes).
    static let trainerCustomisationStruct = StructMap(
        name: "PBRTrainerCustomisation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: The ten model files this part set can supply. They live
            // in the `*_tr_*` archives.
            .array(name: "model_file_ids", count: 10, of: .uint32),

            // 0x28
            .uint16(name: "name_message_id"),
            .uint16(name: "description_message_id"),
            .uint16(name: "unknown_1"),
            .uint8(name: "unknown_2"),

            // 0x2F: One flag byte per model slot above.
            .array(name: "unknown_flags", count: 10, of: .uint8),
            // 0x39: Alignment filler (0xD0 on every row) — the legacy tool
            // guessed "Filler?" here and was right.
            .padding(length: 3),
        ],
        description: "One set of interchangeable trainer appearance parts and its menu strings."
    )

    /// One trainer title (0x0E / 14 bytes).
    static let trainerTitleStruct = StructMap(
        name: "PBRTrainerTitle",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "name_message_id"),
            // 0x02: Battle dialogue lines for trainers with this title.
            .array(name: "quote_message_ids", count: 6, of: .uint16),
        ],
        description: "A trainer title's name and its six battle dialogue message ids."
    )
}
