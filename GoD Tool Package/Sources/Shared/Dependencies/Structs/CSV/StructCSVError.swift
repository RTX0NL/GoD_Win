//
//  StructCSVError.swift
//

import Foundation
import GoDFoundation

public enum StructCSVError: Error, CustomStringConvertible {
    /// The definition has no serializable leaves — every property is
    /// padding or void, so a row would carry nothing.
    case noColumns(structName: String, ErrorTrace)
    case missingHeaderRow(ErrorTrace)
    /// A field's bytes are missing or short — the entry data doesn't cover
    /// the definition.
    case unreadableField(column: String, row: Int, ErrorTrace)
    /// A `boolean` field holds a byte that is neither 0 nor 1, which means
    /// the definition and the data disagree. Writing it back as 0/1 would
    /// silently change the bytes, so it fails instead.
    case nonBooleanByte(column: String, row: Int, raw: UInt8, ErrorTrace)
    case invalidValue(column: String, row: Int, value: String, expected: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .noColumns(structName, errorTrace):
            return "Error: Struct '\(structName)' has no CSV columns — every property is padding or void.\n\(errorTrace)"
        case let .missingHeaderRow(errorTrace):
            return "Error: CSV table has no header row.\n\(errorTrace)"
        case let .unreadableField(column, row, errorTrace):
            return "Error: Couldn't read column '\(column)' of row \(row) — the entry data is shorter than the struct.\n\(errorTrace)"
        case let .nonBooleanByte(column, row, raw, errorTrace):
            return "Error: Column '\(column)' of row \(row) is declared boolean but holds "
                + "0x\(String(raw, radix: 16, uppercase: true)), which is neither 0 nor 1 — "
                + "the field is probably not a boolean.\n\(errorTrace)"
        case let .invalidValue(column, row, value, expected, errorTrace):
            return "Error: Column '\(column)' of row \(row) holds '\(value)'; expected \(expected).\n\(errorTrace)"
        }
    }
}
