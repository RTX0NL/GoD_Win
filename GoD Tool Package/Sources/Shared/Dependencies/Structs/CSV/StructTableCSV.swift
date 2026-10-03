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
//  Padding is the one thing a zeroed buffer can get wrong, because it has
//  no column to carry it: a packer that fills its gaps with something other
//  than zero (Battle Revolution's table compiler writes `0xD0` in some runs
//  and zero in others) needs those bytes back, so `decode` takes the runs
//  and their fill byte. A run's fill is one value for the whole table — it
//  carries no information, which is exactly why it has no column and why
//  naming the value is enough.
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
        guard let bytes: GoDData = entry.data.read(atAddress: column.offset, length: column.length) else {
            throw StructCSVError.unreadableField(column: column.header, row: row, .init())
        }

        let type: StructProperty
        switch column.kind {
        case .bits(let layout, let field):
            guard let value = StructData.readBitField(
                field: field, layout: layout,
                from: entry.data, atOffset: column.offset, byteOrder: entry.byteOrder
            ) else {
                throw StructCSVError.unreadableField(column: column.header, row: row, .init())
            }
            switch field.value {
            case .boolean:
                return value != 0 ? "true" : "false"
            case .enumeration(let definition):
                // Same rule as a whole-field enum: an unnamed value is a
                // number, not a synthesized `Enum_<raw>` name.
                return definition.values.first(where: { $0.rawValue == value })?.name ?? String(value)
            case .unsigned, .signed:
                return String(value)
            }
        case .value(let valueType):
            type = valueType
        }

        if case .label = type {
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

        switch type {
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

        case .label, .subStruct, .padding, .bits:
            // `.label` returned above; the schema never emits a column for
            // a whole sub-struct, for padding, or for a bit container.
            throw StructCSVError.unreadableField(column: column.header, row: row, .init())
        }
    }

    /// Finite floats print in Swift's shortest form, which parses back to
    /// the same bits.
    ///
    /// Non-finite ones print as `NaN` / `Infinity` / `-Infinity`. The
    /// infinities are single exact bit patterns, so those spellings are
    /// lossless; `NaN` is only used for the canonical quiet NaN, because
    /// IEEE-754 gives NaN a 22-bit payload and a spelling can't carry one.
    /// A payload-bearing or signalling NaN falls back to its raw bit
    /// pattern — real data has float-typed fields that aren't really
    /// floats, and those bytes have to survive.
    ///
    /// Classification is done on the bits rather than via `isFinite` so a
    /// signalling NaN is never loaded into a floating-point register, which
    /// on some hardware quiets it.
    private static func floatCell(bits: UInt32) -> String {
        guard (bits >> 23) & 0xFF == 0xFF else {
            return String(describing: Float(bitPattern: bits))
        }
        switch bits {
        case 0x7F80_0000: return NonFiniteFloat.infinity.text
        case 0xFF80_0000: return NonFiniteFloat.negativeInfinity.text
        case 0x7FC0_0000: return NonFiniteFloat.nan.text   // Float.nan
        default: return "0x" + String(format: "%08X", bits)
        }
    }

    private static func doubleCell(bits: UInt64) -> String {
        guard (bits >> 52) & 0x7FF == 0x7FF else {
            return String(describing: Double(bitPattern: bits))
        }
        switch bits {
        case 0x7FF0_0000_0000_0000: return NonFiniteFloat.infinity.text
        case 0xFFF0_0000_0000_0000: return NonFiniteFloat.negativeInfinity.text
        case 0x7FF8_0000_0000_0000: return NonFiniteFloat.nan.text   // Double.nan
        default: return "0x" + String(format: "%016llX", bits)
        }
    }

    /// The three non-finite values that have a spelling, with the exact bit
    /// patterns they stand for.
    ///
    /// Parsed explicitly rather than leaning on `Float("NaN")`: that goes
    /// through the platform's `strtof`, whose handling of these spellings
    /// (and of `nan(0x...)` forms) varies, and this codec has to behave the
    /// same on every platform it builds for.
    enum NonFiniteFloat: CaseIterable {
        case nan, infinity, negativeInfinity

        var text: String {
            switch self {
            case .nan: return "NaN"
            case .infinity: return "Infinity"
            case .negativeInfinity: return "-Infinity"
            }
        }

        /// Spellings accepted on the way in, beyond `text` itself. Matching
        /// is case-insensitive.
        var accepted: [String] {
            switch self {
            case .nan: return ["nan"]
            case .infinity: return ["infinity", "inf", "+infinity", "+inf"]
            case .negativeInfinity: return ["-infinity", "-inf"]
            }
        }

        var floatBits: UInt32 {
            switch self {
            case .nan: return 0x7FC0_0000
            case .infinity: return 0x7F80_0000
            case .negativeInfinity: return 0xFF80_0000
            }
        }

        var doubleBits: UInt64 {
            switch self {
            case .nan: return 0x7FF8_0000_0000_0000
            case .infinity: return 0x7FF0_0000_0000_0000
            case .negativeInfinity: return 0xFFF0_0000_0000_0000
            }
        }

        static func parse(_ text: String) -> NonFiniteFloat? {
            let lowered = text.lowercased()
            return allCases.first { $0.accepted.contains(lowered) }
        }
    }

    // MARK: - Decoding

    /// - Parameter paddingFills: what to write over the record's padding
    ///   runs once a row is built. Padding has no column, so a rebuilt row is
    ///   zero there; a packer that fills its gaps with something else
    ///   (Battle Revolution's table compiler writes `0xD0` in some runs and
    ///   zero in others, per run) hands those runs over here. Empty leaves
    ///   every run zero.
    public static func decode(
        _ text: String,
        definition: StructDefinition,
        byteOrder: ByteOrder = .big,
        paddingFills: [StructPaddingFill] = []
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

        // A zero-filled run needs no writing: the row starts zeroed. A run
        // that doesn't fit this record isn't described by it — writing it
        // would grow the row and move every entry after it — so it is
        // dropped rather than applied.
        let fills = paddingFills.filter {
            $0.byte != 0 && $0.length > 0 && $0.offset >= 0 && $0.offset + $0.length <= definition.length
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
            for fill in fills {
                entry.data.write(
                    GoDData(byteStream: [UInt8](repeating: fill.byte, count: fill.length), byteOrder: byteOrder),
                    atAddress: UInt(fill.offset)
                )
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
            guard case .value(let type) = column.kind else { return }
            try StructData.writeValue(
                value,
                type: type,
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

        let type: StructProperty
        switch column.kind {
        case .bits(let layout, let field):
            // Blank leaves the bits as they are — a row starts zeroed, so
            // that is zero, exactly as an absent column elsewhere.
            guard !trimmed.isEmpty else { return }
            let value: Int
            switch field.value {
            case .boolean:
                guard let parsed = parseBool(trimmed) else { throw fail("true or false") }
                value = parsed ? 1 : 0
            case .enumeration(let definition):
                if let resolved = try? definition.get(trimmed) {
                    value = resolved.rawValue
                } else if let raw = parseInt(trimmed) {
                    value = raw
                } else {
                    throw fail("a case name of '\(definition.name)' or an integer")
                }
            case .unsigned, .signed:
                guard let parsed = parseInt(trimmed) else { throw fail("an integer") }
                value = parsed
            }
            try StructData.writeBitField(
                value,
                field: field,
                layout: layout,
                into: entry.data,
                atOffset: column.offset,
                byteOrder: entry.byteOrder
            )
            return
        case .value(let valueType):
            type = valueType
        }

        switch type {
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
                if let nonFinite = NonFiniteFloat.parse(trimmed) {
                    try writeBits(Int(nonFinite.floatBits), width: 4)
                } else if let bits = parseHex(trimmed) {
                    try writeBits(Int(bits & 0xFFFF_FFFF), width: 4)
                } else if let value = Float(trimmed) {
                    try writeBits(Int(value.bitPattern), width: 4)
                } else {
                    throw fail("a decimal number, NaN/Infinity/-Infinity, or an 0x bit pattern")
                }
            case .double, .lossless_double:
                guard !trimmed.isEmpty else { return }
                if let nonFinite = NonFiniteFloat.parse(trimmed) {
                    try writeBits(Int(bitPattern: UInt(nonFinite.doubleBits)), width: 8)
                } else if let bits = parseHex(trimmed) {
                    try writeBits(Int(bitPattern: UInt(bits)), width: 8)
                } else if let value = Double(trimmed) {
                    try writeBits(Int(bitPattern: UInt(value.bitPattern)), width: 8)
                } else {
                    throw fail("a decimal number, NaN/Infinity/-Infinity, or an 0x bit pattern")
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

        case .subStruct, .padding, .bits:
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
