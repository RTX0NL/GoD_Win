import GoDFoundation
import GoDEngine
import Structs
import GTX

public struct FSYSRegistry: Codable {
    
    public struct Entry: Codable {
        public let metadata: FSYSArchive.Entry.MetaData
        public let file: File
        /// For GTX entries: texture metadata needed for re-encoding from PNG
        public let textureMetadata: GXTextureMetadata?
        /// For ATX entries: wrapper prefix + inner texture metadata for 1:1 rebuild from PNG
        public let atxMetadata: ATXMetadata?

        public init(
            metadata: FSYSArchive.Entry.MetaData,
            file: File,
            textureMetadata: GXTextureMetadata? = nil,
            atxMetadata: ATXMetadata? = nil
        ) {
            self.metadata = metadata
            self.file = file
            self.textureMetadata = textureMetadata
            self.atxMetadata = atxMetadata
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
