import Foundation
import Structs

extension WiiEngine.Structs.Defaults {
    /// Wii disc header at offset 0x0. Similar to GameCube but with Wii magic word at 0x18.
    static let wiiDiscHeader = StructMap(
        name: "WiiDiscHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .string(name: "game_id", format: .utf8, length: 4),
            .string(name: "maker_code", format: .utf8, length: 2),
            .uint8(name: "disc_number"),
            .uint8(name: "disc_version"),
            .uint8(name: "audio_streaming"),
            .uint8(name: "stream_buffer_size"),
            .padding(length: 0x0E),
            .uint32(name: "wii_magic_word", description: "Always 0x5D1C9EA3 for Wii discs"),
            .uint32(name: "gc_magic_word", description: "Always 0 for Wii discs"),
            .string(name: "game_title", format: .utf8, length: 0x40),
            .uint8(name: "disable_hash_verification"),
            .uint8(name: "disable_disc_encryption"),
            .padding(length: 0x39E),
        ]
    )
}
