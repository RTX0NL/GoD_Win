//
//  StructTableCSV.swift
//
//  A table of struct entries as CSV: one header row of flattened property
//  paths (`StructCSVSchema`), then one row per entry.
//
//  Values are the *abstracted* form — an enum field is its case name, not
//  its index; a bool is true/false; a pointer is its label name. A raw
//  value the enum doesn't name falls back to the integer rather than a
//  synthesized `Enum_<raw>` name, because in CSV every cell is text and a
//  synthesized name would have to be told apart from a real one by
//  reconstructing the enum's current name.
//
//  Decoding builds each entry from scratch in a zeroed buffer: the CSV and
//  the definition are together sufficient, nothing is read back from the
//  original binary, and a column that is absent or blank simply leaves its
//  bytes zero. Columns are matched by header, not by position, so a file
//  can be reordered or partially filled.
//

import Foundation
import GoDFoundation

public enum StructTableCSV {

    public struct DecodeResult {
        public let entries: [StructData]
        /// Recoverable oddities — unknown/missing/duplicate columns, short
        /// rows. The caller decides how loudly to report them.
        public let warnings: [String]
    }

    // MARK: - Encoding

    public static func encode(table: StructTableData) throws -> String {
        let entries = (0 ..< table.count).compactMap { table.get(index: $0) }
        return try encode(entries: entries, definition: table.definition)
    }

    public static func encode(entries: [StructData], definition: StructDefinition) throws -> String {
        let columns = StructCSVSchema.columns(of: definition)
        guard !columns.isEmpty else {
            throw StructCSVError.noColumns(structName: definition.name, .init())
        }

        var rows = [columns.map(\.header)]
        for (index, entry) in entries.enumerated() {
            rows.append(try columns.map { try cell(for: $0, of: entry, row: index + 1) })
        }
        return CSV.encode(rows: rows)
    }

    private static func cell(
        for column: StructCSVColumn,
        of entry: StructData,
        row: Int
    ) throws -> String {
        guard let bytes: GoDData = entry.data.read(atAddress: column.offset, length: column.type.length) else {
            throw StructCSVError.unreadableField(column: column.header, row: row, .init())
        }

        if case .label = column.type {
            if let name = entry.labelValues[column.labelKey ?? column.header] {
                return name
            }
            // No recorded name — fall back to the raw pointer under the
            // auto-generated naming convention, so a pointer is never
            // silently dropped. (`TypedDataExporter` only records names for
            // top-level label properties, not for elements of label arrays.)
            let address = StructData.readInteger(
                from: bytes, width: 4, signed: false, byteOrder: bytes.byteOrder
            ) ?? 0
            return address == 0 ? "" : "lbl_" + String(format: "%08X", UInt32(truncatingIfNeeded: address))
        }

        func integer(width: Int, signed: Bool) throws -> Int {
            guard let value = StructData.readInteger(
                from: bytes, width: width, signed: signed, byteOrder: bytes.byteOrder
            ) else {
                throw StructCSVError.unreadableField(column: column.header, row: row, .init())
            }
            return value
        }

        switch column.type {
        case .enumeration(let definition):
            let raw = try integer(
                width: definition.propertyType.length,
                signed: definition.propertyType.isSigned
            )
            // Deliberately not `definition.get(raw)`: that synthesizes an
            // `Enum_<raw>` name for `allowUnknownCases` enums, and an
            // unnamed value is a number, not an abstraction.
            return definition.values.first(where: { $0.rawValue == raw })?.name ?? String(raw)

        case .primitive(let primitive):
            switch primitive {
            case .void:
                return ""
            case .integer(let subType):
                return String(try integer(width: subType.length, signed: subType.isSigned))
            case .float, .lossless_float:
                return floatCell(bits: UInt32(truncatingIfNeeded: try integer(width: 4, signed: false)))
            case .double, .lossless_double:
                return doubleCell(bits: UInt64(bitPattern: Int64(try integer(width: 8, signed: false))))
            case .boolean:
                switch bytes.rawBytes.first ?? 0 {
                case 0: return "false"
                case 1: return "true"
                case let raw:
                    throw StructCSVError.nonBooleanByte(column: column.header, row: row, raw: raw, .init())
                }
            case .character(let format):
                return bytes.readString(atAddress: 0, format: format, maxCharacters: 1) ?? ""
            }

        case .array(let element, let count):
            guard case .primitive(.character(let format)) = element else {
                // The schema only ever emits a whole array as one column
                // when its elements are characters.
                throw StructCSVError.unreadableField(column: column.header, row: row, .init())
            }
            return bytes.readString(atAddress: 0, format: format, maxCharacters: count) ?? ""

        case .label, .subStruct, .padding:
            // `.label` returned above; the schema never emits a column for
            // a whole sub-struct or for padding.
            throw StructCSVError.unreadableField(column: column.header, row: row, .init())
        }
    }

