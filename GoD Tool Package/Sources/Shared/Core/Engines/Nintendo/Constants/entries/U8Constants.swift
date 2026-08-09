import GoDFoundation

public extension NintendoEngine.Data {
    /// Knobs a U8 writer needs that aren't derivable from the entries.
    ///
    /// Measured on Battle Revolution's `.arc` files, whose geometry is
    /// fully determined by these two values plus the entry list — see
    /// `Documentation/File Formats/Shared/U8 - Nintendo Archive.md`.
    struct U8: Codable {
        /// File data starts on a multiple of this, and the data region
        /// itself begins at the first such boundary after the node and
        /// string tables.
        public var dataAlignment: Int = 0x20
        /// Written into the gaps that alignment leaves.
        public var paddingByte: UInt8 = 0x00
        /// Byte count of one node record: type + name offset packed into a
        /// word, then data offset and size.
        public let nodeLength: Int = 12
        /// Bytes ahead of the root node: magic, root offset, header size,
        /// data offset, then a reserved run.
        public let headerLength: Int = 0x20

        public init() {}
    }
}
