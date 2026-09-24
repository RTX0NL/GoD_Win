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
            // CRC-32 of the entry's *uncompressed* payload (IEEE, the same
            // parameters as `CRC32.compute`). Colosseum and XD leave it zero
            // — verified on all 4152 and 4445 compressed entries of their US
            // discs — while Battle Revolution fills it in, and that was the
            // only reason its archives didn't repack byte for byte.
            //
            // The name stays `unknown` deliberately. A struct's property names
            // are serialized into every project's engine folder and looked up
            // by exact match, so renaming this would silently write nothing on
            // a project dumped before the rename rather than fail loudly.
            .uint32(name: "unknown")
        ]
    )
}
