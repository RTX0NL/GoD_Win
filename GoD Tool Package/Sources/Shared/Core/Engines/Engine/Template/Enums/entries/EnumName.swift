import Foundation
import Structs

extension TemplateEngine.Enums.Defaults {
    static let templateEnum = Enum(
        name: "Template Enum",
        allowUnknownCases: false,
        values: [
            .init(name: "Value_1", rawValue: 1),
            .init(name: "Value_2", rawValue: 2),
            .init(name: "Value_3", rawValue: 3)
        ],
        propertyType: .uint8
    )
}
