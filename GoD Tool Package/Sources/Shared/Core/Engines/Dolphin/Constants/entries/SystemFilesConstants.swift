import GoDFoundation

extension DolphinEngine.Data {
    public struct SystemFiles: Codable {
        public private(set) var systemFolder = Folder("/sys")
        
        public private(set) var dolOffsetAlignment = 0x100
        /// Alignment of a section's offset *inside* the `.dol`. Every
        /// section of every retail Colosseum and XD build is already a
        /// multiple of 32 bytes long, so this changes nothing until an edit
        /// resizes one — at which point the sections after it would
        /// otherwise land at arbitrary offsets the apploader's DVD reads
        /// can't use.
        public private(set) var dolSectionAlignment = 0x20
        public private(set) var executableFile = File("/sys/main.dol")
        
        /// How a stored FST offset is scaled: 1 on GameCube, 4 on Wii
        /// (where the field holds the offset >> 2). Not an alignment — see
        /// `fstOffsetAlignment`.
        public private(set) var fstOffsetMultiplier = 0x1
        /// Where the FST may start on the disc. 0x100 reproduces retail
        /// exactly: `align(end of main.dol, 0x100)` is the FST offset on all
        /// five GameCube discs measured (Colosseum US/PAL/JP, XD US/JP),
        /// including the two that sit at 0x800 boundaries anyway.
        ///
        /// This used to be `fstOffsetMultiplier`, which is 1 on GameCube, so
        /// the FST landed wherever `main.dol` happened to end — an odd byte
        /// offset once a rebuilt DOL changed size.
        public private(set) var fstOffsetAlignment = 0x100
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
