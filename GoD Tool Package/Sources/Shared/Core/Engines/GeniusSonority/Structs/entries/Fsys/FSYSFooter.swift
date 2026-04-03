import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let fsysFooterStruct = StructMap(
        name: "FSYSFooter",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .padding(length: 0x1C),
            .string(name: "magic_bytes", format: .utf8, length: 4),
        ]
    )
}
