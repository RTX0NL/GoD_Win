import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let fsysTOCEntryStructSmall = StructMap(
        name: "FsysTOCEntry",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .uint32(name: "group_id"),
            .uint32(name: "filename_address")
        ]
    )
    
    static let fsysTOCEntryStructFull = StructMap(
        name: "FsysTOCEntry",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .uint32(name: "group_id"),
            .uint32(name: "filename_address"),
            .padding(length: 8)
        ]
    )
}
