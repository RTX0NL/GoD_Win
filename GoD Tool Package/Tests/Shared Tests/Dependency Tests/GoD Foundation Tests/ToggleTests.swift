//
//  ToggleTests.swift
//
//  Coverage for the Toggle Codable enum and its Array filter helper.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class ToggleTests: XCTestCase {

    private func decode(_ json: String) throws -> Toggle {
        try JSONDecoder().decode(Toggle.self, from: Data(json.utf8))
    }

    func testDecodeTruthyValues() throws {
        for raw in ["\"YES\"", "\"yes\"", "\"Yes\"", "\"true\"", "\"TRUE\"", "\"True\""] {
            XCTAssertEqual(try decode(raw), .yes, "\(raw) should decode to .yes")
        }
    }

    func testDecodeFalsyValues() throws {
        for raw in ["\"NO\"", "\"no\"", "\"false\""] {
            XCTAssertEqual(try decode(raw), .no, "\(raw) should decode to .no")
        }
    }

    func testUnrecognizedValueDecodesToNo() throws {
        // Known quirk: anything unrecognized falls back to .no rather than failing.
        XCTAssertEqual(try decode("\"maybe\""), .no)
        XCTAssertEqual(try decode("\"1\""), .no)
        XCTAssertEqual(try decode("\"\""), .no)
    }

    func testRawValueInit() {
        XCTAssertEqual(Toggle(rawValue: "true"), .yes)
        XCTAssertEqual(Toggle(rawValue: "anything else"), .no)
    }

    func testEncodeRawValues() throws {
        let yes: Data = try JSONEncoder().encode(Toggle.yes)
        XCTAssertEqual(String(data: yes, encoding: .utf8), "\"YES\"")
        let no: Data = try JSONEncoder().encode(Toggle.no)
        XCTAssertEqual(String(data: no, encoding: .utf8), "\"NO\"")
    }

    func testArrayFilterByKeypath() {
        struct Row { let name: String; let enabled: Toggle }
        let rows = [
            Row(name: "a", enabled: .yes),
            Row(name: "b", enabled: .no),
            Row(name: "c", enabled: .yes),
        ]
        let enabled = rows.filter(\.enabled)
        XCTAssertEqual(enabled.map(\.name), ["a", "c"])
    }
}
