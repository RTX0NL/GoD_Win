import Foundation
import Structs

extension WiiEngine.Structs.Defaults {
    /// Wii ticket structure (0x2A4 bytes).
    /// Located immediately at the partition start (before the partition header).
    /// Contains the encrypted title key needed for partition decryption.
    static let wiiTicket = StructMap(
        name: "WiiTicket",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "signature_type"),
            .padding(length: 0x100),                    // RSA-2048 signature
            .padding(length: 0x3C),                     // signature padding
            .string(name: "issuer", format: .utf8, length: 0x40),
            .padding(length: 0x3F),                     // ECDH data + padding
            .array(name: "encrypted_title_key", count: 16, of: .uint8),  // offset 0x1BF
            .uint8(name: "unknown"),
            .array(name: "ticket_id", count: 8, of: .uint8),
            .array(name: "console_id", count: 4, of: .uint8),
            .array(name: "title_id", count: 8, of: .uint8),     // offset 0x1DC, used as IV for title key decryption
            .uint16(name: "unknown2"),
            .uint16(name: "title_version"),
            .uint32(name: "permitted_titles_mask"),
            .uint32(name: "permit_mask"),
            .uint8(name: "title_export_allowed"),
            .uint8(name: "common_key_index", description: "0=common, 1=korean, 2=vWii"),
            .padding(length: 0x30),                     // unknown
            .padding(length: 0x40),                     // content access permissions
            .padding(length: 0x02),                     // padding
            .array(name: "time_limits", count: 0x40, of: .uint8),
        ]
    )
}
