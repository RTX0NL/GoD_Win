@_exported import GoDEngine
import GoDFoundation
import Structs

public struct GamecubeEngine: Engine {
    public typealias DataType = GamecubeEngine.Data
    public typealias EnumsType = GamecubeEngine.Enums
    public typealias StructsType = GamecubeEngine.Structs
    
    public let name = "Gamecube Engine"
    public private(set) var data = GamecubeEngine.Data()
    public private(set) var enums = GamecubeEngine.Enums()
    public private(set) var structs = GamecubeEngine.Structs()
    private(set) var definitions: [StructDefinition]!
    
    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }
    
    public static func defaults() throws -> GamecubeEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}

