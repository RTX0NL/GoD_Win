import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct TOC: Codable {
        public internal(set) var magicBytes = "GLLA"
        public internal(set) var unknown = 0
        public internal(set) var padding: Int?
        public internal(set) var junk1: Int?
        public internal(set) var junk2: Int?
        public internal(set) var junk3: Int?
    }
}
