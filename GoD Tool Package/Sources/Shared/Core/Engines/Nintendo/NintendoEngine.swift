@_exported import GoDEngine
import GoDFoundation
import Structs

/// Nintendo's own container formats, as opposed to a specific game's.
///
/// This engine holds the formats that ship with Nintendo's SDKs and turn up
/// across unrelated titles — U8 (`.arc`) and NARC (`.narc`) to begin with.
/// It deliberately carries no game knowledge: an archive's layout is the
/// same whether it came from Battle Revolution or New Super Mario Bros Wii,
/// so the per-game routing of what comes *out* of an archive stays in the
/// game engines.
public struct NintendoEngine: Engine {
    public typealias DataType = NintendoEngine.Data
    public typealias EnumsType = NintendoEngine.Enums
    public typealias StructsType = NintendoEngine.Structs

    /// See `WiiEngine.defaultName` — callers that need the engine's folder
    /// name before building an instance read it from the type.
    public static let defaultName = "Nintendo Engine"
    public let name = Self.defaultName
    public private(set) var data = NintendoEngine.Data()
    public private(set) var enums = NintendoEngine.Enums()
    public private(set) var structs = NintendoEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> NintendoEngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}
