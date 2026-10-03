//
//  CSV.swift
//
//  RFC 4180 reader/writer. Deliberately dialect-faithful: a field is
//  preserved byte for byte, and quoting is decided by content rather than
//  by the caller. Nothing here knows what the cells mean.
//

import Foundation

public enum CSV {

    public enum Errors: Error, CustomStringConvertible {
        case unterminatedQuote(row: Int, ErrorTrace)

        public var description: String {
            switch self {
            case let .unterminatedQuote(row, errorTrace):
                return "Error: CSV row \(row) opens a quoted field that is never closed.\n\(errorTrace)"
            }
        }
    }

    /// Characters that force a field to be quoted. `\r\n` is listed as well
    /// as its halves because Swift clusters it into a single Character, so
    /// matching only `\r` and `\n` would miss it. Leading/trailing
    /// whitespace is handled separately, so a value that deliberately
    /// carries it survives a reader that trims unquoted cells.
    private static let mustQuote: Set<Character> = [",", "\"", "\n", "\r", "\r\n"]

    // MARK: - Writing

    /// Renders rows as CSV text, terminated by a final newline.
    ///
    /// Rows are emitted as given — this does not pad short rows or check
    /// that they agree on width. A field is quoted when it contains a
    /// comma, a quote, a line break, or leading/trailing whitespace;
    /// embedded quotes are doubled.
    public static func encode(rows: [[String]]) -> String {
        var out = ""
        for row in rows {
            // A one-field row holding nothing would be a blank line, which
            // the reader drops; `""` is the same row spelled so it survives.
            out += row == [""] ? "\"\"" : row.map(escape).joined(separator: ",")
            out += "\n"
        }
        return out
    }

    public static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(where: { mustQuote.contains($0) })
            || field.first?.isWhitespace == true
            || field.last?.isWhitespace == true
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Reading

    /// Parses CSV text into rows of fields.
    ///
    /// Accepts `\n`, `\r\n` and bare `\r` line breaks and a leading UTF-8
    /// BOM. Quoted fields may contain commas, line breaks and doubled
    /// quotes. Entirely blank lines are dropped — a row of empty *fields*
    /// is written `,,,` and survives, so nothing meaningful is lost, and
    /// hand-edited files routinely pick up stray blank lines.
    public static func parse(_ text: String) throws -> [[String]] {
        var rows = [[String]]()
        var row = [String]()
        var field = ""
        var inQuotes = false
        // Whether the current line held any character at all. A truly blank
        // line has none and is dropped; `,` (two empty fields) and `""` (one
        // empty field) both do, so they survive as rows.
        var lineHasContent = false

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            if lineHasContent {
                endField()
                rows.append(row)
            }
            row = []
            lineHasContent = false
        }

        var iterator = text.drop(while: { $0 == "\u{FEFF}" }).makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    // Either an escaped quote ("") or the end of the field.
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                lineHasContent = true
            case ",":
                endField()
                lineHasContent = true
            // Swift clusters CRLF into a single Character, so it has to be
            // matched as one — `"\r"` alone never sees it.
            case "\n", "\r", "\r\n":
                endRow()
            default:
                field.append(character)
                lineHasContent = true
            }
        }

        guard !inQuotes else {
            throw Errors.unterminatedQuote(row: rows.count + 1, .init())
        }
        endRow()
        return rows
    }
}
