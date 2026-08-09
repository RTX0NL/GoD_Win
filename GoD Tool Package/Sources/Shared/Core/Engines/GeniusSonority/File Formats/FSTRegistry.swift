import GoDFoundation
import GoDEngine
import Structs

public struct FSTRegistry: Codable {
    public enum EntryType: String, Codable {
        case fsys
        case binary
        /// A Nintendo container — U8 (`.arc`) or NARC (`.narc`) — that was
        /// unpacked rather than copied. `file` points at its
        /// `NintendoArchiveRegistry` manifest, and the rebuild repacks the
        /// archive from that instead of writing bytes back verbatim.
        case nintendoArchive
    }

    public struct Entry: Codable {
        public let type: EntryType
        /// Where the dumped artifact lives in the project (the registry JSON
        /// for an `.fsys` or `.nintendoArchive` entry, the extracted bytes
        /// for a `.binary` one).
        public let file: File
        /// Path of the original file relative to the disc's `files/` folder,
        /// e.g. `subdir/thing.bin`. The project layout groups files by type
        /// and so loses the disc's own directory structure; this is what the
        /// rebuild puts back. Nil for registries dumped before this field
        /// existed, in which case the rebuild falls back to the bare
        /// filename (the old, flattening behavior).
        public let discPath: String?

        public init(type: EntryType, file: File, discPath: String? = nil) {
            self.type = type
            self.file = file
            self.discPath = discPath
        }

        /// Path to write this entry to under the rebuilt `files/` folder.
        public var rebuildPath: String {
            discPath ?? file.fileName
        }
    }
    
    public let entries: [Entry]
    
    public init(entries: [Entry]) {
        self.entries = entries
    }
}
