import Foundation

public extension GeniusSonorityEngine {
    struct Data: Codable {
        /// Which title this engine serves. Decides everything that varies by
        /// game rather than by region — most visibly which `.fnt` format the
        /// file-format registry binds.
        ///
        /// Optional storage so engines serialized before this existed still
        /// decode; those predate PBR support, so Gale of Darkness is the
        /// only safe assumption for them.
        public var game: GSGame {
            get { storedGame ?? .galeOfDarkness }
            set { storedGame = newValue }
        }
        internal var storedGame: GSGame?

        public internal(set) var fsys = FSYS()
        public internal(set) var lzss = LZSS()
        public internal(set) var toc = TOC()

        /// Backing store for `chunkTypeMapRoutes` (see ChunkTypeMaps.swift).
        /// Optional so an engine serialized before this property existed
        /// still decodes; the computed accessor presents it as an array.
        internal var storedChunkTypeMapRoutes: [ChunkTypeMapRoute]?

        enum CodingKeys: String, CodingKey {
            case fsys, lzss, toc
            case storedGame = "game"
            case storedChunkTypeMapRoutes = "chunkTypeMapRoutes"
        }
    }
}
