import Foundation
import Structs

extension TemplateEngine.Structs.Defaults {
    static let templateStruct = StructMap(
        name: "StructName",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "date", format: .utf8, length: 10),
            .padding(length: 6),
            .uint32(name: "entry_point"),
            .uint32(name: "size"),
            .uint32(name: "trailer_size"),
            .padding(length: 4)
        ]
    )
}
