import GoDFoundation
import GoDEngine
import Structs

public struct FSYSRegistry: Codable {
    
    public struct Entry: Codable {
        public let metadata: FSYSArchive.Entry.MetaData
        public let file: File
        
        public init(metadata: FSYSArchive.Entry.MetaData, file: File) {
            self.metadata = metadata
            self.file = file
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
