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
                Defaults.lzssHeaderStruct,
                Defaults.fsysTOCHeaderStruct,
                Defaults.fsysTOCEntryStructFull,
            ]
        }
    }
}

internal extension GeniusSonorityEngine {
    var fsysHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSHeader" })! }
    var fsysFooterStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSFooter" })! }
    var fsysFileMetaDataStruct: StructDefinition { definitions.first(where: { $0.name == "FSYSFileMetaData" })! }
    var lzssHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "LZSSHeader" })! }
    var fsysTOCHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "FsysTOCHeader" })! }
    var fsysTOCEntryStruct: StructDefinition { definitions.first(where: { $0.name == "FsysTOCEntry" })! }
}
