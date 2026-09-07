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
        /// The engine's own descriptor and struct disagree — a definition bug,
        /// independent of any disc.
        case declaredStrideMismatch(table: String, structName: String, structLength: Int, declared: Int, ErrorTrace = .init())
        /// The struct doesn't match *this* disc. Usually a regional layout
        /// difference rather than a mistake.
        case entryStrideMismatch(table: String, structName: String, structLength: Int, expected: Int, ErrorTrace = .init())
        case truncated(table: String, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .declaredStrideMismatch(table, structName, structLength, declared, trace):
                return "Error: common table \(table): entry struct \(structName) is \(structLength) bytes "
                    + "but the table descriptor declares \(declared). The struct can't tile the entry array.\n\(trace)"
            case let .entryStrideMismatch(table, structName, structLength, expected, trace):
                return "Error: common table \(table): entry struct \(structName) is \(structLength) bytes "
                    + "but this disc's table header says \(expected). The struct describes a different "
                    + "build of this table.\n\(trace)"
            case let .truncated(table, trace):
                return "Error: common table \(table): file is shorter than its header describes.\n\(trace)"
            }
        }
    }

    /// Decode one `common.fsys` table binary. Returns nil for a table whose
    /// entry layout hasn't been documented (`structName == nil`) — the caller
    /// keeps those as raw `.bin`.
    ///
    /// - Parameter structs: the engine the entry struct resolves against.
    ///   Supplied rather than taken as `self` because these tables are a
    ///   *mapping* surface: an entry struct names a species, move or item
    ///   enum that lives in the Pokemon engine, and `getStruct` only ever
    ///   consults one engine's own enums. Callers pass a `GenericEngine`
    ///   combining this one with whatever else the definitions reference.
    func typeCommonTable(
        _ table: Data.CommonTable,
        binary: GoDData,
        structs: any Engine
    ) throws -> TypedCommonTable? {
        guard let structName = table.structName else { return nil }
        binary.setByteOrder(.big)

        let format = data.commonTableFormat
        let headerDefinition = try structs.getStruct(format.headerStructName)
        let entryDefinition = try structs.getStruct(structName)

        guard entryDefinition.length == table.entrySize else {
            throw CommonTableError.declaredStrideMismatch(
                table: table.name, structName: structName,
                structLength: entryDefinition.length, declared: table.entrySize
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

        // The table states its own stride, so a struct that disagrees is a
        // wrong layout — not a short file. Checking it here means a regional
        // divergence reports as the mismatch it is; without this the entry
        // walk below simply runs off the end and blames truncation. (The JP
        // disc's `Countries` is 0x6C to US/PAL's 0x76, and `TutorialData`
        // 0x3A to 0x1C — see the region-specific table entries.)
        if let discStride: Int = header.get("entry_size"), discStride != entryDefinition.length {
            throw CommonTableError.entryStrideMismatch(
                table: table.name, structName: structName,
                structLength: entryDefinition.length, expected: discStride
            )
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

        // Name table + relocation table, whose start the header records
        // directly (the entry array's aligned end). The padding between the
        // entries' true end and this start is rederived on rebuild, so it
        // isn't stored.
        let nameTableOffset: Int = header.get("name_table_offset") ?? 0
        let relocationOffset: Int = header.get("relocation_table_offset") ?? binary.length
        let trailerStart = nameTableOffset > 0 ? nameTableOffset : relocationOffset
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
