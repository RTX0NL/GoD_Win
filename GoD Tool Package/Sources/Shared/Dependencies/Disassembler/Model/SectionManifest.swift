import GoDFoundation

/// Manifest for a data section, listing chunks in order.
/// The ordering in the chunks array IS the ordering in the section binary.
public struct DataSectionManifest: Codable, Equatable {
    /// Section name (e.g. "data0")
    public let section: String
    /// Ordered list of data chunks
    public var chunks: [Chunk]

    public init(section: String, chunks: [Chunk] = []) {
        self.section = section
        self.chunks = chunks
    }

    public struct Chunk: Codable, Equatable {
        /// Label at the start of this chunk
        public let label: String
        /// What kind of data this chunk contains
        public let type: ChunkType
        /// File containing the chunk data. Relative to the section folder in
        /// a DOL section's `manifest.json`; relative to the module folder in
        /// a REL's `<name>.rel.json`, whose one chunk list spans every
        /// section.
        public let file: String
        /// For struct chunks: the struct type name
        public let structType: String?
        /// For table chunks: label pointing to the count value
        public let countLabel: String?
        /// For table chunks: hardcoded count (fallback)
        public let count: Int?
        /// For binary chunks: size in bytes
        public let size: Int?
        /// For file chunks: the file extension (e.g. "msg")
        public let fileExtension: String?
        /// For table chunks: symbol names of individual entries, keyed by
        /// entry index. Sparse — most entries have no symbol of their own.
        ///
        /// This is metadata about the table rather than a value in it, so it
        /// lives here rather than as a column in the CSV: a row's fields are
        /// the struct's fields and nothing else. (Keyed by a string because
        /// JSON object keys are strings.)
        public let entryLabels: [String: String]?

        public init(
            label: String,
            type: ChunkType,
            file: String,
            structType: String? = nil,
            countLabel: String? = nil,
            count: Int? = nil,
            size: Int? = nil,
            fileExtension: String? = nil,
            entryLabels: [String: String]? = nil
        ) {
            self.label = label
            self.type = type
            self.file = file
            self.structType = structType
            self.countLabel = countLabel
            self.count = count
            self.size = size
            self.fileExtension = fileExtension
            self.entryLabels = entryLabels
        }
    }

    public enum ChunkType: String, Codable, Equatable {
        /// A single struct instance with known type
        case `struct`
        /// A table of consecutive entries of the same type
        case table
        /// Assembly text with pointer labels (.4byte directives)
        case assembly
        /// Raw binary data with no labels
        case binary
        /// An embedded file with a custom extension (e.g. .msg)
        case file
    }
}

/// Manifest for a text section, listing files in order.
/// The ordering in the files array IS the processing order for assembly.
public struct TextSectionManifest: Codable, Equatable {
    /// Section name (e.g. "text0")
    public let section: String
    /// Ordered list of assembly file paths (relative to section folder)
    public var files: [String]

    public init(section: String, files: [String] = []) {
        self.section = section
        self.files = files
    }
}
