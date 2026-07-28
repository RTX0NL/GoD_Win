import GoDFoundation

extension WiiEngine.Data {
    public struct PartitionFiles: Codable {
        public private(set) var systemFolder = Folder("/sys")
        public private(set) var filesFolder = Folder("/files")
        // ticket/tmd/cert/h3 sit at the partition root (not under /sys) so the
        // extracted tree matches Dolphin's DirectoryBlob layout and can be
        // booted directly as a folder. Dolphin finds the title key in the
        // partition-root ticket.bin; under /sys it can't and won't boot.
        public private(set) var ticketFile = File("/ticket.bin")
        public private(set) var tmdFile = File("/tmd.bin")
        public private(set) var certFile = File("/cert.bin")
        public private(set) var h3File = File("/h3.bin")
        public private(set) var bootFile = File("/sys/boot.bin")
        public private(set) var bi2File = File("/sys/bi2.bin")
        public private(set) var apploaderFile = File("/sys/apploader.img")
        public private(set) var executableFile = File("/sys/main.dol")
        public private(set) var fstFile = File("/sys/fst.bin")
    }
}
