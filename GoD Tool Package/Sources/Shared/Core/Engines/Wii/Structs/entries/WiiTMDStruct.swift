import Foundation
import Structs

extension WiiEngine.Structs.Defaults {
    /// TMD (Title Metadata) header. Variable length due to content records.
    /// The full TMD is: header + (content_count * 0x24) bytes of content records.
    static let wiiTMDHeader = StructMap(
        name: "WiiTMDHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "signature_type"),
            .padding(length: 0x100),                     // RSA-2048 signature
            .padding(length: 0x3C),                      // signature padding
            .string(name: "issuer", format: .utf8, length: 0x40),
            .uint8(name: "version"),
            .uint8(name: "ca_crl_version"),
            .uint8(name: "signer_crl_version"),
            .uint8(name: "is_vwii"),
            .array(name: "ios_title_id", count: 8, of: .uint8),
            .array(name: "title_id", count: 8, of: .uint8),
            .uint32(name: "title_type"),
            .uint16(name: "group_id"),
            .padding(length: 2),                         // reserved
            .uint16(name: "region"),
            .padding(length: 0x3A),                      // ratings + reserved
            .padding(length: 0x0C),                      // IPC mask + reserved
            .padding(length: 0x12),                      // access rights + reserved
            .uint16(name: "title_version"),
            .uint16(name: "content_count"),
            .uint16(name: "boot_index"),
            .padding(length: 2),                         // minor version / padding
        ]
    )

    /// TMD content record (0x24 bytes each).
    static let wiiTMDContentRecord = StructMap(
        name: "WiiTMDContentRecord",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "content_id"),
            .uint16(name: "index"),
            .uint16(name: "type"),
            .uint64(name: "size"),
            .array(name: "sha1_hash", count: 20, of: .uint8),
        ]
    )
}
