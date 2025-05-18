import Foundation

public extension GeniusSonorityEngine {
    struct Data: Codable {
        public internal(set) var fsys = FSYS()
        public internal(set) var lzss = LZSS()
    }
}
