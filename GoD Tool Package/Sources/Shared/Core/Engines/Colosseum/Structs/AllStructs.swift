import GoDFoundation
import GoDEngine
import Structs

public extension ColosseumEngine {
    struct Structs: EngineStructs {
        public private(set) var entries: [StructMap] = Structs.allItems

        public init(unchecked items: [StructMap]) {
            self.entries = items
        }

        static public var allItems: [StructMap] {
            [
                ColosseumStructDefaults.characterModelStruct,
            ]
        }
    }
}

public extension ColosseumEngine {
    // struct definition accessors
}
