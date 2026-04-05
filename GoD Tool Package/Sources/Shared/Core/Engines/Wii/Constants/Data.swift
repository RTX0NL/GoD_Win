import GoDFoundation

public extension WiiEngine {
    struct Data: Codable {
        public private(set) var disc = Disc()
        public private(set) var partitionFiles = PartitionFiles()
    }
}
