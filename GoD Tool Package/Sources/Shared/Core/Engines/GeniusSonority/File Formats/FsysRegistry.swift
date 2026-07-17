import GoDFoundation
import GoDEngine
import Structs
import GTX

public struct FSYSRegistry: Codable {
    
    public struct Entry: Codable {
        /// For THP-pair entries, this is the THH metadata (the "primary"
        /// of the pair). `thdMetadata` below carries the THD sibling.
        public let metadata: FSYSArchive.Entry.MetaData
        public let file: File
        /// For GTX entries: texture metadata needed for re-encoding from PNG
        public let textureMetadata: GXTextureMetadata?
        /// For ATX entries: wrapper prefix + inner texture metadata for 1:1 rebuild from PNG
        public let atxMetadata: ATXMetadata?
        /// For THP-pair entries (THH + THD fused into one `.thp`): the
        /// THD sibling's FSYS metadata. Present only when `file` points
        /// at a combined `.thp`. On pack, the `.thp` is split back into
        /// THH + THD bytes and two FSYS entries are emitted using
        /// `metadata` and `thdMetadata` respectively.
        public let thdMetadata: FSYSArchive.Entry.MetaData?

        public init(
            metadata: FSYSArchive.Entry.MetaData,
            file: File,
            textureMetadata: GXTextureMetadata? = nil,
            atxMetadata: ATXMetadata? = nil,
            thdMetadata: FSYSArchive.Entry.MetaData? = nil
        ) {
            self.metadata = metadata
            self.file = file
            self.textureMetadata = textureMetadata
            self.atxMetadata = atxMetadata
            self.thdMetadata = thdMetadata
        }
    }
    
    public let groupID: Int
    public let metaData: FSYSArchive.MetaData
    public let entries: [Entry]
    
    public init(groupID: Int, metaData: FSYSArchive.MetaData, entries: [Entry]) {
        self.groupID = groupID
        self.metaData = metaData
        self.entries = entries
    }
}