    /// Finite floats print in Swift's shortest form, which parses back to
    /// the same bits. Non-finite ones print as their raw bit pattern: a NaN
    /// carries a payload that `Float("NaN")` would discard, and real data
    /// has plenty of float-typed fields that aren't really floats.
    private static func floatCell(bits: UInt32) -> String {
        let value = Float(bitPattern: bits)
        guard value.isFinite else { return "0x" + String(format: "%08X", bits) }
        return String(describing: value)
    }

    private static func doubleCell(bits: UInt64) -> String {
        let value = Double(bitPattern: bits)
        guard value.isFinite else { return "0x" + String(format: "%016llX", bits) }
        return String(describing: value)
    }

    // MARK: - Decoding

    public static func decode(
        _ text: String,
        definition: StructDefinition,
        byteOrder: ByteOrder = .big
    ) throws -> DecodeResult {
        let columns = StructCSVSchema.columns(of: definition)
        guard !columns.isEmpty else {
            throw StructCSVError.noColumns(structName: definition.name, .init())
        }

        let rows = try CSV.parse(text)
        guard let header = rows.first else {
            throw StructCSVError.missingHeaderRow(.init())
        }

        var warnings = [String]()
        let columnsByHeader = Dictionary(
            columns.map { ($0.header, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Header order is the file's, not the definition's — a hand-edited
        // file may reorder, drop or add columns.
        var mapping = [(index: Int, column: StructCSVColumn)]()
        var matched = Set<String>()
        for (index, rawName) in header.enumerated() {
            let name = rawName.trimmingCharacters(in: .whitespaces)
            guard let column = columnsByHeader[name] else {
                warnings.append("Unknown column '\(name)' ignored — '\(definition.name)' has no such field.")
                continue
            }
            guard !matched.contains(name) else {
                warnings.append("Column '\(name)' appears more than once; only the first is read.")
                continue
            }
            matched.insert(name)
            mapping.append((index, column))
        }

        let missing = columns.map(\.header).filter { !matched.contains($0) }
        if !missing.isEmpty {
            warnings.append(
                "\(missing.count) column(s) absent from the file; those fields are left zero: "
                + missing.prefix(10).joined(separator: ", ")
                + (missing.count > 10 ? ", …" : "")
            )
        }

        var entries = [StructData]()
        for (rowIndex, row) in rows.dropFirst().enumerated() {
            let rowNumber = rowIndex + 1
            if row.count != header.count {
                warnings.append(
                    "Row \(rowNumber) has \(row.count) field(s), header has \(header.count)."
                    + (row.count < header.count ? " Missing fields left zero." : " Extra fields ignored.")
                )
            }
            let entry = StructData(definition: definition, byteOrder: byteOrder)
            for (index, column) in mapping where index < row.count {
                try write(cell: row[index], column: column, into: entry, row: rowNumber)
            }
            entries.append(entry)
        }

        return DecodeResult(entries: entries, warnings: warnings)
    }

    private static func write(
        cell: String,
        column: StructCSVColumn,
        into entry: StructData,
        row: Int
    ) throws {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)

        func fail(_ expected: String) -> StructCSVError {
            .invalidValue(column: column.header, row: row, value: cell, expected: expected, .init())
        }

        // Everything else routes through `StructData.writeValue`, so the
        // byte-level rules live in one place.
        func writeValue(_ value: Any) throws {
            try StructData.writeValue(
                value,
                type: column.type,
                propertyName: column.header,
                into: entry.data,
                atOffset: column.offset,
                labelValues: &entry.labelValues,
                byteOrder: entry.byteOrder
            )
        }

        /// Writes a float/double cell given as a raw bit pattern.
        func writeBits(_ bits: Int, width: Int) throws {
            try StructData.writeInteger(
                bits, width: width, signed: false,
                into: entry.data, atOffset: column.offset, byteOrder: entry.byteOrder
            )
        }

        switch column.type {
        case .label:
            guard !trimmed.isEmpty else { return }
            entry.labelValues[column.labelKey ?? column.header] = trimmed

        case .enumeration(let definition):
            guard !trimmed.isEmpty else { return }
            // A named case (or the legacy `Enum_<raw>` shape, which `get`
            // still parses) wins; otherwise the cell is a raw value.
            if (try? definition.get(trimmed)) != nil {
                try writeValue(trimmed)
            } else if let raw = parseInt(trimmed) {
                try writeValue(raw)
            } else {
                throw fail("a case name of '\(definition.name)' or an integer")
            }

        case .primitive(let primitive):
            switch primitive {
            case .void:
                return
            case .integer:
                guard !trimmed.isEmpty else { return }
                guard let value = parseInt(trimmed) else { throw fail("an integer") }
                try writeValue(value)
            case .float, .lossless_float:
                guard !trimmed.isEmpty else { return }
                if let bits = parseHex(trimmed) {
                    try writeBits(Int(bits & 0xFFFF_FFFF), width: 4)
                } else if let value = Float(trimmed) {
                    try writeBits(Int(value.bitPattern), width: 4)
                } else {
                    throw fail("a decimal number or an 0x bit pattern")
                }
            case .double, .lossless_double:
                guard !trimmed.isEmpty else { return }
                if let bits = parseHex(trimmed) {
                    try writeBits(Int(bitPattern: UInt(bits)), width: 8)
                } else if let value = Double(trimmed) {
                    try writeBits(Int(bitPattern: UInt(value.bitPattern)), width: 8)
                } else {
                    throw fail("a decimal number or an 0x bit pattern")
                }
            case .boolean:
                guard !trimmed.isEmpty else { return }
                guard let value = parseBool(trimmed) else { throw fail("true or false") }
                try writeValue(value)
            case .character:
                // Strings keep their exact content, including any padding
                // the author typed deliberately.
                try writeValue(cell)
            }

        case .array:
            // Only character arrays reach here (see the schema).
            try writeValue(cell)

        case .subStruct, .padding:
            return
        }
    }

    // MARK: - Cell parsing

    /// Decimal or `0x` hex, optionally signed. Booleans are accepted too,
    /// so a field retyped from `boolean` to an integer still reads.
    static func parseInt(_ text: String) -> Int? {
        if let boolean = parseBool(text) { return boolean ? 1 : 0 }
        var body = text
        var negative = false
        if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }
        let magnitude: Int?
        if body.lowercased().hasPrefix("0x") {
            magnitude = Int(body.dropFirst(2), radix: 16)
        } else {
            magnitude = Int(body)
        }
        guard let value = magnitude else { return nil }
        return negative ? -value : value
    }

    /// An unsigned `0x` literal, used for float bit patterns.
    static func parseHex(_ text: String) -> UInt64? {
        guard text.lowercased().hasPrefix("0x") else { return nil }
        return UInt64(text.dropFirst(2), radix: 16)
    }

    static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
}
