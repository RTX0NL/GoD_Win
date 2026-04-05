import GoDFoundation

extension WiiEngine.Data {
    public struct Disc: Codable {
        public private(set) var partitionTableOffset = 0x40000
        public private(set) var maxDiscCapacity = 0x118240000
        public private(set) var fstOffsetMultiplier = 4
        public private(set) var dataGroupSize = 0x8000
        public private(set) var hashBlockSize = 0x400
        public private(set) var userDataPerGroup = 0x7C00
        public private(set) var wiiMagicWord: UInt32 = 0x5D1C9EA3
        public private(set) var wiiMagicWordOffset = 0x18
    }
}
