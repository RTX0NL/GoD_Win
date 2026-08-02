//
//  GenericEngine.swift
//  GoDEngine
//
//  A schema-agnostic engine used when an operation only needs an engine's
//  struct/enum definitions and doesn't care which concrete game engine the
//  folder belongs to. Its `DataType` decodes from any engine's top-level
//  JSON (the bytes are ignored), and its enum/struct sets accept whatever
//  the folder contains, so `GenericEngine(from:in:)` can load *any* engine
//  folder and resolve definitions by name via `getStruct` / `getEnum`.
//

import GoDFoundation
import Structs

public struct GenericEngine: Engine {

    /// Decodes from (and ignores) whatever the engine's data JSON contains.
    /// Real engines carry a bespoke `DataType`; here we only care about the
    /// enum/struct folders, so the data file's content is irrelevant.
    public struct Data: Codable {
        public init() {}
        /// Ignores whatever the engine's data JSON holds — never reads the
        /// decoder, so it accepts any shape.
        public init(from decoder: Decoder) throws {}
        /// Emits an empty object so the serialized engine has a valid
        /// top-level `<name>.json` (an empty `encode` would produce no
        /// top-level value and fail encoding).
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode([String: String]())
        }
    }

    /// Accepts exactly the enums found in the folder (no required baseline).
    public struct Enums: EngineEnums {
        public private(set) var entries: [Enum]
        public init(unchecked items: [Enum]) { self.entries = items }
        public static var allItems: [Enum] { [] }
    }

    /// Accepts exactly the structs found in the folder (no required baseline).
    public struct Structs: EngineStructs {
        public private(set) var entries: [StructMap]
        public init(unchecked items: [StructMap]) { self.entries = items }
        public static var allItems: [StructMap] { [] }
    }

    public let name = "Generic Engine"
    public let data: Data
    public let enums: Enums
    public let structs: Structs

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
    }
}

// MARK: - Combining engines

public extension GenericEngine {

    /// Combines several engines into one, preserving their order.
    ///
    /// `getStruct` / `getEnum` take the first definition of a given name, so
    /// the sub-engines are effectively consulted in turn and the earliest
    /// one wins. Where two engines name the same type differently — Colosseum
    /// and XD both declare `CharacterModel`, at 0xDC and 0x34 bytes — order
    /// is what decides, so callers should pass the game engine first.
    ///
    /// Definitions resolve across the whole combination, not just within the
    /// engine that declared them: a Colosseum struct can reference a Pokemon
    /// enum as long as both engines are in the list. That is the point of
    /// combining rather than trying each engine in isolation.
    init(combining engines: [any Engine]) throws {
        try self.init(
            data: Data(),
            enums: Enums(unchecked: engines.flatMap { $0.enums.entries }),
            structs: Structs(unchecked: engines.flatMap { $0.structs.entries })
        )
    }

    /// Loads each folder as an engine and combines them, in order.
    init(combining folders: [Folder], in fileSystem: FileSystemTree) throws {
        try self.init(combining: folders.map { folder in
            try GenericEngine(from: folder, in: fileSystem)
        })
    }

    /// Names declared by more than one of the combined engines, where only
    /// the first is reachable. Worth logging: a shadowed struct resolves to a
    /// different layout than its author intended.
    var shadowedNames: (structs: [String], enums: [String]) {
        func repeated(_ names: [String]) -> [String] {
            var seen = Set<String>()
            var shadowed = Set<String>()
            for name in names {
                if !seen.insert(name).inserted { shadowed.insert(name) }
            }
            return shadowed.sorted()
        }
        return (repeated(structs.entries.map(\.name)), repeated(enums.entries.map(\.name)))
    }
}
