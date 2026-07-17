//
//  GoDMutableTests.swift
//
//  Coverage for the mutation primitives on GoDData (via GoDMutableData).
//

import Foundation
import XCTest
@testable import GoDFoundation

final class GoDMutableTests: XCTestCase {

    func testAppendGoDData() {
        let d = GoDData(byteStream: [1, 2], byteOrder: .big)
        d.append(GoDData(byteStream: [3, 4], byteOrder: .big))
        XCTAssertEqual(d.rawBytes, [1, 2, 3, 4])
    }

    func testAppendDataConvertible() {
        let d = GoDData(byteOrder: .big)
        d.append(UInt16(0x0102))
        d.append(UInt8(0x03))
        XCTAssertEqual(d.rawBytes, [0x01, 0x02, 0x03])
    }

    func testAppendString() {
        let d = GoDData(byteOrder: .big)
        d.appendString("AB", format: .utf8)
        XCTAssertEqual(d.rawBytes, [0x41, 0x42])
        d.appendString("C", format: .utf8, includeTerminator: true)
        XCTAssertEqual(d.rawBytes, [0x41, 0x42, 0x43, 0x00])
    }

    func testInsert() {
        let d = GoDData(byteStream: [1, 4], byteOrder: .big)
        d.insert(GoDData(byteStream: [2, 3], byteOrder: .big), atOffset: UInt(1))
        XCTAssertEqual(d.rawBytes, [1, 2, 3, 4])
    }

    func testInsertDataConvertible() {
        let d = GoDData(byteStream: [0xFF], byteOrder: .big)
        d.insert(UInt16(0x0102), atOffset: 0)
        XCTAssertEqual(d.rawBytes, [0x01, 0x02, 0xFF])
    }

    func testPrepend() {
        let d = GoDData(byteStream: [3, 4], byteOrder: .big)
        d.prepend(GoDData(byteStream: [1, 2], byteOrder: .big))
        XCTAssertEqual(d.rawBytes, [1, 2, 3, 4])
    }

    func testPrependDataConvertible() {
        let d = GoDData(byteStream: [0x03], byteOrder: .big)
        d.prepend(UInt16(0x0102))
        XCTAssertEqual(d.rawBytes, [0x01, 0x02, 0x03])
    }

    func testDelete() {
        let d = GoDData(byteStream: [1, 2, 3, 4, 5], byteOrder: .big)
        d.delete(start: 1, count: 2)
        XCTAssertEqual(d.rawBytes, [1, 4, 5])
    }

    func testAlign() {
        let d = GoDData(byteStream: [1, 2, 3], byteOrder: .big)
        d.align(to: 4)
        XCTAssertEqual(d.rawBytes, [1, 2, 3, 0])
        // Already aligned: no change.
        d.align(to: 4)
        XCTAssertEqual(d.length, 4)
    }

    func testPad() {
        let d = GoDData(byteStream: [1], byteOrder: .big)
        d.pad(by: 3)
        XCTAssertEqual(d.rawBytes, [1, 0, 0, 0])
    }
}
