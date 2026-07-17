//
//  StructTableTests.swift
//
//  Covers StructTableData (indexed access over a packed array of fixed-
//  size records) and StructTableDefinition, plus the GoDData struct
//  read/write helpers in GoDData+StructProperties.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructTableTests: XCTestCase {

    private let entryDef = StructDefinition(
        name: "Pair",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "a"),
            .uint8(name: "b"),
        ]
    )

    private func table(entries: Int) -> StructTableData {
        // Each entry is 2 bytes; fill with an increasing pattern.
        let bytes = (0..<(entries * 2)).map { UInt8($0 & 0xFF) }
        return StructTableData(definition: entryDef, data: GoDData(byteStream: bytes, byteOrder: .big))
    }

    // MARK: - StructTableDefinition

    func testTableDefinitionStoresFields() {
        let def = StructTableDefinition(name: "Table", entryCount: 5, definition: entryDef)
        XCTAssertEqual(def.name, "Table")
        XCTAssertEqual(def.entryCount, 5)
        XCTAssertEqual(def.definition, entryDef)
    }

    // MARK: - count

    func testCountIsDataLengthOverEntryLength() {
        XCTAssertEqual(table(entries: 4).count, 4)
        XCTAssertEqual(table(entries: 0).count, 0)
    }

    // MARK: - get

    func testGetReturnsEntryAtIndex() {
        let sut = table(entries: 3)
        let entry1 = sut.get(index: 1)
        XCTAssertEqual(entry1?.get("a"), 2)   // bytes[2]
        XCTAssertEqual(entry1?.get("b"), 3)   // bytes[3]
    }

    func testGetOutOfRangeReturnsNil() {
        let sut = table(entries: 2)
        XCTAssertNil(sut.get(index: 2))
        XCTAssertNil(sut.get(index: 99))
    }

    func testSubscriptGet() {
        let sut = table(entries: 3)
        XCTAssertEqual(sut[2]?.get("a"), 4)
    }

    // MARK: - set

    func testSetWritesEntry() {
        let sut = table(entries: 3)
        let replacement = StructData(definition: entryDef, data: GoDData(byteStream: [0xAA, 0xBB], byteOrder: .big))
        XCTAssertTrue(sut.set(index: 1, to: replacement))
        XCTAssertEqual(sut.get(index: 1)?.get("a"), 0xAA)
        XCTAssertEqual(sut.get(index: 1)?.get("b"), 0xBB)
        // Neighbours untouched.
        XCTAssertEqual(sut.get(index: 0)?.get("a"), 0)
        XCTAssertEqual(sut.get(index: 2)?.get("a"), 4)
    }

    func testSetOutOfRangeReturnsFalse() {
        let sut = table(entries: 2)
        let replacement = StructData(definition: entryDef, data: GoDData(byteStream: [1, 2], byteOrder: .big))
        XCTAssertFalse(sut.set(index: 5, to: replacement))
    }

    func testSubscriptSet() {
        let sut = table(entries: 2)
        sut[0] = StructData(definition: entryDef, data: GoDData(byteStream: [9, 8], byteOrder: .big))
        XCTAssertEqual(sut.get(index: 0)?.get("b"), 8)
    }

    // MARK: - GoDData+StructProperties

    func testReadSingleStruct() {
        let data = GoDData(byteStream: [1, 2, 3, 4], byteOrder: .big)
        let sd = data.read(struct: entryDef, atAddress: 2)
        XCTAssertEqual(sd?.get("a"), 3)
        XCTAssertEqual(sd?.get("b"), 4)
    }

    func testReadStructArray() {
        let data = GoDData(byteStream: [1, 2, 3, 4, 5, 6], byteOrder: .big)
        let structs = data.read(structs: entryDef, atAddress: 0, count: 3)
        XCTAssertEqual(structs?.count, 3)
        XCTAssertEqual(structs?[2].get("a"), 5)
    }

    func testReadStructArrayZeroCountIsEmpty() {
        let data = GoDData(byteStream: [1, 2], byteOrder: .big)
        XCTAssertEqual(data.read(structs: entryDef, atAddress: 0, count: 0)?.count, 0)
    }

    func testReadStructArrayNegativeCountIsNil() {
        let data = GoDData(byteStream: [1, 2], byteOrder: .big)
        XCTAssertNil(data.read(structs: entryDef, atAddress: 0, count: -1))
    }

    func testReadStructArrayOverrunIsNil() {
        let data = GoDData(byteStream: [1, 2], byteOrder: .big)
        XCTAssertNil(data.read(structs: entryDef, atAddress: 0, count: 5))
    }

    func testReadPropertyReturnsFieldWidthSlice() {
        let data = GoDData(byteStream: [0xDE, 0xAD, 0xBE, 0xEF], byteOrder: .big)
        let slice = data.read(property: .uint16, atAddress: 1)
        XCTAssertEqual(slice?.rawBytes, [0xAD, 0xBE])
    }

    func testWriteStruct() {
        let data = GoDData(byteStream: [0, 0, 0, 0], byteOrder: .big)
        let sd = StructData(definition: entryDef, data: GoDData(byteStream: [7, 8], byteOrder: .big))
        XCTAssertTrue(data.write(struct: sd, atAddress: 2))
        XCTAssertEqual(data.rawBytes, [0, 0, 7, 8])
    }

    func testWriteNilStructIsNoOpButSucceeds() {
        let data = GoDData(byteStream: [1, 2], byteOrder: .big)
        XCTAssertTrue(data.write(struct: nil, atAddress: 0))
        XCTAssertEqual(data.rawBytes, [1, 2])
    }
}
