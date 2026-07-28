@_exported import GoDEngine
import GoDFoundation
import Structs

public struct WiiEngine: Engine {
    public typealias DataType = WiiEngine.Data
    public typealias EnumsType = WiiEngine.Enums
    public typealias StructsType = WiiEngine.Structs

    /// See `XDEngine.defaultName` — callers that need the engine's folder
    /// name before building an instance read it from the type.
    public static let defaultName = "Wii Engine"
    public let name = Self.defaultName
    public private(set) var data = WiiEngine.Data()
    public private(set) var enums = WiiEngine.Enums()
    public private(set) var structs = WiiEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> WiiEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}
