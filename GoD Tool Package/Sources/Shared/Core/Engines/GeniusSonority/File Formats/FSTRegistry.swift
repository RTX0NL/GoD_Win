import GoDFoundation
import GoDEngine
import Structs

public struct FSTRegistry: Codable {
    public enum EntryType: String, Codable {
        case fsys
        case binary
    }
    
    public struct Entry: Codable {
        public let type: EntryType
        public let file: File
        
        public init(type: EntryType, file: File) {
            self.type = type
            self.file = file
        }
    }
    
    public let entries: [Entry]
    
    public init(entries: [Entry]) {
        self.entries = entries
    }
}
