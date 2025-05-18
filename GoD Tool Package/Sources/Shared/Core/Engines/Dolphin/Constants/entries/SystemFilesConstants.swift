import GoDFoundation

extension DolphinEngine.Data {
    public struct SystemFiles: Codable {
        public private(set) var systemFolder = Folder("/sys")
        
        public private(set) var dolOffsetAlignment = 0x100
        public private(set) var executableFile = File("/sys/main.dol")
        
        public private(set) var fstOffsetMultiplier = 0x1
        public private(set) var fstFile = File("/sys/fst.bin")
        
        public private(set) var bootDataOffset = 0
        public private(set) var bootFile = File("/sys/boot.bin")
        
        public private(set) var bi2DataOffset = 0x440
        public private(set) var bi2File = File("/sys/bi2.bin")
        
        public private(set) var apploaderOffset = 0x2440
        public private(set) var apploaderFile = File("/sys/apploader.img")
        
        public private(set) var preserveJunkData = true
        public private(set) var junkFile = File("/sys/junk.bin")
    }
}
