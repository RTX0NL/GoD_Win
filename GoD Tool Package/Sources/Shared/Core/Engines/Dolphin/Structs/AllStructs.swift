//
//  File.swift
//  
//
//  Created by Stars Momodu on 10/02/2025.
//

import GoDFoundation
import GoDEngine
import Structs

public extension DolphinEngine {
    struct Structs: EngineStructs {
        enum Defaults {}
        
        public private(set) var entries: [StructMap] = Structs.allItems
        
        public init(unchecked items: [StructMap]) {
            self.entries = items
        }
        
        static public var allItems: [StructMap] {
            [
                Defaults.bootDataStruct,
                Defaults.bi2Struct,
                Defaults.apploaderHeaderStruct,
                Defaults.dolHeaderStruct,
                Defaults.fstRootEntryStruct,
                Defaults.fstDirectoryEntryStruct,
                Defaults.fstFileEntryStruct
            ]
        }
    }
}

public extension DolphinEngine {
    var bootDataStruct: StructDefinition { definitions.first(where: { $0.name == "ISOBootData" })! }
    var bi2Struct: StructDefinition { definitions.first(where: { $0.name == "Bi2Data" })! }
    var apploaderHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "ApploaderHeader" })! }
    var dolHeaderStruct: StructDefinition { definitions.first(where: { $0.name == "DolHeader" })! }
    var fstRootEntryStruct: StructDefinition { definitions.first(where: { $0.name == "FSTRootEntry" })! }
    var fstDirectoryEntryStruct: StructDefinition { definitions.first(where: {$0.name == "FSTDirectoryEntry" })! }
    var fstFileEntryStruct: StructDefinition { definitions.first(where: { $0.name == "FSTFileEntry" })! }
}
