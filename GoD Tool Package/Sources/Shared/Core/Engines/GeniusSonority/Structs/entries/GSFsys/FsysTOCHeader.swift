import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let fsysTOCHeaderStruct = StructMap(
        name: "FsysTOCHeader",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "magic_bytes", format: .utf8, length: 4),
            .uint32(name: "unknown"),
            .uint32(name: "entry_count"),
            .uint32(name: "junk1"),
            .uint32(name: "entry_table_address"),
            .uint32(name: "string_table_address"),
            .uint32(name: "junk2"),
            .uint32(name: "junk3")
        ]
    )
}
