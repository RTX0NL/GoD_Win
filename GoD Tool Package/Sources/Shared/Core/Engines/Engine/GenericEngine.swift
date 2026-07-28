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
