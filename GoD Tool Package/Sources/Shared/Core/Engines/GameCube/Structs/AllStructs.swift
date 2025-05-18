import GoDFoundation
import GoDEngine
import Structs

public extension GamecubeEngine {
    struct Structs: EngineStructs {
        enum Defaults {}
        
        public private(set) var entries: [StructMap] = Structs.allItems
        
        public init(unchecked items: [StructMap]) {
            self.entries = items
        }
        
        static public var allItems: [StructMap] {
            [
            ]
        }
    }
}

public extension GamecubeEngine {
    // struct definition accessors
}
