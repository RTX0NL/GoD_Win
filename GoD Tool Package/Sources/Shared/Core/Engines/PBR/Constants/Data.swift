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

        /// `deck.fsys` table typing, keyed by the entry's FSYS file type.
        public var deckTables: [DeckTable] = Self.defaultDeckTables

        /// Struct describing the shared 0x10 `deck.fsys` header.
        public var deckHeaderStructName = "PBRDeckHeader"

        /// `common.fsys` member holding the string directory
        /// (`PBRStringDirectory`) on US and PAL discs.
        ///
        /// It sits past the 33 data tables and isn't one of them — it has
        /// no table header, just a dense array over the string ids — so it
        /// is named here rather than in `commonTables`.
        public var stringDirectoryIndex = 91

        /// The same member on a Japanese disc, which orders `common.fsys`
        /// differently. From the legacy tool's `PBRStringManager`.
        public var japaneseStringDirectoryIndex = 119

        /// Project filename of the string directory member on a disc of
        /// this order.
        ///
        /// The unpack names a nameless entry `<archive>_<index>.<ext>` with
        /// the index zero-padded to three digits, which is what this
        /// mirrors — `PBRStringDirectoryNamingTests` pins the two together
        /// so the convention can't drift out from under it.
        public func stringDirectoryFileName(japanese: Bool) -> String {
            let index = japanese ? japaneseStringDirectoryIndex : stringDirectoryIndex
            var digits = String(index)
            while digits.count < 3 { digits = "0" + digits }
            return "common_" + digits + ".bin"
        }

        /// Language codes a `MESG` table can declare, in the order a dump
        /// lists them. A code the disc carries but this doesn't name is
        /// still dumped — it sorts after these — so an unexpected build
        /// isn't silently dropped.
        public var stringLanguageCodes = ["USUK", "FRFR", "GRGR", "ITIT", "SPSP", "JPJP"]

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

        /// Byte the packer writes into alignment gaps *inside* an entry.
        ///
        /// Genius Sonority's table compiler fills intra-entry gaps with
        /// `0xD0` rather than zero — 14 of the 33 PAL tables contain such
        /// runs. That is load-bearing knowledge, not trivia: it's what
        /// separates a live-but-unidentified field from a hole, and several
        /// fields the legacy tool called "Unknown" are padding on this
        /// evidence (and one it called padding turned out to be a field).
        ///
        /// A rebuild has to re-emit it, or the output differs from the disc
        /// everywhere a struct declares padding — but not from this constant:
        /// the fill is per *run*, not per table (`PBRColosseum` has `0xD0` at
        /// +0x41 and zero at +0x44), so the dump measures each run and the
        /// registry carries it (`StructPaddingFill`). This says what the runs
        /// are allowed to hold, which is what the corpus guard checks them
        /// against.
        public var intraEntryPaddingByte = 0xD0

        /// Byte written *between* a table's regions to reach the next
        /// alignment boundary — pool → entries → name table → relocation
        /// list. Zero on every PAL table, i.e. deliberately not `0xD0`.
        public var interRegionPaddingByte = 0x00

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

    /// Binds a `deck.fsys` entry type to the struct describing one entry.
    /// Decks are addressed by FSYS file type (all `dckp` entries share a
    /// struct), not by index.
    struct DeckTable: Codable, Equatable {
        /// FSYS file type of the deck entries (`dckp`/`dckt`/`dcka`).
        public var fileType: String
        /// Registered struct describing a single deck entry.
        public var structName: String
        /// Entry stride observed on the PAL disc.
        public var entrySize: Int

        public init(fileType: String, structName: String, entrySize: Int) {
            self.fileType = fileType
            self.structName = structName
            self.entrySize = entrySize
        }
    }

    static let defaultDeckTables: [DeckTable] = [
        .init(fileType: "dckp", structName: "PBRPokemonDeck", entrySize: 0x38),
        .init(fileType: "dckt", structName: "PBRTrainerDeck", entrySize: 0x98),
        .init(fileType: "dcka", structName: "PBRAIDeck",      entrySize: 0x24),
    ]

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

        /// Struct describing an entry *on the Japanese disc*, when that
        /// build lays the table out differently. `nil` — the common case —
        /// means the JP disc uses the same record as US/PAL, which held for
        /// 29 of the JP disc's 32 tables when measured: `Countries` and
        /// `ColosseumsUnknown` drop a per-language array and are shorter,
        /// `PokemonStats` drops a field and is the *same* length, which is
        /// why a stride check alone can't find these.
        ///
        /// Optional so engines serialized before this existed still decode.
        public var japaneseStructName: String?

        /// Entry stride on the Japanese disc, paired with
        /// `japaneseStructName`. Both are set together or neither is.
        public var japaneseEntrySize: Int?

        public init(
            name: String,
            index: Int,
            japaneseIndex: Int?,
            structName: String?,
            entrySize: Int,
            japaneseStructName: String? = nil,
            japaneseEntrySize: Int? = nil
        ) {
            self.name = name
            self.index = index
            self.japaneseIndex = japaneseIndex
            self.structName = structName
            self.entrySize = entrySize
            self.japaneseStructName = japaneseStructName
            self.japaneseEntrySize = japaneseEntrySize
        }

        /// This descriptor with the region's record bound, so callers read
        /// `structName`/`entrySize` without repeating the region test — and
        /// so a table that only *some* builds lay out differently can't be
        /// half-resolved at a call site.
        public func resolved(japanese: Bool) -> CommonTable {
            guard japanese, let name = japaneseStructName, let size = japaneseEntrySize else {
                return self
            }
            var copy = self
            copy.structName = name
            copy.entrySize = size
            return copy
        }
    }
}
