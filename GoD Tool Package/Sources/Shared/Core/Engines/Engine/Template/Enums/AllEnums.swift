import GoDFoundation
import Structs

internal extension TemplateEngine {
    struct Enums: EngineEnums {
        enum Defaults {}
        
        public private(set) var entries: [Enum] = Enums.allItems
        
        public init(unchecked items: [Enum]) {
            self.entries = items
        }
        
        static public var allItems: [Enum] {
            [
            ]
        }
    }
}

internal extension TemplateEngine {
    // enum definition accessors
    var templateEnum: Enum { enums.entries.first(where: { $0.name == "template" })! }
}
