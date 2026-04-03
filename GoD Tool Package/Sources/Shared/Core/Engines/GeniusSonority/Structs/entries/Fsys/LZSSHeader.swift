import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let lzssHeaderStruct = StructMap(
        name: "LZSSHeader",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "magic_bytes", format: .utf8, length: 4),
            .uint32(name: "uncompressed_size"),
            .uint32(name: "compressed_size"),
            .uint32(name: "unknown")
        ]
    )
}
