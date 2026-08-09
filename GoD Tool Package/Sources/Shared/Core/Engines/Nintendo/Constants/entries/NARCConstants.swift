import GoDFoundation

public extension NintendoEngine.Data {
    /// Knobs a NARC writer needs that aren't derivable from the entries.
    struct NARC: Codable {
        /// Each file's data starts on a multiple of this within FIMG.
        public var fileAlignment: Int = 4
        /// Written into the gaps that alignment leaves.
        public var paddingByte: UInt8 = 0x00
        /// Version word after the byte-order mark. `0x0100` everywhere seen.
        public var version: UInt16 = 0x0100
        /// Bytes ahead of the first section: magic, BOM, version, total
        /// size, header length, section count.
        public let headerLength: Int = 0x10
        /// The byte-order mark as stored — always the same two bytes; which
        /// end they read from is what the magic's spelling already told us.
        public let byteOrderMark: UInt16 = 0xFFFE

        public init() {}
    }
}
