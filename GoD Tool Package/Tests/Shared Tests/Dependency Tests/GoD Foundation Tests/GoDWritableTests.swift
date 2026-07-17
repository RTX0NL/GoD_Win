//
//  GoDWritableTests.swift
//
//  Coverage for the write primitives on GoDData (via GoDWritable).
//

import Foundation
import XCTest
@testable import GoDFoundation

final class GoDWritableTests: XCTestCase {

    func testWriteGoDDataAtAddress() {
        let d = GoDData(length: 8, byteOrder: .big)
        XCTAssertTrue(d.write(GoDData(byteStream: [0xAA, 0xBB], byteOrder: .big), atAddress: UInt(2)))
        XCTAssertEqual(d.rawBytes, [0, 0, 0xAA, 0xBB, 0, 0, 0, 0])
    }

    func testWriteGrowsWithPadding() {
        let d = GoDData(length: 2, byteOrder: .big)
        d.write(GoDData(byteStream: [1, 2, 3, 4], byteOrder: .big), atAddress: 4)
        XCTAssertEqual(d.rawBytes, [0, 0, 0, 0, 1, 2, 3, 4])
    }

    func testWriteNilIsNoOp() {
        let d = GoDData(byteStream: [1, 2, 3], byteOrder: .big)
        let nilData: GoDData? = nil
        XCTAssertTrue(d.write(nilData, atAddress: 0))
        XCTAssertEqual(d.rawBytes, [1, 2, 3])
    }

    func testWritePrimitiveBigEndianRoundTrip() {
        let d = GoDData(length: 8, byteOrder: .big)
        d.write(UInt32(0x1234_5678), atAddress: 0)
        XCTAssertEqual(Array(d.rawBytes[0..<4]), [0x12, 0x34, 0x56, 0x78])
        let back: UInt32? = d.readValue(atAddress: 0)
        XCTAssertEqual(back, 0x1234_5678)
    }

    func testWritePrimitiveLittleEndian() {
        let d = GoDData(length: 4, byteOrder: .little)
        d.write(UInt16(0xABCD), atAddress: 0)
        XCTAssertEqual(Array(d.rawBytes[0..<2]), [0xCD, 0xAB])
    }

    func testWriteVariousWidths() {
        let d = GoDData(length: 16, byteOrder: .big)
        d.write(UInt8(0xEF), atAddress: 0)
        d.write(UInt16(0x0102), atAddress: 1)
        d.write(UInt32(0x0304_0506), atAddress: 3)
        XCTAssertEqual(Array(d.rawBytes[0..<7]), [0xEF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
    }

    func testWriteAsType() {
        let d = GoDData(length: 4, byteOrder: .big)
        XCTAssertTrue(d.write(0x1234, AsType: UInt16.self, atAddress: 0))
        XCTAssertEqual(Array(d.rawBytes[0..<2]), [0x12, 0x34])

        // A nil value is a no-op success.
        let none: Int? = nil
        XCTAssertTrue(d.write(none, AsType: UInt16.self, atAddress: 2))
        XCTAssertEqual(Array(d.rawBytes[2..<4]), [0, 0])
    }

    func testWriteString() {
        let d = GoDData(length: 0, byteOrder: .big)
        d.write("AB", atAddress: 0, format: .utf8, includeNullTerminator: true)
        XCTAssertEqual(d.rawBytes, [0x41, 0x42, 0x00])
    }

    func testWriteStringWithMaxCharactersPads() {
        let d = GoDData(length: 0, byteOrder: .big)
        d.write("AB", atAddress: 0, format: .utf8, maxCharacters: 4)
        XCTAssertEqual(d.rawBytes, [0x41, 0x42, 0x00, 0x00])
    }

    func testWriteStringWithMaxCharactersTruncates() {
        let d = GoDData(length: 0, byteOrder: .big)
        d.write("ABCDEF", atAddress: 0, format: .utf8, maxCharacters: 3)
        XCTAssertEqual(d.rawBytes, [0x41, 0x42, 0x43])
    }

    func testWriteNilStringIsNoOp() {
        let d = GoDData(byteStream: [9, 9], byteOrder: .big)
        let s: String? = nil
        XCTAssertTrue(d.write(s, atAddress: 0, format: .utf8))
        XCTAssertEqual(d.rawBytes, [9, 9])
    }

    func testWriteCharacter() {
        let d = GoDData(length: 2, byteOrder: .big)
        d.writeCharacter("Z", atAddress: 0, format: .utf8)
        XCTAssertEqual(d.rawBytes[0], 0x5A)
    }

    func testNull() {
        let d = GoDData(byteStream: [1, 2, 3, 4, 5, 6], byteOrder: .big)
        d.null(start: 1, length: 3)
        XCTAssertEqual(d.rawBytes, [1, 0, 0, 0, 5, 6])
    }
}
