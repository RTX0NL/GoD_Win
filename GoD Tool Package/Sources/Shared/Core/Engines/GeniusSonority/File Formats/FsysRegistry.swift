import GoDFoundation
import GoDEngine
import Structs
import GTX

public struct FSYSRegistry: Codable {
    
    public struct Entry: Codable {
        public let metadata: FSYSArchive.Entry.MetaData
        public let file: File
        /// For GTX/ATX entries: texture metadata needed for re-encoding from PNG
        public let textureMetadata: GXTextureMetadata?

        public init(metadata: FSYSArchive.Entry.MetaData, file: File, textureMetadata: GXTextureMetadata? = nil) {
            self.metadata = metadata
            self.file = file
            self.textureMetadata = textureMetadata
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
