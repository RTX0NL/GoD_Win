import GoDFoundation
import Structs

/// A user-authored file that describes typed regions within data sections.
/// Contains a single ordered list of chunks that the disassembler uses
/// to produce typed output (struct JSON, embedded files, etc.) instead of raw hex.
///
/// The engine folders whose struct/enum definitions resolve these chunks'
/// type names are supplied by the disassembly/assembly operation config
/// (`engines`), not by the map itself — the same map applies regardless of
/// where its engine lives on disk.
public struct TypeMap: Codable, Equatable {

    public let chunks: [Chunk]

    public init(chunks: [Chunk] = []) {
        self.chunks = chunks
    }

    /// A typed data chunk — each variant carries its own associated data.
    /// Encodes as `{"table": {...}}`, `{"single": {...}}`, `{"file": {...}}`
    /// or `{"count": {...}}`.
    public enum Chunk: Equatable {
        /// A table of consecutive same-typed struct entries
        case table(Table)
        /// A single typed value (struct, primitive, or enum)
        case single(Single)
        /// An embedded file dumped with a custom extension
        case file(EmbeddedFile)
        /// A word holding another table's entry count — derived on build,
        /// never stored
        case count(Count)

        public struct Table: Codable, Equatable {
            /// Display name for this table
            public let name: String
            /// Label of the first entry
            public let start: String
            /// Type name (looked up in engines — no "struct" prefix needed)
            public let entryType: String

            /// How many entries the table has. Absent means "as many as fit
            /// between this label and the next", which is what a table whose
            /// end a symbol already marks should say.
            ///
            /// There used to be a `countLabel` beside this — a label naming a
            /// word that holds the count — and nothing ever read it: a map
            /// could set it and get an empty table with no complaint. The
            /// count words are worth checking a declared count *against*
            /// (`DolTableCSVCorpusTests` does), but reading one at dump time
            /// would only trade a hardcoded number for a hardcoded per-region
            /// address, since on the DOL side they are unnamed `lbl_` targets
            /// in `.sdata` rather than symbols.
            public let count: Int?

            public init(name: String, start: String, entryType: String, count: Int? = nil) {
                self.name = name
                self.start = start
                self.entryType = entryType
                self.count = count
            }
        }

        public struct Single: Codable, Equatable {
            /// Label at this value's address
            public let label: String
            /// Type name (looked up in engines)
            public let type: String

            public init(label: String, type: String) {
                self.label = label
                self.type = type
            }
        }

        public struct EmbeddedFile: Codable, Equatable {
            /// Label at the file's start address
            public let label: String
            /// File extension (e.g. "msg", "scd")
            public let `extension`: String

            /// Optional explicit byte length.
            ///
            /// Normally absent, and normally should be: by the time a chunk
            /// is type-matched it has already been *split*, and the split
            /// knows the real bounds — a REL section's chunks run from one
            /// symbol to the next, and a DOL is only chunked at all when a
            /// symbol map says where the labels are. Restating the length in
            /// the map just gives it a second chance to disagree, and it made
            /// every new entry require measuring a file by hand.
            ///
            /// Kept for the rare case where a declared file is genuinely
            /// shorter than the gap to the next label and the remainder must
            /// stay a separate chunk.
            public let size: Int?

            public init(label: String, extension ext: String, size: Int? = nil) {
                self.label = label
                self.extension = ext
                self.size = size
            }
        }

        /// An integer that holds the number of entries in a table.
        ///
        /// The value is a fact about the table, so it isn't dumped as an
        /// editable value: the assembler writes the table's entry count here,
        /// big-endian, and the table is sized by its CSV rather than held to
        /// the count it was dumped with. A separately editable count would let
        /// a table gain a row the game never reads.
        ///
        /// Nothing about a module's layout is assumed — which integer counts
        /// which table, and how wide it is, is declared here, per type map.
        public struct Count: Codable, Equatable {
            /// Label at the count
            public let label: String
            /// Start label of the table it counts — a `table` chunk in the
            /// same type map
            public let table: String
            /// How the count is stored. Integers only, which the type
            /// enforces: a float or a struct name fails to decode. Defaults
            /// to `uint32`, the width of a REL's count words.
            public let type: IntegerProperties

            public init(label: String, table: String, type: IntegerProperties = .uint32) {
                self.label = label
                self.table = table
                self.type = type
            }

            private enum CodingKeys: String, CodingKey { case label, table, type }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                label = try container.decode(String.self, forKey: .label)
                table = try container.decode(String.self, forKey: .table)
                type = try container.decodeIfPresent(IntegerProperties.self, forKey: .type) ?? .uint32
            }
        }

        public var label: String {
            switch self {
            case .table(let t): return t.start
            case .single(let s): return s.label
            case .file(let f): return f.label
            case .count(let c): return c.label
            }
        }
    }

    /// Checks that every `count` chunk names a table this map declares.
    ///
    /// A count of a symbol the map doesn't list, or of one it lists as
    /// something other than a table, has nothing to derive its value from,
    /// so it is an error rather than a raw word left in place.
    public func validate() throws {
        var tableLabels = Set<String>()
        var otherLabels = Set<String>()
        for chunk in chunks {
            if case .table(let t) = chunk { tableLabels.insert(t.start) } else { otherLabels.insert(chunk.label) }
        }
        for case .count(let count) in chunks where !tableLabels.contains(count.table) {
            throw TypeMapError.countTargetNotATable(
                count: count.label, table: count.table, declared: otherLabels.contains(count.table), .init()
            )
        }
    }
}

public enum TypeMapError: Error, CustomStringConvertible {
    case countTargetNotATable(count: String, table: String, declared: Bool, ErrorTrace)

    public var description: String {
        switch self {
        case let .countTargetNotATable(count, table, declared, trace):
            let problem = declared ? "which the type map declares as something other than a table"
                                   : "which the type map doesn't declare"
            return "Count '\(count)' counts '\(table)', \(problem)\n\(trace)"
        }
    }
}

// MARK: - Custom Codable for TypeMap.Chunk

extension TypeMap.Chunk: Codable {
    private enum CodingKeys: String, CodingKey {
        case table, single, file, count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let table = try container.decodeIfPresent(Table.self, forKey: .table) {
            self = .table(table)
        } else if let single = try container.decodeIfPresent(Single.self, forKey: .single) {
            self = .single(single)
        } else if let file = try container.decodeIfPresent(EmbeddedFile.self, forKey: .file) {
            self = .file(file)
        } else if let count = try container.decodeIfPresent(Count.self, forKey: .count) {
            self = .count(count)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "TypeMap.Chunk must contain 'table', 'single', 'file' or 'count'"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .table(let t): try container.encode(t, forKey: .table)
        case .single(let s): try container.encode(s, forKey: .single)
        case .file(let f): try container.encode(f, forKey: .file)
        case .count(let c): try container.encode(c, forKey: .count)
        }
    }
}
