import GoDFoundation

extension DolphinEngine.Data {
    public struct UserFiles: Codable {
        public private(set) var userOffsetAlignment = 0x8000
        public private(set) var filesFolder = Folder("/files")
    }
}
