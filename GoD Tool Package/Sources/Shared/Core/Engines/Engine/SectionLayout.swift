//
//  SectionLayout.swift
//  GoDEngine
//
//  Describes typed regions *inside* one save section's bytes — the same role
//  `TypeMap` plays for a DOL/REL data section, keyed by byte offset instead of
//  by symbol because a save section has no symbols.
//
//  This exists because some sections aren't describable by a single struct.
//  XD's flag section is three bit banks whose split lives in another file
//  entirely (`common.rel`'s `GeneralFlags`), followed by two unrelated blocks
//  the serializer writes separately. A section type can't express that: the
//  save dump would need to know about flag tables, and Colosseum's flags —
//  which sit at an offset *inside* a larger section — couldn't be reached at
//  all.
//
//  So the save dump stays dumb: a section it can't type dumps as one `.bin`,
//  and a second operation (`saveSectionsDump`) decomposes that binary against
//  this layout. The reverse operation recomposes the binary before the save
//  build reads it, so the two halves are an ordinary dump-1 → dump-2,
//  build-2 → build-1 chain.
//

import GoDFoundation

/// Typed regions within one section, addressed by byte offset.
public struct SectionLayout: Codable, Equatable {

    /// The sections this layout describes, keyed by the section's `name` as
    /// the engine's `saveSections` declares it (`"Flags"`, `"Tail"`, …).
    /// Keyed by name rather than index so a layout survives a section being
    /// renumbered, and so it reads as documentation.
    public let sections: [String: Section]

    public init(sections: [String: Section] = [:]) {
        self.sections = sections
    }

    public struct Section: Codable, Equatable {
        /// Ordered, non-overlapping regions. Bytes no chunk claims are kept
        /// verbatim by the dump, so a partial layout is valid and describing
        /// more of a section later is additive.
        public let chunks: [Chunk]

        public init(chunks: [Chunk] = []) {
            self.chunks = chunks
        }
    }

    /// One typed region. Encodes as `{"flags": {…}}` / `{"struct": {…}}`,
    /// matching how `TypeMap.Chunk` spells its variants.
    public enum Chunk: Equatable {
        /// Bit banks decoded through a flag descriptor table.
        case flags(Flags)
        /// A single struct instance.
        case structInstance(StructChunk)
        /// A run of same-typed structs.
        case table(TableChunk)

        public struct Flags: Codable, Equatable {
            /// Artifact name (without extension) and the key a reader sees.
            public let name: String
            /// Byte offset of the first bank within the section, when the
            /// banks are a run of raw bytes. Absent when they are addressed
            /// as fields instead — see `Bank.field`.
            public let offset: Int?
            /// The banks, in order. A flag's `bank` field is a 1-based index
            /// into this list — bank 0 means the flag has no storage.
            public let banks: [Bank]

            public init(name: String, offset: Int? = nil, banks: [Bank]) {
                self.name = name
                self.offset = offset
                self.banks = banks
            }

            public struct Bank: Codable, Equatable {
                /// The game's own name for the bank (`FlagLevel0`, …).
                public let name: String
                /// Byte length. Must be what the game hands its flag system —
                /// the bit positions are a running total over these, so a
                /// wrong length silently moves every later flag.
                public let length: Int
                /// Property of the section's struct this bank lives in, for a
                /// section that dumps as typed JSON rather than raw bytes.
                ///
                /// Colosseum needs this: its flags sit inside `Tail`, which is
                /// a struct, so there is no `.bin` to slice and the banks are
                /// already named byte arrays in the artifact. When this is set
                /// the flag CSV is **authoritative** — the build writes the
                /// decoded values back into these properties, so editing the
                /// array in the section's own JSON has no effect.
                public let field: String?

                public init(name: String, length: Int, field: String? = nil) {
                    self.name = name
                    self.length = length
                    self.field = field
                }
            }

            /// Total bytes the banks occupy.
            public var length: Int { banks.reduce(0) { $0 + $1.length } }

            /// True when the banks are properties of a typed section rather
            /// than a byte range. Mixing the two in one chunk is meaningless,
            /// so the first bank decides.
            public var isFieldAddressed: Bool { banks.first?.field != nil }
        }

        public struct StructChunk: Codable, Equatable {
            public let name: String
            public let offset: Int
            /// Struct definition name, resolved across the operation's engines.
            public let type: String

            public init(name: String, offset: Int, type: String) {
                self.name = name
                self.offset = offset
                self.type = type
            }
        }

        public struct TableChunk: Codable, Equatable {
            public let name: String
            public let offset: Int
            public let type: String
            public let count: Int

            public init(name: String, offset: Int, type: String, count: Int) {
                self.name = name
                self.offset = offset
                self.type = type
                self.count = count
            }
        }

        /// Where this chunk starts within its section. Field-addressed flag
        /// chunks have no byte range and never reach this.
        public var offset: Int {
            switch self {
            case .flags(let c): return c.offset ?? 0
            case .structInstance(let c): return c.offset
            case .table(let c): return c.offset
            }
        }

        /// True only for a flag chunk whose banks name struct properties.
        public var isFieldAddressed: Bool {
            if case .flags(let c) = self { return c.isFieldAddressed }
            return false
        }

        /// The artifact stem, unique within a section.
        public var name: String {
            switch self {
            case .flags(let c): return c.name
            case .structInstance(let c): return c.name
            case .table(let c): return c.name
            }
        }
    }
}

// MARK: - Chunk coding

extension SectionLayout.Chunk: Codable {
    private enum CodingKeys: String, CodingKey {
        case flags, `struct`, table
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let c = try container.decodeIfPresent(Flags.self, forKey: .flags) {
            self = .flags(c)
        } else if let c = try container.decodeIfPresent(StructChunk.self, forKey: .struct) {
            self = .structInstance(c)
        } else if let c = try container.decodeIfPresent(TableChunk.self, forKey: .table) {
            self = .table(c)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A section-layout chunk must be one of: flags, struct, table"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .flags(let c): try container.encode(c, forKey: .flags)
        case .structInstance(let c): try container.encode(c, forKey: .struct)
        case .table(let c): try container.encode(c, forKey: .table)
        }
    }
}
