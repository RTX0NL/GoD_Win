//
//  CSVTests.swift
//
//  RFC 4180 dialect: quoting decided by content, doubled quotes, embedded
//  separators and line breaks, and the tolerances a hand-edited file needs
//  (CRLF, BOM, stray blank lines).
//

import XCTest
@testable import GoDFoundation

final class CSVTests: XCTestCase {

    // MARK: - Writing

    func testPlainFieldsAreNotQuoted() {
        XCTAssertEqual(CSV.encode(rows: [["a", "b"], ["1", "2"]]), "a,b\n1,2\n")
    }

    func testFieldsWithSeparatorsAreQuoted() {
        XCTAssertEqual(CSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.escape("line\nbreak"), "\"line\nbreak\"")
        XCTAssertEqual(CSV.escape("carriage\rreturn"), "\"carriage\rreturn\"")
    }

    func testFieldContainingCRLFIsQuoted() {
        // Swift clusters "\r\n" into one Character, so a naive membership
        // test against "\r" and "\n" alone misses it and emits a field that
        // silently splits the row on the way back in.
        XCTAssertEqual(CSV.escape("a\r\nb"), "\"a\r\nb\"")
    }

    func testEmbeddedQuotesAreDoubled() {
        XCTAssertEqual(CSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testSurroundingWhitespaceIsQuoted() {
        // So a value that deliberately carries it survives a reader that
        // trims unquoted cells.
        XCTAssertEqual(CSV.escape(" padded "), "\" padded \"")
        XCTAssertEqual(CSV.escape("inner space"), "inner space")
    }

    func testEmptyFieldsAndRows() {
        XCTAssertEqual(CSV.encode(rows: [["", ""]]), ",\n")
    }

    // MARK: - Reading

    func testParsesPlainRows() throws {
        XCTAssertEqual(try CSV.parse("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])
    }

    func testParsesWithoutTrailingNewline() throws {
        XCTAssertEqual(try CSV.parse("a,b\n1,2"), [["a", "b"], ["1", "2"]])
    }

    func testParsesQuotedFields() throws {
        XCTAssertEqual(try CSV.parse("\"a,b\",c\n"), [["a,b", "c"]])
        XCTAssertEqual(try CSV.parse("\"say \"\"hi\"\"\",c\n"), [["say \"hi\"", "c"]])
        XCTAssertEqual(try CSV.parse("\"two\nlines\",c\n"), [["two\nlines", "c"]])
    }

    func testQuotedFieldPreservesWhitespace() throws {
        XCTAssertEqual(try CSV.parse("\" padded \",x\n"), [[" padded ", "x"]])
    }

    func testAcceptsCRLFAndBareCR() throws {
        XCTAssertEqual(try CSV.parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(try CSV.parse("a,b\r1,2\r"), [["a", "b"], ["1", "2"]])
    }

    func testStripsByteOrderMark() throws {
        XCTAssertEqual(try CSV.parse("\u{FEFF}a,b\n"), [["a", "b"]])
    }

    func testDropsBlankLinesButKeepsEmptyFieldRows() throws {
        XCTAssertEqual(try CSV.parse("a,b\n\n1,2\n\n"), [["a", "b"], ["1", "2"]])
        // A row of empty fields is written `,` and is a real row.
        XCTAssertEqual(try CSV.parse("a,b\n,\n"), [["a", "b"], ["", ""]])
        // As is a single quoted empty field.
        XCTAssertEqual(try CSV.parse("a\n\"\"\n"), [["a"], [""]])
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try CSV.parse("a,\"unclosed\n")) { error in
            guard case CSV.Errors.unterminatedQuote = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Round trip

    func testRoundTripsAwkwardContent() throws {
        let rows = [
            ["name", "note"],
            ["comma,inside", "quote\"inside"],
            ["new\nline", " padded "],
            ["", "plain"],
        ]
        XCTAssertEqual(try CSV.parse(CSV.encode(rows: rows)), rows)
    }
}
