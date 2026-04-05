import GoDFoundation

extension WiiEngine.Data {
    public struct PartitionFiles: Codable {
        public private(set) var systemFolder = Folder("/sys")
        public private(set) var filesFolder = Folder("/files")
        public private(set) var ticketFile = File("/sys/ticket.bin")
        public private(set) var tmdFile = File("/sys/tmd.bin")
        public private(set) var certFile = File("/sys/cert.bin")
        public private(set) var h3File = File("/sys/h3.bin")
        public private(set) var bootFile = File("/sys/boot.bin")
        public private(set) var bi2File = File("/sys/bi2.bin")
        public private(set) var apploaderFile = File("/sys/apploader.img")
        public private(set) var executableFile = File("/sys/main.dol")
        public private(set) var fstFile = File("/sys/fst.bin")
    }
}
