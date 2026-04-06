import GoDFoundation
import GoDEngine
import Structs

public extension XDEngine {
    struct Enums: EngineEnums {
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
