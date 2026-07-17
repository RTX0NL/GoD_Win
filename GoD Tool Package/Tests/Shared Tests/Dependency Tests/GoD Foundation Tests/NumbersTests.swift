//
//  NumbersTests.swift
//
//  Coverage for numeric helpers on Int and UInt8.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class NumbersTests: XCTestCase {

    // MARK: - Int

    func testBoolean() {
        XCTAssertFalse(0.boolean)
        XCTAssertTrue(1.boolean)
        XCTAssertTrue((-5).boolean)
    }

    func testString() {
        XCTAssertEqual(42.string, "42")
        XCTAssertEqual((-7).string, "-7")
    }

    func testUnsigned() {
        XCTAssertEqual(0.unsigned, 0)
        XCTAssertEqual(255.unsigned, 255)
        XCTAssertEqual(0x1234_5678.unsigned, 0x1234_5678)
        XCTAssertEqual((-1).unsigned, 0xFFFF_FFFF)
        XCTAssertEqual((-2).unsigned, 0xFFFF_FFFE)
    }

    func testHex() {
        XCTAssertEqual(255.hex(), "FF")
        XCTAssertEqual(0.hex(), "0")
        XCTAssertEqual(0xABCD.hex(), "ABCD")
        XCTAssertEqual(255.hexString(), "0xFF")
    }

    func testBinary() {
        XCTAssertEqual(5.binary(), "00000101")
        XCTAssertEqual(0.binary(), "00000000")
        XCTAssertEqual(256.binary(), "0000000100000000")
        XCTAssertEqual(5.binaryString(), "0b00000101")
    }

    func testByteArray() {
        XCTAssertEqual(0x0102_0304.byteArray, [1, 2, 3, 4])
        XCTAssertEqual(0.byteArray, [0, 0, 0, 0])
        XCTAssertEqual(0xFF.byteArray, [0, 0, 0, 0xFF])
    }

    func testByteArrayU16() {
        XCTAssertEqual(0x0102.byteArrayU16, [1, 2])
        XCTAssertEqual(0xABCD.byteArrayU16, [0xAB, 0xCD])
    }

    func testCharArray() {
        XCTAssertEqual(0x0102_0304.charArray, [1, 2, 3, 4] as [UInt8])
    }

    func testBits() {
        XCTAssertEqual(0b1011.bits(count: 4), [1, 1, 0, 1])
        XCTAssertEqual(0b1011.bits(count: 4, startWithLeastSignificantBit: false), [1, 0, 1, 1])
        XCTAssertEqual(0.bits(count: 3), [0, 0, 0])
    }

    func testBitArray() {
        XCTAssertEqual(0b101.bitArray(count: 3), [true, false, true])
        XCTAssertEqual(0b101.bitArray(count: 3, startWithLeastSignificantBit: false), [true, false, true])
    }

    func testMaskedValues() {
        XCTAssertEqual(0x1FF.int8Value, 0xFF)
        XCTAssertEqual(0x1_FFFF.int16Value, 0xFFFF)
        XCTAssertEqual(0xAB.int8Value, 0xAB)
    }

    func testInt32Value() {
        XCTAssertEqual(0x0000_0001.int32Value, 1)
        XCTAssertEqual(0xFFFF_FFFF.int32Value, -1)
        XCTAssertEqual(0x8000_0000.int32Value, Int(Int32.min))
    }

    func testAligned() {
        XCTAssertEqual(0.aligned(to: 16), 0)
        XCTAssertEqual(16.aligned(to: 16), 16)
        XCTAssertEqual(1.aligned(to: 16), 16)
        XCTAssertEqual(17.aligned(to: 16), 32)
        XCTAssertEqual(5.aligned(to: 4), 8)
        // boundary <= 0 is a no-op
        XCTAssertEqual(5.aligned(to: 0), 5)
    }

    // MARK: - UInt8

    func testUInt8Hex() {
        XCTAssertEqual(UInt8(0).hex(), "00")
        XCTAssertEqual(UInt8(15).hex(), "0F")
        XCTAssertEqual(UInt8(255).hex(), "FF")
        XCTAssertEqual(UInt8(171).hexString(), "0xAB")
    }

    func testUInt8Normalized() {
        XCTAssertEqual(UInt8(0).normalized(), 0.0)
        XCTAssertEqual(UInt8(255).normalized(), 1.0)
        XCTAssertEqual(UInt8(51).normalized(), 0.2, accuracy: 0.0001)
    }
}
