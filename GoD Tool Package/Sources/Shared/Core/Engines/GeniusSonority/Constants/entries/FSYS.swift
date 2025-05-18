import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct FSYS: Codable {
        public private(set) var magicBytes = "FSYS"
        public internal(set) var fileMetaDataPadding = 0x40 // 0x20 in Colosseum but value is only aesthetic
        public private(set) var fileExtensionSuffixes = [
            "pool",
            "proj",
            "sdir"
        ]
        
        public private(set) var GSfsysFile = File("/files/GSfsys.toc")
    }
}
