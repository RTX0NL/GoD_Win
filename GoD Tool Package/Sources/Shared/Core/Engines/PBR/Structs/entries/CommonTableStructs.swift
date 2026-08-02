import Foundation
import Structs

/// The container format shared by every `common.fsys` data table.
///
/// A table file is laid out as:
///
/// ```
/// 0x00  header                    (0x30 bytes, PBRCommonTableHeader)
/// 0x30  string pool               (string_pool_size bytes, padded to 0x10)
///       entry array               (entry_count × entry_size)
///       name table                (relocation_table_count × PBRCommonTableNameRecord)
///       relocation table          (relocation_table_count × u32) → end of file
/// ```
///
/// The string pool holds packed `PBRCommonTableStringHeader` records — a
/// 16-bit hash followed by a NUL-terminated ASCII name. The name table maps
/// those names to entry indexes and is sorted ascending by hash, so the game
/// can find an entry by name with a binary search. Tables with no named
/// entries have an empty string pool and no name/relocation regions.
///
/// Every field below was verified against all 33 tables of the PAL disc
/// (RPBP01): `entries_size == entry_count × entry_size`,
/// `entries_offset == align16(string_pool_offset + string_pool_size)`,
/// `name_table_offset == align16(entries_offset + entries_size)` (or 0 when
/// there is no name table), and
/// `relocation_table_offset + relocation_table_count × 4 == file size`.
public extension PBRStructDefaults {

    /// Leading 0x30-byte header of a `common.fsys` data table.
    static let commonTableHeaderStruct = StructMap(
        name: "PBRCommonTableHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Number of entries in the entry array.
            .uint32(name: "entry_count"),

            // 0x04: Stride of one entry, in bytes.
            .uint32(name: "entry_size"),

            // 0x08: Offset of the string pool. Always 0x30 — i.e. the pool
            // starts immediately after this header — on all 33 tables.
            .uint32(name: "string_pool_offset"),

            // 0x0C: Byte length of the string pool, unpadded. 0 when the
            // table has no named entries.
            .uint32(name: "string_pool_size"),

            // 0x10: Offset of the entry array — the string pool's end
            // rounded up to 0x10.
            .uint32(name: "entries_offset"),

            // 0x14: Byte length of the entry array (entry_count × entry_size).
            .uint32(name: "entries_size"),

            // 0x18: Offset of the trailing relocation table. When the table
            // has no named entries this is the (0x10-aligned) end of the
            // entry array, which is also the file size.
            .uint32(name: "relocation_table_offset"),

            // 0x1C: Number of 4-byte words in the relocation table. Equal to
            // the number of name-table records, since the name records'
            // `name_offset` fields are the only pointers in the file.
            .uint32(name: "relocation_table_count"),

            // 0x20: Offset of the name table — the entry array's end rounded
            // up to 0x10. Zero when there are no named entries.
            .uint32(name: "name_table_offset"),

            // 0x24: Unused. Zero on every table of the PAL disc.
            .padding(length: 12)
        ],
        description: "Header of a common.fsys data table: entry array geometry plus the optional name-lookup regions. Verified against all 33 tables of the PAL disc."
    )

    /// One record of a table's name table: name → entry index.
    /// Records are sorted ascending by the 16-bit hash their `name_offset`
    /// points at, which is what makes name lookup a binary search.
    static let commonTableNameRecordStruct = StructMap(
        name: "PBRCommonTableNameRecord",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Offset of this entry's string-pool record, from the
            // start of the file. This is the word the relocation table
            // points at — the game fixes it up to a RAM pointer on load.
            .uint32(name: "name_offset"),

            // 0x04: Index into the table's entry array.
            .uint32(name: "entry_index"),
        ],
        description: "Maps a name-pool record to an entry index. Sorted by name hash for binary search."
    )

    /// Fixed part of a string-pool record. A NUL-terminated ASCII name
    /// follows immediately and runs to the next record with no padding, so
    /// only the hash can be modelled as a fixed-size struct.
    ///
    /// Real pools hold names like `TOKUSEI_012` (abilities), `bf_00`
    /// (battlefields), `NOKOTTI` (Pokémon), `NormalGirl` (trainer events).
    static let commonTableStringHeaderStruct = StructMap(
        name: "PBRCommonTableStringHeader",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: 16-bit hash of the name that follows. The name table is
            // sorted on this value.
            .uint16(name: "name_hash"),
        ],
        description: "Header of a string-pool record — a 16-bit name hash followed by a NUL-terminated name."
    )

    /// One word of a table's trailing relocation table: the file offset of
    /// a word that holds a file-relative offset and is fixed up to a RAM
    /// pointer when the table loads. In practice each points at a name
    /// record's `name_offset` field, so the count matches the name-record
    /// count on every table.
    static let commonTableRelocationStruct = StructMap(
        name: "PBRCommonTableRelocation",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: File offset of a word holding a file-relative offset.
            .uint32(name: "pointer_field_offset"),
        ],
        description: "Trailing relocation word: the offset of a field the loader converts from a file offset to a RAM pointer."
    )
}
