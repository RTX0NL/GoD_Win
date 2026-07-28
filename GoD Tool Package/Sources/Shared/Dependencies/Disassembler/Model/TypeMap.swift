import GoDFoundation

/// A user-authored file that describes typed regions within data sections.
/// Contains a single ordered list of chunks that the disassembler uses
/// to produce typed output (struct JSON, embedded files, etc.) instead of raw hex.
///
/// The engine folders whose struct/enum definitions resolve these chunks'
/// type names are supplied by the disassembly/assembly operation config
/// (`engines`), not by the map itself — the same map applies regardless of
/// where its engine lives on disk.
public struct TypeMap: Codable, Equatable {

    /// Ordered list of typed data chunks
    public let chunks: [Chunk]

    public init(chunks: [Chunk] = []) {
        self.chunks = chunks
    }

    /// A typed data chunk — each variant carries its own associated data.
    /// Encodes as `{"table": {...}}`, `{"single": {...}}`, or `{"file": {...}}`.
    public enum Chunk: Equatable {
        /// A table of consecutive same-typed struct entries
        case table(Table)
        /// A single typed value (struct, primitive, or enum)
        case single(Single)
        /// An embedded file dumped with a custom extension
        case file(EmbeddedFile)

        public struct Table: Codable, Equatable {
            /// Display name for this table
            public let name: String
            /// Label of the first entry
            public let start: String
            /// Type name (looked up in engines — no "struct" prefix needed)
            public let entryType: String
            /// Hardcoded entry count
            public let count: Int?
            /// Label pointing to a value holding the entry count (preferred over hardcoded)
            public let countLabel: String?

            public init(name: String, start: String, entryType: String, count: Int? = nil, countLabel: String? = nil) {
                self.name = name
                self.start = start
                self.entryType = entryType
                self.count = count
                self.countLabel = countLabel
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
            /// Size in bytes
            public let size: Int

            public init(label: String, extension ext: String, size: Int) {
                self.label = label
                self.extension = ext
                self.size = size
            }
        }
    }
}

// MARK: - Custom Codable for TypeMap.Chunk

extension TypeMap.Chunk: Codable {
    private enum CodingKeys: String, CodingKey {
        case table, single, file
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let table = try container.decodeIfPresent(Table.self, forKey: .table) {
            self = .table(table)
        } else if let single = try container.decodeIfPresent(Single.self, forKey: .single) {
            self = .single(single)
        } else if let file = try container.decodeIfPresent(EmbeddedFile.self, forKey: .file) {
            self = .file(file)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "TypeMap.Chunk must contain 'table', 'single', or 'file'"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .table(let t): try container.encode(t, forKey: .table)
        case .single(let s): try container.encode(s, forKey: .single)
        case .file(let f): try container.encode(f, forKey: .file)
        }
    }
}
