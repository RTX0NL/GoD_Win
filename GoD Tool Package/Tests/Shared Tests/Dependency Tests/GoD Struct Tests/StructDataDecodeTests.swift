//
//  StructDataDecodeTests.swift
//
//  Round-trip tests for the JSON → StructData decoder. Each test
//  builds a StructData from raw bytes, encodes it to JSON, decodes
//  back into a StructData, and confirms the resulting bytes match
//  the original byte-for-byte.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructDataDecodeTests: XCTestCase {

    // Roundtrip a struct made entirely of unsigned integers of every
    // common width — the simplest possible decode path.
    func testIntegerRoundTrip() throws {
        let def = StructDefinition(
            name: "Ints",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "a"),
                .int8(name: "b"),
                .uint16(name: "c"),
                .int16(name: "d"),
                .uint32(name: "e"),
                .int32(name: "f"),
                .uint64(name: "g"),
                .int64(name: "h"),
            ]
        )
        let bytes: [UInt8] = [
            0xAB,                                    // a = 0xAB
            0xFF,                                    // b = -1 (Int8)
            0x12, 0x34,                              // c = 0x1234
            0x80, 0x00,                              // d = -32768 (Int16 min)
            0xDE, 0xAD, 0xBE, 0xEF,                  // e = 0xDEADBEEF
            0xFF, 0xFF, 0xFF, 0xFF,                  // f = -1 (Int32)
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,  // g
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,  // h = -1 (Int64)
        ]
        try assertRoundTrip(definition: def, bytes: bytes)
    }

    // Arrays of primitives — uint8 array plus an array of uint16s.
    // The `padding(length:)` helper actually expands to
    // `.array(.uint8, count: N)`, so it round-trips through JSON
    // like any other byte array.
    func testArrayRoundTrip() throws {
        let def = StructDefinition(
            name: "Arrays",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .padding(length: 4),                          // = .array(.uint8, count: 4)
                .array(name: "bytes", count: 6, of: .uint8),
                .array(name: "shorts", count: 3, of: .uint16),
            ]
        )
        let bytes: [UInt8] = [
            0x10, 0x20, 0x30, 0x40,                                 // padding
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06,                     // bytes[6]
            0x11, 0x22, 0x33, 0x44, 0x55, 0x66,                     // shorts[3]: 0x1122, 0x3344, 0x5566
        ]
        try assertRoundTrip(definition: def, bytes: bytes)
    }

    // String / character-array round trip — the "encoded as one big
    // string" case in the encoder. We use `.utf8` here because
    // `StructPrimitives.character.length` and
    // `StringFormats.characterLength` agree on its byte width (1);
    // the other formats have a longstanding inconsistency where
    // `StructPrimitives.character` reports 2 bytes per char while
    // the string encoder writes 1 (or 2) bytes — that's a separate
    // bug to fix later.
    func testStringRoundTrip() throws {
        let def = StructDefinition(
            name: "Strings",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .string(name: "name", format: .utf8, length: 8),
            ]
        )
        let bytes: [UInt8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x00, 0x00] // "hello\0\0\0"
        try assertRoundTrip(definition: def, bytes: bytes)
    }

    // Enum round-trip — encode emits the case *name*, decode looks
    // it up via `Enum.get(name:)` and writes the rawValue. weekEnum's
    // propertyType is `.int8`, so the section is one signed byte.
    func testEnumRoundTrip() throws {
        let def = StructDefinition(
            name: "Enums",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .abstraction(name: "day", enumeration: weekEnum),
            ]
        )
        let bytes: [UInt8] = [0x03] // day = 3 (Thursday in weekEnum, which is u8-backed)
        try assertRoundTrip(definition: def, bytes: bytes)
    }

    func testSubStructRoundTrip() throws {
        let inner = StructDefinition(
            name: "Inner",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "x"),
                .uint8(name: "y"),
            ]
        )
        let outer = StructDefinition(
            name: "Outer",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "tag"),
                .subStruct(name: "inner", defintion: inner),
                .uint16(name: "trailer"),
            ]
        )
        let bytes: [UInt8] = [
            0xAA,           // tag
            0x10, 0x20,     // inner.x, inner.y
            0xBE, 0xEF,     // trailer = 0xBEEF
        ]
        try assertRoundTrip(definition: outer, bytes: bytes)
    }

    // Label property — encode emits the label name; decode recovers
    // it into `labelValues`. The 4 on-disk bytes stay zero.
    func testLabelRoundTrip() throws {
        let def = StructDefinition(
            name: "WithLabel",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "tag"),
                .label(name: "ptr"),
                .uint8(name: "trailer"),
            ]
        )
        let original = StructData(
            definition: def,
            data: GoDData(byteStream: [0xAA, 0x00, 0x00, 0x00, 0x00, 0xBB], byteOrder: .big)
        )
        original.labelValues["ptr"] = "someLabel"

        let json = try XCTUnwrap(original.encodeJSON())
        let rebuilt = try StructData(definition: def, json: json)

        XCTAssertEqual(rebuilt.labelValues["ptr"], "someLabel",
                       "label name should round-trip via labelValues")
        XCTAssertEqual(rebuilt.data.rawBytes, [0xAA, 0x00, 0x00, 0x00, 0x00, 0xBB],
                       "label's on-disk 4 bytes stay zero (matches encoder asymmetry)")
    }

    func testWrongTypeNameThrows() throws {
        let def = StructDefinition(
            name: "Real",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [.uint8(name: "x")]
        )
        let json = #"{"type":"Wrong","data":{"x":1}}"#.data(using: .utf8)!
        let bytes = GoDData(byteStream: [UInt8](json), byteOrder: .big)
        XCTAssertThrowsError(try StructData(definition: def, json: bytes))
    }

    // MARK: - Helpers

    /// Build StructData from `bytes`, encode to JSON, decode back,
    /// assert the decoded bytes match the original (or `expectedAfterDecode`
    /// when provided — used for properties like `.padding` that are
    /// asymmetric across the round-trip).
    private func assertRoundTrip(
        definition: StructDefinition,
        bytes: [UInt8],
        expectedAfterDecode: [UInt8]? = nil,
        file: StaticString = #file, line: UInt = #line
    ) throws {
        let original = StructData(
            definition: definition,
            data: GoDData(byteStream: bytes, byteOrder: .big)
        )
        let json = try XCTUnwrap(original.encodeJSON(), file: file, line: line)
        let rebuilt = try StructData(definition: definition, json: json)
        let expected = expectedAfterDecode ?? bytes
        XCTAssertEqual(
            rebuilt.data.rawBytes, expected,
            "round-trip bytes mismatch for \(definition.name)",
            file: file, line: line
        )
    }
}
