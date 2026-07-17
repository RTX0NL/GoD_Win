//
//  StructDataCodingTests.swift
//
//  Covers the StructData accessor paths not hit by the existing decode /
//  byte-order tests: CustomStringConvertible rendering across every
//  property kind, the Encodable JSON shape (enum names, lossless floats,
//  labels, arrays, sub-structs), the userInfo-driven Decodable entry
//  point, and its error paths.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructDataCodingTests: XCTestCase {

    // MARK: - description

    func testDescriptionRendersEveryPropertyKind() {
        let inner = StructDefinition(name: "Stats", wordSize: 1, alignmentStyle: .none,
                                     properties: [.uint8(name: "x"), .uint8(name: "y")])
        let def = StructDefinition(
            name: "Mon", wordSize: 1, alignmentStyle: .none,
            properties: [
                .uint8(name: "hp"),
                .int16(name: "atk"),
                .float(name: "weight"),
                .boolean(name: "shiny"),
                .abstraction(name: "day", enumeration: weekEnum),
                .label(name: "script"),
                .array(name: "moves", count: 3, of: .uint16),
                .string(name: "nick", format: .utf8, length: 4),
                .subStruct(name: "stats", defintion: inner),
                .padding(length: 2),
            ]
        )
        let sut = StructData(definition: def, byteOrder: .big)
        sut.set("hp", to: 100)
        sut.set("atk", to: -5)
        sut.set("weight", to: Float(2.5))
        sut.set("shiny", to: 1)
        sut.set("day", to: 3)
        sut.setLabel("script", to: "MyScript")
        sut.set("nick", to: "abcd", format: .utf8)
        sut.set("stats.x", to: 7)

        let desc = sut.description
        XCTAssertTrue(desc.contains("hp = 100"), desc)
        XCTAssertTrue(desc.contains("atk = -5"), desc)
        XCTAssertTrue(desc.contains("weight = 2.5"), desc)
        XCTAssertTrue(desc.contains("shiny = true"), desc)
        XCTAssertTrue(desc.contains("day = Thursday (3) <DaysOfWeek>"), desc)
        XCTAssertTrue(desc.contains("script = MyScript <label>"), desc)
        XCTAssertTrue(desc.contains("moves: 3 items"), desc)
        XCTAssertTrue(desc.contains("nick = abcd"), desc)
        XCTAssertTrue(desc.contains("stats:"), desc)
        // `.padding(length:)` expands to `.array(.uint8, count:)` named
        // "padding", so it renders through the array branch.
        XCTAssertTrue(desc.contains("padding: 2 items"), desc)
    }

    func testDescriptionUnknownEnumValue() {
        let def = StructDefinition(name: "E", wordSize: 1, alignmentStyle: .none,
                                   properties: [.abstraction(name: "day", enumeration: weekEnum)])
        let sut = StructData(definition: def, byteOrder: .big)
        sut.set("day", to: 99)
        XCTAssertTrue(sut.description.contains("day = unknown (99) <DaysOfWeek>"), sut.description)
    }

    func testDescriptionLabelDefaultsToNA() {
        let def = StructDefinition(name: "L", wordSize: 1, alignmentStyle: .none,
                                   properties: [.label(name: "ptr")])
        let sut = StructData(definition: def, byteOrder: .big)
        XCTAssertTrue(sut.description.contains("ptr = N/A <label>"), sut.description)
    }

    // MARK: - Encodable JSON shape

    private func encodedDataNode(_ sut: StructData) throws -> [String: Any] {
        let json = try XCTUnwrap(sut.encodeJSON())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        return try XCTUnwrap(root["data"] as? [String: Any])
    }

    func testEncodeEmitsEnumNamesLabelsLosslessArraysSubStructs() throws {
        let inner = StructDefinition(name: "Inner", wordSize: 1, alignmentStyle: .none,
                                     properties: [.uint8(name: "x")])
        let def = StructDefinition(
            name: "Enc", wordSize: 1, alignmentStyle: .none,
            properties: [
                .abstraction(name: "day", enumeration: weekEnum),
                .losslessFloat(name: "lf"),
                .label(name: "ptr"),
                .array(name: "arr", count: 3, of: .uint8),
                .subStruct(name: "sub", defintion: inner),
            ]
        )
        let sut = StructData(definition: def, byteOrder: .big)
        sut.set("day", to: 2)                       // Wednesday
        sut.set("lf", to: Float(1.5))
        sut.setLabel("ptr", to: "L")
        sut.set("arr", to: GoDData(byteStream: [1, 2, 3], byteOrder: .big))
        sut.set("sub.x", to: 9)

        let node = try encodedDataNode(sut)
        XCTAssertEqual(node["day"] as? String, "Wednesday")
        XCTAssertEqual(node["lf"] as? String, "1.5")            // lossless → JSON string
        XCTAssertEqual(node["ptr"] as? String, "L")
        XCTAssertEqual(node["arr"] as? [Int], [1, 2, 3])
        XCTAssertEqual((node["sub"] as? [String: Any])?["x"] as? Int, 9)

        // Top-level "type" is the definition name.
        let json = try XCTUnwrap(sut.encodeJSON())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        XCTAssertEqual(root["type"] as? String, "Enc")
    }

    func testEncodeRenamesMultiplePaddingRegions() throws {
        let def = StructDefinition(
            name: "Pads", wordSize: 1, alignmentStyle: .none,
            properties: [.padding(length: 2), .uint8(name: "a"), .padding(length: 2)]
        )
        let sut = StructData(definition: def, byteOrder: .big)
        let node = try encodedDataNode(sut)
        XCTAssertNotNil(node["padding_0"])
        XCTAssertNotNil(node["padding_1"])
        XCTAssertNotNil(node["a"])
    }

    // MARK: - init(definition:json:) round trip

    // NOTE: StructData provides `init(from decoder:)` + a
    // `definitionUserInfoKey` and its doc comment claims
    // `JSONDecoder().decode(StructData.self, …)` works with a definition
    // in userInfo — but StructData never declares `: Decodable`
    // conformance, so that path is unreachable. The working entry point
    // is `init(definition:json:)`, exercised here across enum, lossless
    // double, label, array, sub-struct and double fields.
    func testInitJSONRoundTrip() throws {
        let inner = StructDefinition(name: "Inner", wordSize: 1, alignmentStyle: .none,
                                     properties: [.uint8(name: "x")])
        let def = StructDefinition(
            name: "RT", wordSize: 1, alignmentStyle: .none,
            properties: [
                .abstraction(name: "day", enumeration: weekEnum),
                .losslessDouble(name: "ld"),
                .label(name: "ptr"),
                .array(name: "arr", count: 3, of: .uint8),
                .subStruct(name: "sub", defintion: inner),
                .double(name: "d"),
            ]
        )
        let original = StructData(definition: def, byteOrder: .big)
        original.set("day", to: 4)
        original.set("ld", to: Double(3.25))
        original.setLabel("ptr", to: "Sym")
        original.set("arr", to: GoDData(byteStream: [9, 8, 7], byteOrder: .big))
        original.set("sub.x", to: 5)
        original.set("d", to: Double(-2.75))

        let json = try XCTUnwrap(original.encodeJSON())
        let rebuilt = try StructData(definition: def, json: json)

        XCTAssertEqual(rebuilt.data.rawBytes, original.data.rawBytes, "byte-identical round trip")
        XCTAssertEqual(rebuilt.labelValues["ptr"], "Sym")
    }

    func testInitJSONNonObjectThrows() {
        let def = StructDefinition(name: "X", wordSize: 1, alignmentStyle: .none, properties: [.uint8(name: "a")])
        let json = "[1,2,3]".data(format: .utf8)
        XCTAssertThrowsError(try StructData(definition: def, json: json))
    }

    func testInitJSONMissingDataThrows() {
        let def = StructDefinition(name: "X", wordSize: 1, alignmentStyle: .none, properties: [.uint8(name: "a")])
        let json = #"{"type":"X"}"#.data(format: .utf8)
        XCTAssertThrowsError(try StructData(definition: def, json: json))
    }

    // MARK: - LosslessFloat / LosslessDouble wrappers

    func testLosslessWrappersRejectNonNumericStrings() {
        XCTAssertThrowsError(try JSONDecoder().decode(LosslessFloat.self, from: #""abc""#.data(format: .utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LosslessDouble.self, from: #""xyz""#.data(format: .utf8)))
    }

    func testLosslessFloatDenormalRoundTrip() throws {
        // Subnormal Float32 that loses bits through plain JSON numbers.
        let denormal = Float(bitPattern: 0x0000_0010)
        let encoded = try XCTUnwrap(LosslessFloat(denormal).encodeJSON())
        let decoded = try JSONDecoder().decode(LosslessFloat.self, from: encoded)
        XCTAssertEqual(decoded.value.bitPattern, denormal.bitPattern)
    }
}
