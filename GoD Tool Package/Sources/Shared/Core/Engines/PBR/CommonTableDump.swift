import Foundation
import GoDFoundation
import Structs

/// Decoding a `common.fsys` data table into its typed, editable form.
///
/// A table binary is `header + string pool + entry array + name table +
/// relocation table` (see `PBRCommonTableHeader`). The entry array is the
/// editable payload — it decodes to a `StructData` per row via the table's
/// bound entry struct, which serializes to CSV. The surrounding regions
/// (string pool, name/relocation tables) hold packed names and pointer
/// fixups that aren't derivable from the entries, so they're kept as raw
/// byte runs for a byte-exact rebuild.
public extension PBREngine {

    struct TypedCommonTable {
        public let table: Data.CommonTable
        /// The 0x30 container header, for round-tripping the geometry.
        public let header: StructData
        /// One decoded row per entry.
        public let entries: [StructData]
        public let entryDefinition: StructDefinition
        /// Bytes between the header and the entry array (string pool + its
        /// 0x10 padding). Nil when the table has no string pool.
        public let leadingExtra: GoDData?
        /// Bytes after the entry array's 0x10-aligned end (name table +
        /// relocation table). Nil when the table has no named entries.
        public let trailingExtra: GoDData?
    }

    enum CommonTableError: GoDError {
        case entryStrideMismatch(table: String, structName: String, structLength: Int, expected: Int, ErrorTrace = .init())
        case truncated(table: String, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .entryStrideMismatch(table, structName, structLength, expected, trace):
                return "Error: common table \(table): entry struct \(structName) is \(structLength) bytes "
                    + "but the disc header says \(expected). The struct can't tile the entry array.\n\(trace)"
            case let .truncated(table, trace):
                return "Error: common table \(table): file is shorter than its header describes.\n\(trace)"
            }
        }
    }

    /// Decode one `common.fsys` table binary. Returns nil for a table whose
    /// entry layout hasn't been documented (`structName == nil`) — the caller
    /// keeps those as raw `.bin`.
    func typeCommonTable(_ table: Data.CommonTable, binary: GoDData) throws -> TypedCommonTable? {
        guard let structName = table.structName else { return nil }
        binary.setByteOrder(.big)

        let format = data.commonTableFormat
        let headerDefinition = try getStruct(format.headerStructName)
        let entryDefinition = try getStruct(structName)

        guard entryDefinition.length == table.entrySize else {
            throw CommonTableError.entryStrideMismatch(
                table: table.name, structName: structName,
                structLength: entryDefinition.length, expected: table.entrySize
            )
        }

        guard let headerBytes = binary.read(atAddress: 0, length: headerDefinition.length) else {
            throw CommonTableError.truncated(table: table.name)
        }
        let header = StructData(definition: headerDefinition, data: headerBytes)

        guard let count: Int = header.get("entry_count"),
              let entriesOffset: Int = header.get("entries_offset") else {
            throw CommonTableError.truncated(table: table.name)
        }

        var entries = [StructData]()
        entries.reserveCapacity(count)
        for i in 0 ..< count {
            let offset = entriesOffset + i * entryDefinition.length
            guard let rowBytes = binary.read(atAddress: offset, length: entryDefinition.length) else {
                throw CommonTableError.truncated(table: table.name)
            }
            entries.append(StructData(definition: entryDefinition, data: rowBytes))
        }

        // String pool + its padding, between the header and the entry array.
        let leadingExtra = entriesOffset > headerDefinition.length
            ? binary.read(atAddress: headerDefinition.length, length: entriesOffset - headerDefinition.length)
            : nil

        // Name table + relocation table, after the entry array's aligned end.
        // The gap between the entries' true end and this aligned start is zero
        // padding (rederived on rebuild), so it isn't stored.
        let alignment = format.regionAlignment
        let entriesEnd = entriesOffset + count * entryDefinition.length
        let trailerStart = (entriesEnd + alignment - 1) / alignment * alignment
        let trailingExtra = binary.length > trailerStart
            ? binary.read(atAddress: trailerStart, length: binary.length - trailerStart)
            : nil

        return TypedCommonTable(
            table: table,
            header: header,
            entries: entries,
            entryDefinition: entryDefinition,
            leadingExtra: leadingExtra,
            trailingExtra: trailingExtra
        )
    }
}
