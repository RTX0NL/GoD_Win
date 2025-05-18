import GoDFoundation
import Structs

public extension GeniusSonorityEngine {
    struct Enums: EngineEnums {
        enum Defaults {}
        
        public private(set) var entries: [Enum] = Enums.allItems
        
        public init(unchecked items: [Enum]) {
            self.entries = items
        }
        
        static public var allItems: [Enum] {
            [
                Defaults.fileTypesColoXDEnum,
                Defaults.fsysGroupIDsColoEnum
            ]
        }
    }
}

public extension GeniusSonorityEngine {
    // enum definition accessors
    var fileTypesEnum: Enum { enums.entries.first(where: { $0.name == "FileTypes" })! }
    var fsysGroupIDsEnum: Enum { enums.entries.first(where: { $0.name == "FsysGroupIDs" })! }
}
