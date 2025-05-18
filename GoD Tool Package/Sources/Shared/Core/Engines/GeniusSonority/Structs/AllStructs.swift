import GoDFoundation
import Structs

public extension GeniusSonorityEngine {
    struct Structs: EngineStructs {
        enum Defaults {}
        
        public private(set) var entries: [StructMap] = Structs.allItems
        
        public init(unchecked items: [StructMap]) {
            self.entries = items
        }
        
        static public var allItems: [StructMap] {
            [
                Defaults.fsysHeaderStruct,
                Defaults.fsysFooterStruct,
                Defaults.fsysFileMetadataStruct,
                Defaults.lzssHeaderStruct
            ]
        }
    }
}

internal extension GeniusSonorityEngine {
    // struct definition accessors
    var fsysHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSHeader" })! }
    var fsysFooterStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSFooter" })! }
    var fsysFileMetaDataStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSFileMetaData" })! }
    var lzssHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "LZSSHeader" })! }
}
