import GoDFoundation
import Structs

internal extension TemplateEngine {
    struct Structs: EngineStructs {
        enum Defaults {}
        
        public private(set) var entries: [StructMap] = Structs.allItems
        
        public init(unchecked items: [StructMap]) {
            self.entries = items
        }
        
        static public var allItems: [StructMap] {
            [
                Defaults.templateStruct
            ]
        }
    }
}

internal extension TemplateEngine {
    // struct definition accessors
    var templateStruct: StructDefinition { definitions.first(where: { $0.name == "TemplateStruct" })! }
}
