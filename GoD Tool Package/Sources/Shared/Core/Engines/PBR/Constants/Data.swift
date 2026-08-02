import GoDFoundation
import GoDEngine

public extension PBREngine {
    struct Data: Codable {
        /// Layout constants shared by every `common.fsys` data table.
        public var commonTableFormat = CommonTableFormat()

        /// One descriptor per `common.fsys` member, in US/PAL file order.
        /// Binds each table to the struct that describes a single entry so
        /// a dump can type its rows without hardcoding the mapping.
        public var commonTables: [CommonTable] = Self.defaultCommonTables

        public init() {}
    }
}

public extension PBREngine.Data {

    /// Fixed layout of the container format every `common.fsys` member
    /// uses. Verified against all 33 tables of the PAL disc (RPBP01).
    struct CommonTableFormat: Codable, Equatable {
        /// Bytes of header before the first data region. Always 0x30, and
        /// every table's `string_pool_offset` field holds exactly this.
        public var headerSize = 0x30

        /// Regions inside a table are padded up to a multiple of this.
        /// `entries_offset == align(string_pool_offset + string_pool_size)`
        /// and `name_table_offset == align(entries_offset + entries_size)`
        /// hold on all 33 tables.
        public var regionAlignment = 0x10

        /// Registered struct describing the leading header.
        public var headerStructName = "PBRCommonTableHeader"

        /// Registered struct describing one record of the name table
        /// (the region between the entry array and the relocation table).
        public var nameRecordStructName = "PBRCommonTableNameRecord"

        /// Registered struct describing the fixed part of a string-pool
        /// record. The record's name is a variable-length NUL-terminated
        /// string that follows, so only the hash is modelled.
        public var stringRecordStructName = "PBRCommonTableStringHeader"

        /// Registered struct describing one word of the trailing
        /// relocation table.
        public var relocationStructName = "PBRCommonTableRelocation"

        public init() {}
    }

    /// Describes one member of `common.fsys`.
    struct CommonTable: Codable, Equatable {
        /// Canonical table name. Matches the `PBRCommonTableIndex` case.
        public var name: String

        /// File index within `common.fsys` on US and PAL discs.
        public var index: Int

        /// File index on Japanese discs, or `nil` if the table is absent
        /// there. The JP disc ships the same tables in a different order.
        public var japaneseIndex: Int?

        /// Registered struct describing a single entry, or `nil` if the
        /// layout hasn't been documented yet.
        public var structName: String?

        /// Entry stride observed on the PAL disc. A table whose bound
        /// struct doesn't match this length can't tile its entry array,
        /// which is what `PBRCommonTableStructTests` pins.
        public var entrySize: Int

        public init(
            name: String,
            index: Int,
            japaneseIndex: Int?,
            structName: String?,
            entrySize: Int
        ) {
            self.name = name
            self.index = index
            self.japaneseIndex = japaneseIndex
            self.structName = structName
            self.entrySize = entrySize
        }
    }
}
