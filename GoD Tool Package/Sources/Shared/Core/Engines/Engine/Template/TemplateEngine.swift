//@_exported import GoDEngine
import GoDFoundation
import Structs

/// A template for formatting new engines. Not intended to be used
internal struct TemplateEngine: Engine {
    public typealias DataType = TemplateEngine.Data
    public typealias EnumsType = TemplateEngine.Enums
    public typealias StructsType = TemplateEngine.Structs
    
    public let name = "Template Engine"
    public private(set) var data = TemplateEngine.Data()
    public private(set) var enums = TemplateEngine.Enums()
    public private(set) var structs = TemplateEngine.Structs()
    private(set) var definitions: [StructDefinition]!
    
    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }
}

