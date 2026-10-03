//
//  StructDataBitFieldTests.swift
//
//  Reading and writing named bit ranges through `StructData` — the
//  accessors, the keypath resolution, and the JSON artifact.
//
//  Bit 0 is the most significant bit of the container, so the expectations
//  here are written as whole bytes: a shift error would still produce a
//  plausible number, and only the byte says which bits moved.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructDataBitFieldTests: XCTestCase {

    // MARK: - Fixtures

    /// Shaped like XD's map-REL character flags byte.
    private let flags = StructDefinition.Property.bits(name: "flags", fields: [
        .flag(name: "visible", bit: 0),
        .abstraction(name: "day", bits: 1...3, enumeration: weekEnum),
        .number(name: "delta", bits: 4...5, signed: true),
        .number(name: "unknown_6_7", bits: 6...7),
    ])

    private func definition(_ properties: [StructDefinition.Property]) -> StructDefinition {
        StructDefinition(name: "Packed", wordSize: 1, alignmentStyle: .none, properties: properties)
    }

    private func data(_ bytes: [UInt8], _ definition: StructDefinition) -> StructData {
        StructData(definition: definition, data: GoDData(byteStream: bytes, byteOrder: .big))
    }

    // MARK: - Keypath resolution

    func testTheContainerResolvesAsAPropertyAndItsFieldsDoNot() {
        let def = definition([.uint8(name: "before"), flags])
        XCTAssertEqual(def.offset(for: "flags"), 1)
        XCTAssertEqual(def.property(for: "flags"), flags.type)

        // A bit field is not a property: there is no byte of its own and no
        // `StructProperty` to describe three bits. Handing back the
        // container's offset instead would let a caller read the whole
        // container and call it the field.
        XCTAssertNil(def.offset(for: "flags.visible"))
        XCTAssertNil(def.property(for: "flags.visible"))

        let location = def.bitLocation(for: "flags.visible")
        XCTAssertEqual(location?.byteOffset, 1)
        XCTAssertEqual(location?.field.name, "visible")
    }

    func testBitLocationRefusesAnythingElse() {
        let def = definition([.uint8(name: "plain"), flags])
        XCTAssertNil(def.bitLocation(for: "flags"))
        XCTAssertNil(def.bitLocation(for: "flags.nope"))
        XCTAssertNil(def.bitLocation(for: "plain.visible"))
        XCTAssertNil(def.bitLocation(for: "missing.visible"))
        XCTAssertNil(def.bitLocation(for: ""))
    }

    func testBitLocationThroughASubStruct() {
        let inner = definition([flags])
        let outer = StructDefinition(
            name: "Outer", wordSize: 1, alignmentStyle: .none,
            properties: [.uint16(name: "pad"), .subStruct(name: "sub", defintion: inner)]
        )
        XCTAssertEqual(outer.bitLocation(for: "sub.flags.day")?.byteOffset, 2)
        XCTAssertEqual(outer.bitLocation(for: "sub.flags.day")?.field.name, "day")
    }

    func testANearMissSuggestsTheFieldName() {
        let def = definition([flags])
        XCTAssertEqual(def.closestBitFieldName(to: "flags.Unknown67"), "unknown_6_7")
        XCTAssertNil(def.closestBitFieldName(to: "flags.visible"))
        XCTAssertNil(def.closestBitFieldName(to: "flags"))
    }

    // MARK: - Reading

    func testReadsEveryValueKind() {
        // 0xBD = 1011 1101: visible 1, day 011 (Thursday), delta 11 (-1),
        // unknown 01.
        let def = definition([flags])
        let sut = data([0xBD], def)
        XCTAssertEqual(sut.getBits("flags.visible"), 1)
        XCTAssertEqual(sut.getBits("flags.day"), 3)
        XCTAssertEqual(sut.getBits("flags.delta"), -1)
        XCTAssertEqual(sut.getBits("flags.unknown_6_7"), 1)

        let day: Enum.Case? = sut.get("flags.day")
        XCTAssertEqual(day?.name, "Thursday")
        let visible: Bool? = sut.get("flags.visible")
        XCTAssertEqual(visible, true)
        let value: Int? = sut.get("flags.unknown_6_7")
        XCTAssertEqual(value, 1)
    }

    func testTheWholeContainerIsStillReadable() {
        let sut = data([0xBD], definition([flags]))
        let whole: Int? = sut.get("flags")
        XCTAssertEqual(whole, 0xBD)
    }

    func testReadingABitFieldOfAWiderContainer() {
        let def = definition([
            .bits(name: "word", storage: .uint16, fields: [
                .number(name: "high", bits: 0...3),
                .number(name: "middle", bits: 4...11),
                .number(name: "low", bits: 12...15),
            ]),
        ])
        let sut = data([0x12, 0x34], def)
        XCTAssertEqual(sut.getBits("word.high"), 0x1)
        XCTAssertEqual(sut.getBits("word.middle"), 0x23)
        XCTAssertEqual(sut.getBits("word.low"), 0x4)
    }

    func testThrowingEnumSubscriptOnABitField() throws {
        let sut = data([0xBD], definition([flags]))
        let day: Enum.Case = try sut[dynamicMember: "flags.day"]
        XCTAssertEqual(day.name, "Thursday")
        XCTAssertThrowsError(try sut[dynamicMember: "flags.delta"] as Enum.Case)
    }

    // MARK: - Writing

    func testWritingOneFieldLeavesItsNeighboursAlone() {
        let def = definition([.uint8(name: "before"), flags, .uint8(name: "after")])
        let sut = data([0x11, 0xFF, 0x22], def)
        // `day` is bits 1:3, so its mask is 0x70 — clearing it leaves 0x8F.
        sut.setBits("flags.day", to: 0)
        XCTAssertEqual(sut.data.rawBytes, [0x11, 0x8F, 0x22])
        sut.setBits("flags.visible", to: 0)
        XCTAssertEqual(sut.data.rawBytes, [0x11, 0x0F, 0x22])
    }

    func testAnOverWideValueIsTruncatedRatherThanBleeding() {
        let sut = data([0x00], definition([flags]))
        sut.setBits("flags.day", to: 0xFF)
        XCTAssertEqual(sut.data.rawBytes, [0x70])
    }

    func testSetThroughTheIntegerPathWritesBits() {
        let sut = data([0x00], definition([flags]))
        // `delta` is bits 4:5, so its mask is 0x0C.
        sut.set("flags.delta", to: -1)
        XCTAssertEqual(sut.data.rawBytes, [0x0C])
    }

    func testSetThroughTheDataPathWritesBits() {
        let sut = data([0x00], definition([flags]))
        sut.set("flags.day", to: 5)
        XCTAssertEqual(sut.getBits("flags.day"), 5)
        let typed: Bool = true
        sut.set("flags.visible", to: typed)
        XCTAssertEqual(sut.getBits("flags.visible"), 1)
    }

    func testSettingTheWholeContainerOverwritesEveryField() {
        let sut = data([0x00], definition([flags]))
        sut.set("flags", to: 0xBD)
        XCTAssertEqual(sut.getBits("flags.day"), 3)
        XCTAssertEqual(sut.data.rawBytes, [0xBD])
    }

    func testSetEnumCaseByName() throws {
        let sut = data([0x00], definition([flags]))
        try sut.setEnumCase("flags.day", named: "Friday")
        XCTAssertEqual(sut.getBits("flags.day"), 4)
        XCTAssertEqual(sut.data.rawBytes, [0x40])

        XCTAssertThrowsError(try sut.setEnumCase("flags.day", named: "Octember"))
        XCTAssertThrowsError(try sut.setEnumCase("flags.delta", named: "Friday"))
        // The byte is unchanged by either failure.
        XCTAssertEqual(sut.data.rawBytes, [0x40])
    }

    func testStringSetterResolvesAnEnumTypedBitFieldByCaseName() {
        let sut = data([0x00], definition([flags]))
        let named: String? = "Satday"
        sut[dynamicMember: "flags.day"] = named
        XCTAssertEqual(sut.getBits("flags.day"), 5)

        // A subscript setter can't throw, so a name the enum doesn't have
        // leaves the bits as they were rather than writing zero.
        let unknown: String? = "Octember"
        sut[dynamicMember: "flags.day"] = unknown
        XCTAssertEqual(sut.getBits("flags.day"), 5)
    }

    func testEnumCaseSetterWritesBits() {
        let sut = data([0x00], definition([flags]))
        sut.set("flags.day", to: try? weekEnum.get("Satday"))
        XCTAssertEqual(sut.getBits("flags.day"), 5)
    }

    func testAnArrayOfContainersOccupiesOneStoragePerElement() {
        let def = definition([
            .bitsArray(name: "pair", count: 2, fields: [
                .flag(name: "on", bit: 0),
                .number(name: "rest", bits: 1...7),
            ]),
        ])
        XCTAssertEqual(def.length, 2)
        // Elements are addressed by index in the CSV schema rather than by
        // keypath, so that is where the per-element offsets are checked.
        XCTAssertEqual(StructCSVSchema.columns(of: def).map(\.offset), [0, 0, 1, 1])
    }

    // MARK: - description

    func testDescriptionListsEveryField() {
        let sut = data([0xBD], definition([flags]))
        let description = sut.description
        XCTAssertTrue(description.contains("flags <bits(uint8)>"), description)
        XCTAssertTrue(description.contains("visible = true"), description)
        XCTAssertTrue(description.contains("day = Thursday (3)"), description)
        XCTAssertTrue(description.contains("delta = -1"), description)
    }

    // MARK: - JSON

    private func json(_ structData: StructData) throws -> [String: Any] {
        let encoded = try XCTUnwrap(structData.encodeJSON())
        let root = try JSONSerialization.jsonObject(with: encoded.data) as? [String: Any]
        return try XCTUnwrap(root?["data"] as? [String: Any])
    }

    func testEncodesAsANestedObjectOfNamedRanges() throws {
        let sut = data([0xBD], definition([flags]))
        let node = try XCTUnwrap(try json(sut)["flags"] as? [String: Any])
        XCTAssertEqual(node["visible"] as? Bool, true)
        XCTAssertEqual(node["day"] as? String, "Thursday")
        XCTAssertEqual(node["delta"] as? Int, -1)
        XCTAssertEqual(node["unknown_6_7"] as? Int, 1)
        // The container's own integer is never emitted beside its fields:
        // two spellings of the same bytes would let one silently win.
        XCTAssertEqual(node.count, 4)
    }

    func testJSONRoundTripsByteIdentically() throws {
        let def = definition([
            .uint8(name: "before"),
            flags,
            .bits(name: "word", storage: .uint16, fields: [
                .number(name: "high", bits: 0...7),
                .number(name: "low", bits: 8...15),
            ]),
        ])
        for bytes in [[0x00, 0x00, 0x00, 0x00], [0xFF, 0xFF, 0xFF, 0xFF], [0x11, 0xBD, 0xA5, 0x5A]] {
            let original = data(bytes.map(UInt8.init), def)
            let encoded = try XCTUnwrap(original.encodeJSON())
            let rebuilt = try StructData(definition: def, json: encoded)
            XCTAssertEqual(rebuilt.data.rawBytes, bytes.map(UInt8.init), "round trip of \(bytes)")
        }
    }

    func testJSONRoundTripThroughASubStructAndAnArray() throws {
        let inner = definition([flags])
        let def = StructDefinition(
            name: "Outer", wordSize: 1, alignmentStyle: .none,
            properties: [
                .subStruct(name: "sub", defintion: inner),
                .bitsArray(name: "pair", count: 2, fields: [
                    .flag(name: "on", bit: 0),
                    .number(name: "rest", bits: 1...7),
                ]),
            ]
        )
        let bytes: [UInt8] = [0xBD, 0x81, 0x7F]
        let encoded = try XCTUnwrap(data(bytes, def).encodeJSON())
        let rebuilt = try StructData(definition: def, json: encoded)
        XCTAssertEqual(rebuilt.data.rawBytes, bytes)
    }

    func testJSONRefusesABareIntegerForTheContainer() {
        let def = definition([flags])
        let document = "{\"type\":\"Packed\",\"data\":{\"flags\":189}}"
        XCTAssertThrowsError(
            try StructData(definition: def, json: document.data(format: .utf8))
        ) { error in
            XCTAssertTrue("\(error)".contains("flags"), "\(error)")
        }
    }

    func testJSONLeavesAFieldItDoesNotMention() throws {
        let def = definition([flags])
        let document = "{\"type\":\"Packed\",\"data\":{\"flags\":{\"day\":\"Friday\"}}}"
        let sut = try StructData(definition: def, json: document.data(format: .utf8))
        XCTAssertEqual(sut.data.rawBytes, [0x40])
    }

    func testJSONAcceptsARawValueForAnEnumField() throws {
        let def = definition([flags])
        let document = "{\"type\":\"Packed\",\"data\":{\"flags\":{\"day\":6}}}"
        let sut = try StructData(definition: def, json: document.data(format: .utf8))
        XCTAssertEqual(sut.getBits("flags.day"), 6)
    }

    func testJSONRejectsAWrongTypeForABitField() {
        let def = definition([flags])
        for document in [
            "{\"type\":\"Packed\",\"data\":{\"flags\":{\"visible\":\"yes\"}}}",
            "{\"type\":\"Packed\",\"data\":{\"flags\":{\"delta\":\"lots\"}}}",
            "{\"type\":\"Packed\",\"data\":{\"flags\":{\"day\":\"Octember\"}}}",
        ] {
            XCTAssertThrowsError(
                try StructData(definition: def, json: document.data(format: .utf8)),
                document
            )
        }
    }
}
