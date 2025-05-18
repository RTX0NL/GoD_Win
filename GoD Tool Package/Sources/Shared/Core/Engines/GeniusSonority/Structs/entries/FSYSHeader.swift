import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let fsysHeaderStruct = StructMap(
        name: "FSYSHeader",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "magic_bytes", format: .utf8, length: 4),
            .int32(name: "unknown1"),
            .abstraction(name: "group_id", typeName: "FsysGroupIDs"),
            .int32(name: "entry_count"),
            .int32(name: "flags"),
            .int32(name: "unknown_2"),
            .int32(name: "unknown_3"),
            .int32(name: "unknown_4"),
            .int32(name: "file_size"),
            .padding(length: 0x1C),
            .int32(name: "file_metadata_list"),
            .int32(name: "file_names_pointer"),
            .int32(name: "file_data_pointer"),
            .padding(length: 0x14)
        ]
    )
}
