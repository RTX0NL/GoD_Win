import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct LZSS: Codable {
        public private(set) var magicBytes = "LZSS"

        /// Whether the packer fills in the header's CRC-32 of the
        /// uncompressed payload. Battle Revolution does; Colosseum and XD
        /// leave the field zero. Optional so an engine folder serialized
        /// before this existed still decodes; nil reads as false.
        public internal(set) var storedWritesUncompressedChecksum: Bool?

        /// The effective flag, defaulting to the Colo/XD behaviour.
        public var writesUncompressedChecksum: Bool {
            get { storedWritesUncompressedChecksum ?? false }
            set { storedWritesUncompressedChecksum = newValue }
        }

        enum CodingKeys: String, CodingKey {
            case magicBytes
            case storedWritesUncompressedChecksum = "writesUncompressedChecksum"
        }
    }
}
