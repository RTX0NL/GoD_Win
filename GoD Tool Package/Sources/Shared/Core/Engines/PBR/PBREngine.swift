@_exported import GoDEngine
import GoDFoundation
import Structs
import Foundation

/// Pokémon Battle Revolution engine.
///
/// PBR keeps almost all of its tunable game data in `common.fsys`, whose
/// numbered members (`common_00.bin` … `common_32.bin`) are each one data
/// table in a shared container format — see `PBRCommonTableHeader`. The
/// engine's structs describe those tables; the enums name the file indexes
/// and the model body-map slots.
public struct PBREngine: Engine {
    public typealias DataType = PBREngine.Data
    public typealias EnumsType = PBREngine.Enums
    public typealias StructsType = PBREngine.Structs

    /// The folder an engine serializes to is named after it, so callers
    /// that need the path before building an instance (project setup,
    /// generated configs) can read it from the type instead of repeating
    /// the literal and letting the two drift apart.
    public static let defaultName = "PBR Engine"
    public let name = Self.defaultName
    public private(set) var data = PBREngine.Data()
    public private(set) var enums = PBREngine.Enums()
    public private(set) var structs = PBREngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public static func defaults() throws -> PBREngine {
        try .init(data: Data(), enums: Enums(), structs: Structs())
    }
}

public enum PokemonBattleRevolution {
    public static let gameIDUS = "RPBE"
    public static let gameIDEU = "RPBP"
    public static let gameIDJP = "RPBJ"

    public static let gameIDs = [
        gameIDUS,
        gameIDEU,
        gameIDJP
    ]

    /// Whether a build uses the Japanese `common.fsys` member ordering.
    /// The JP disc ships the same 33 tables in a different order (and
    /// without the `ColosseumsUnknown` table), so anything that resolves a
    /// table by index has to branch on this. See
    /// `PBREngine.Data.commonTables`.
    public static func usesJapaneseTableOrder(gameID: String) -> Bool {
        gameID == gameIDJP
    }
}
