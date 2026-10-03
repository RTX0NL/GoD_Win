//
//  StructMapTests.swift
//
//  Exercises the JSON struct-map parser (StructMap: Decodable) — the
//  data-driven core that turns "type name" token strings into a typed
//  property list — plus the inverse Encodable path. Covers every field
//  category (integers of each width, float/double/lossless, bool,
//  char/string, arrays incl. nested, enum, sub-struct, label, void
//  padding) and the malformed-token error paths.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructMapTests: XCTestCase {

    // Build a StructMap JSON document from a list of "type name" property
    // tokens. `description` is emitted as null (the decoder requires the
    // key to be present).
    private func mapJSON(
        name: String = "Sample",
        wordSize: Int = 1,
        alignmentStyle: String = "none",
        properties: [String]
    ) -> GoDData {
        let props = properties.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"name":"\(name)","description":null,"wordSize":\(wordSize),"alignmentStyle":"\(alignmentStyle)","properties":[\(props)]}
        """
        return json.data(format: .utf8)
    }

    private func decode(_ properties: [String]) throws -> StructMap {
        try JSONDecoder().decode(StructMap.self, from: mapJSON(properties: properties))
    }

    // MARK: - Valid parses

    func testParsesScalarHeaderFields() throws {
        let map = try JSONDecoder().decode(
            StructMap.self,
            from: mapJSON(name: "Header", wordSize: 4, alignmentStyle: "cStyle", properties: ["uint8 a"])
        )
        XCTAssertEqual(map.name, "Header")
        XCTAssertEqual(map.wordSize, 4)
        XCTAssertEqual(map.alignmentStyle, .cStyle)
        XCTAssertNil(map.description)
        XCTAssertEqual(map.properties.count, 1)
        XCTAssertEqual(map.properties[0].name, "a")
        XCTAssertEqual(map.properties[0].type, .uint8)
    }

    func testParsesAllIntegerWidths() throws {
        let map = try decode([
            "uint8 a", "int8 b",
            "uint16 c", "int16 d",
            "uint24 e", "int24 f",
            "uint32 g", "int32 h",
            "uint64 i", "int64 j",
        ])
        let expected: [StructField] = [
            .uint8, .int8, .uint16, .int16, .uint24, .int24, .uint32, .int32, .uint64, .int64,
        ]
        XCTAssertEqual(map.properties.map(\.type), expected)
        XCTAssertEqual(map.properties.map(\.name), ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
    }

    func testParsesFloatingAndBooleanAndChar() throws {
        let map = try decode([
            "float f", "double d",
            "lossless_float lf", "lossless_double ld",
            "boolean b", "char c8",
            "char_utf8 u8", "char_gsColo gc",
        ])
        XCTAssertEqual(map.properties.map(\.type), [
            .float, .double,
            .primitive(.lossless_float), .primitive(.lossless_double),
            .boolean, .uint8,                                    // "char" aliases uint8
            .primitive(.character(.utf8)), .primitive(.character(.gsColo)),
        ])
    }

    func testParsesLabel() throws {
        let map = try decode(["label ptr"])
        XCTAssertEqual(map.properties[0].type, .label)
        XCTAssertEqual(map.properties[0].name, "ptr")
    }

    func testParsesVoidPadding() throws {
        let map = try decode(["void[16] pad"])
        XCTAssertEqual(map.properties[0].type, .padding(length: 16))
    }

    func testParsesArrayOfPrimitive() throws {
        let map = try decode(["uint16[3] shorts"])
        XCTAssertEqual(map.properties[0].type, .array(.uint16, count: 3))
        XCTAssertEqual(map.properties[0].name, "shorts")
    }

    func testParsesNestedArray() throws {
        // Right-most bracket parsed first: uint8[2][3] → array(array(uint8, 2), 3)
        let map = try decode(["uint8[2][3] grid"])
        XCTAssertEqual(map.properties[0].type, .array(.array(.uint8, count: 2), count: 3))
    }

    func testParsesArrayOfChars() throws {
        let map = try decode(["char_utf8[8] name"])
        XCTAssertEqual(map.properties[0].type, .array(.primitive(.character(.utf8)), count: 8))
    }

    func testParsesEnumReference() throws {
        let map = try decode(["enum DaysOfWeek day"])
        XCTAssertEqual(map.properties[0].type, .enumeration(name: "DaysOfWeek"))
        XCTAssertEqual(map.properties[0].name, "day")
    }

    func testParsesSubStructReference() throws {
        let map = try decode(["struct Inner inner"])
        XCTAssertEqual(map.properties[0].type, .subStruct(name: "Inner"))
    }

    // MARK: - Round trip through Encodable

    func testEncodeDecodeRoundTripPreservesProperties() throws {
        let tokens = [
            "uint8 a", "int32 b", "float c", "boolean d",
            "uint16[4] e", "enum DaysOfWeek f", "struct Inner g",
            "void[8] pad", "label ptr", "char_utf8[6] name",
        ]
        let first = try decode(tokens)
        let jsonString = try XCTUnwrap(first.encodeJSONString())
        let second = try JSONDecoder().decode(StructMap.self, from: jsonString.data(format: .utf8))

        XCTAssertEqual(first.name, second.name)
        XCTAssertEqual(first.wordSize, second.wordSize)
        XCTAssertEqual(first.alignmentStyle, second.alignmentStyle)
        XCTAssertEqual(first.properties, second.properties,
                       "property list should survive an encode/decode round trip")
    }

    func testEncodeEmitsTypeNameTokens() throws {
        let map = StructMap(
            name: "Enc",
            wordSize: 2,
            alignmentStyle: .cStyle,
            properties: [
                .uint16(name: "hp"),
                .array(name: "moves", count: 4, of: .uint16),
                .label(name: "script"),
            ],
            description: "a doc string"
        )
        let jsonString = try XCTUnwrap(map.encodeJSONString())
        // Property tokens are "<type> <snake_name>".
        XCTAssertTrue(jsonString.contains("uint16 hp"), jsonString)
        XCTAssertTrue(jsonString.contains("uint16[4] moves"), jsonString)
        XCTAssertTrue(jsonString.contains("label script"), jsonString)
        XCTAssertTrue(jsonString.contains("a doc string"), jsonString)
    }

    // MARK: - Property helpers & normalization

    func testPropertyInitStripsSpacesFromName() {
        let p = StructMap.Property(name: "some field", type: .uint8)
        XCTAssertEqual(p.name, "somefield")
    }

    func testPropertyStaticHelpers() {
        XCTAssertEqual(StructMap.Property.uint8(name: "x").type, .uint8)
        XCTAssertEqual(StructMap.Property.int64(name: "x").type, .int64)
        XCTAssertEqual(StructMap.Property.double(name: "x").type, .double)
        XCTAssertEqual(StructMap.Property.losslessFloat(name: "x").type, .primitive(.lossless_float))
        XCTAssertEqual(StructMap.Property.losslessDouble(name: "x").type, .primitive(.lossless_double))
        XCTAssertEqual(StructMap.Property.boolean(name: "x").type, .boolean)
        XCTAssertEqual(StructMap.Property.character(name: "x", format: .gsXD).type, .primitive(.character(.gsXD)))
        XCTAssertEqual(StructMap.Property.string(name: "x", format: .utf8, length: 5).type,
                       .array(.primitive(.character(.utf8)), count: 5))
        XCTAssertEqual(StructMap.Property.subStruct(name: "x", typeName: "Foo").type, .subStruct(name: "Foo"))
        XCTAssertEqual(StructMap.Property.abstraction(name: "x", typeName: "Bar").type, .enumeration(name: "Bar"))
        XCTAssertEqual(StructMap.Property.padding(length: 3).type, .array(.uint8, count: 3))
        XCTAssertEqual(StructMap.Property.padding(length: 3).name, "padding")
    }

    // MARK: - Error paths

    func testTokenWithNoSpaceThrows() {
        XCTAssertThrowsError(try decode(["uint8"]))     // no " name" suffix
    }

    func testUnknownTypeTokenThrows() {
        XCTAssertThrowsError(try decode(["bogusType field"]))
    }

    func testNonIntegerArrayCountThrows() {
        // "xyz" is neither decimal nor hex, so the count can't parse.
        XCTAssertThrowsError(try decode(["uint8[xyz] field"]))
    }

    func testNonIntegerVoidCountThrows() {
        XCTAssertThrowsError(try decode(["void[xyz] field"]))
    }

    func testMissingDescriptionKeyThrows() {
        let json = #"{"name":"X","wordSize":1,"alignmentStyle":"none","properties":["uint8 a"]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(StructMap.self, from: json.data(format: .utf8)))
    }

    // MARK: - Bit fields

    /// A `properties` entry in its object form. A bit layout is a list, so
    /// it can't be a `"<type> <name>"` string — and the object is the only
    /// property form that carries a description per field.
    private func bitMapJSON(_ propertyObject: String, extra: [String] = []) -> GoDData {
        let entries = ([propertyObject] + extra.map { "\"\($0)\"" }).joined(separator: ",")
        let json = "{\"name\":\"Packed\",\"description\":null,\"wordSize\":1,"
            + "\"alignmentStyle\":\"none\",\"properties\":[\(entries)]}"
        return json.data(format: .utf8)
    }

    private static let flagsObject = """
    {"name":"flags","description":"the packed byte","storage":"uint8","bits":[
      {"name":"kind","range":"0:2","enum":"Kinds","description":"floor kind"},
      {"name":"visible","range":"3","type":"boolean"},
      {"name":"delta","range":"4:5","type":"signed"},
      {"name":"unknown_6_7","range":"6:7"}
    ]}
    """

    func testParsesABitFieldObject() throws {
        let map = try JSONDecoder().decode(
            StructMap.self,
            from: bitMapJSON(Self.flagsObject, extra: ["uint8 after"])
        )
        XCTAssertEqual(map.properties.count, 2)
        XCTAssertEqual(map.properties[0].name, "flags")
        XCTAssertEqual(map.properties[0].description, "the packed byte")
        XCTAssertEqual(map.properties[1].name, "after")

        guard case .bits(let bitMap) = map.properties[0].type else {
            return XCTFail("expected a bit field, got \(map.properties[0].type)")
        }
        XCTAssertEqual(bitMap.storage, .uint8)
        XCTAssertEqual(bitMap.fields.map(\.name), ["kind", "visible", "delta", "unknown_6_7"])
        XCTAssertEqual(bitMap.fields.map(\.bits), [0...2, 3...3, 4...5, 6...7])
        XCTAssertEqual(bitMap.fields.map(\.value), [
            .enumeration(name: "Kinds"), .boolean, .signed, .unsigned,
        ])
        XCTAssertEqual(bitMap.fields[0].description, "floor kind")
    }

    func testParsesAnArrayOfBitContainers() throws {
        let object = """
        {"name":"pair","description":null,"storage":"uint16","count":2,"bits":[
          {"name":"whole","range":"0:15"}
        ]}
        """
        let map = try JSONDecoder().decode(StructMap.self, from: bitMapJSON(object))
        guard case .array(.bits(let bitMap), let count) = map.properties[0].type else {
            return XCTFail("expected an array of bit fields, got \(map.properties[0].type)")
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(bitMap.storage, .uint16)
    }

    func testBitFieldsRoundTripThroughEncodeAndDecode() throws {
        let decoded = try JSONDecoder().decode(
            StructMap.self,
            from: bitMapJSON(Self.flagsObject, extra: ["uint8 after"])
        )
        let reEncoded = try XCTUnwrap(decoded.encodeJSON())
        let again = try JSONDecoder().decode(StructMap.self, from: reEncoded)
        XCTAssertEqual(again.properties.map(\.name), decoded.properties.map(\.name))
        XCTAssertEqual(again.properties.map(\.type), decoded.properties.map(\.type))
        XCTAssertEqual(again.properties.map(\.description), decoded.properties.map(\.description))
    }

    func testBadStorageTypeThrows() {
        let object = """
        {"name":"flags","description":null,"storage":"uint7","bits":[{"name":"a","range":"0:7"}]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(StructMap.self, from: bitMapJSON(object)))
    }

    func testBadRangeThrows() {
        for range in ["2:0", "", "a:b", "0:1:2"] {
            let object = """
            {"name":"flags","description":null,"storage":"uint8","bits":[{"name":"a","range":"\(range)"}]}
            """
            XCTAssertThrowsError(
                try JSONDecoder().decode(StructMap.self, from: bitMapJSON(object)),
                "range '\(range)' should be refused"
            )
        }
    }

    func testBadValueKindThrows() {
        let object = """
        {"name":"flags","description":null,"storage":"uint8","bits":[
          {"name":"a","range":"0:7","type":"float"}
        ]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(StructMap.self, from: bitMapJSON(object)))
    }

    func testBothTypeAndEnumThrows() {
        // The enum reference *is* the type; two answers to one question.
        let object = """
        {"name":"flags","description":null,"storage":"uint8","bits":[
          {"name":"a","range":"0:7","type":"unsigned","enum":"Kinds"}
        ]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(StructMap.self, from: bitMapJSON(object)))
    }
}
