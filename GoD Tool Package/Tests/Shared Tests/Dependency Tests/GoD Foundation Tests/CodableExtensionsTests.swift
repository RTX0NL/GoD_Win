//
//  CodableExtensionsTests.swift
//
//  Coverage for Encodable/Decodable JSON helpers and CustomCodingKeys.
//

import Foundation
import XCTest
@testable import GoDFoundation

private struct Model: Codable, Equatable {
    let b: Int
    let a: String
}

final class CodableExtensionsTests: XCTestCase {

    func testEncodeJSONProducesSortedKeys() {
        let model = Model(b: 1, a: "x")
        let string = model.encodeJSONString()
        XCTAssertNotNil(string)
        // .sortedKeys => "a" appears before "b".
        if let s = string, let aIndex = s.range(of: "\"a\""), let bIndex = s.range(of: "\"b\"") {
            XCTAssertTrue(aIndex.lowerBound < bIndex.lowerBound)
        } else {
            XCTFail("keys not found in \(String(describing: string))")
        }
    }

    func testEncodeDecodeRoundTripViaData() {
        let model = Model(b: 5, a: "hello")
        guard let data = model.encodeJSON() else { return XCTFail("encode failed") }
        let decoded = Model.decodeJSON(from: data)
        XCTAssertEqual(decoded, model)
    }

    func testDecodeFromString() {
        let json = "{\"a\":\"y\",\"b\":42}"
        let decoded = Model.decodeJSON(from: json)
        XCTAssertEqual(decoded, Model(b: 42, a: "y"))
    }

    func testDecodeInvalidStringReturnsNil() {
        XCTAssertNil(Model.decodeJSON(from: "not json"))
    }

    func testWithoutEscapingSlashes() {
        struct Pathy: Codable { let path: String }
        let string = Pathy(path: "/a/b/c").encodeJSONString()
        XCTAssertEqual(string?.contains("/a/b/c"), true)
        XCTAssertEqual(string?.contains("\\/"), false)
    }

    func testCustomCodingKeysStringLiteral() {
        let key: CustomCodingKeys = "myKey"
        XCTAssertEqual(key.stringValue, "myKey")
        XCTAssertNil(key.intValue)
    }

    func testCustomCodingKeysInitStringValue() {
        let key = CustomCodingKeys(stringValue: "field")
        XCTAssertEqual(key?.stringValue, "field")
        let key2 = CustomCodingKeys("field2")
        XCTAssertEqual(key2.stringValue, "field2")
    }

    func testCustomCodingKeysIntValueInitReturnsNil() {
        XCTAssertNil(CustomCodingKeys(intValue: 3))
    }
}
