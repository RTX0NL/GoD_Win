//
//  DolphinEngine.swift
//  
//
//  Created by Stars Momodu on 05/06/2024.
//

@_exported import GoDEngine
import GoDFoundation
import Structs

public struct DolphinEngine: Engine {
    public typealias DataType = DolphinEngine.Data
    public typealias EnumsType = DolphinEngine.Enums
    public typealias StructsType = DolphinEngine.Structs
    
    public let name = "Dolphin Engine"
    public private(set) var data = DolphinEngine.Data()
    public private(set) var enums = DolphinEngine.Enums()
    public private(set) var structs = DolphinEngine.Structs()
    private(set) var definitions: [StructDefinition]!
    
    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }
    
    public static func defaults() throws -> DolphinEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}
