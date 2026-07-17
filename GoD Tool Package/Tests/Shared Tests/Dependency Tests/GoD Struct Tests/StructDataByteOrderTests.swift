//
//  StructDataByteOrderTests.swift
//
//  Exercises the integer read/write mutation API (`set`/`get`) in both
//  byte orders. Big-endian is what every current target (GameCube/Wii)
//  uses; little-endian was previously broken on the write path — the
//  truncation in `set(_:to: GoDData?)` dropped the low-order bytes on
//  LE, so writing 5 into a 2-byte LE field produced [0,0]. These tests
//  lock in the corrected behavior and the int24 sign-extension fix.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructDataByteOrderTests: XCTestCase {

    private func make(_ properties: [StructDefinition.Property], _ order: ByteOrder) -> StructData {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none, properties: properties)
        return StructData(definition: def, data: GoDData(length: def.length, byteOrder: order))
    }

    // The exact regression: 5 into a 2-byte LE field must be [0x05, 0x00],
    // and a 4-byte LE field must be low-byte-first — not [0,0]/garbage.
    func testLittleEndianWritesLowByteFirst() {
        let sd = make([.uint16(name: "a"), .uint32(name: "b")], .little)
        sd.set("a", to: 5)
        sd.set("b", to: 0x11223344)
        XCTAssertEqual(Array(sd.data.rawBytes[0..<2]), [0x05, 0x00])
        XCTAssertEqual(Array(sd.data.rawBytes[2..<6]), [0x44, 0x33, 0x22, 0x11])
    }

    // Big-endian is unchanged (high byte first) — this path always worked.
    func testBigEndianWritesHighByteFirst() {
        let sd = make([.uint16(name: "a"), .uint32(name: "b")], .big)
        sd.set("a", to: 5)
        sd.set("b", to: 0x11223344)
        XCTAssertEqual(Array(sd.data.rawBytes[0..<2]), [0x00, 0x05])
        XCTAssertEqual(Array(sd.data.rawBytes[2..<6]), [0x11, 0x22, 0x33, 0x44])
    }

    // set → get round-trips every width, signed and unsigned, in both orders,
    // including negatives (sign-extension) and the 24-bit widths.
    func testSetGetRoundTripAllWidths() {
        let props: [StructDefinition.Property] = [
            .uint8(name: "u8"), .int8(name: "i8"),
            .uint16(name: "u16"), .int16(name: "i16"),
            .uint24(name: "u24"), .int24(name: "i24"),
            .uint32(name: "u32"), .int32(name: "i32"),
            .int64(name: "i64"),
        ]
        let cases: [(String, Int)] = [
            ("u8", 0xAB), ("i8", -5),
            ("u16", 0xBEEF), ("i16", -32768),
            ("u24", 0xABCDEF), ("i24", -1),
            ("u32", 0x11223344), ("i32", -123456),
            ("i64", -9_000_000_000),
        ]
        for order in [ByteOrder.big, .little] {
            let sd = make(props, order)
            for (key, value) in cases { sd.set(key, to: value) }
            for (key, value) in cases {
                let got: Int? = sd.get(key)
                XCTAssertEqual(got, value, "\(key) round-trip failed for \(order)")
            }
        }
    }

    // Signed int24 = -1 is 0xFFFFFF on disk in either order, and reads back
    // as -1 (the old encode path zero-extended it to 16777215).
    func testInt24SignExtension() {
        for order in [ByteOrder.big, .little] {
            let sd = make([.int24(name: "v")], order)
            sd.set("v", to: -1)
            XCTAssertEqual(sd.data.rawBytes, [0xFF, 0xFF, 0xFF], "int24 -1 bytes for \(order)")
            let neg: Int? = sd.get("v")
            XCTAssertEqual(neg, -1, "int24 -1 read for \(order)")

            sd.set("v", to: 0x7FABCD)
            let pos: Int? = sd.get("v")
            XCTAssertEqual(pos, 0x7FABCD, "int24 positive read for \(order)")
        }
    }
}
