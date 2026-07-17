//
//  JSONTests.swift
//
//  Coverage for JSONDecoder/JSONEncoder GoDData bridges.
//

import Foundation
import XCTest
@testable import GoDFoundation

private struct Sample: Codable, Equatable {
    let id: Int
    let name: String
}

final class JSONTests: XCTestCase {

    func testEncodeReturnsGoDData() throws {
        let value = Sample(id: 7, name: "seven")
        let data: GoDData = try JSONEncoder().encode(value)
        XCTAssertGreaterThan(data.length, 0)
        XCTAssertEqual(data.byteOrder, Environment.byteOrder)
    }

    func testDecodeFromGoDData() throws {
        let value = Sample(id: 9, name: "nine")
        let encoded: GoDData = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Sample.self, from: encoded)
        XCTAssertEqual(decoded, value)
    }

    func testDecodeInvalidThrows() {
        let junk = GoDData(string: "{not valid json", format: .utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Sample.self, from: junk))
    }

    func testDecodingErrorDescription() {
        let error = JSONDecodingError.invalidToken("XYZ", Int.self)
        XCTAssertTrue(error.description.contains("XYZ"))
    }
}
