//
//  StructMapFieldTests.swift
//
//  Covers the StructField enum: its CustomStringConvertible rendering
//  (which the StructMap encoder relies on) and the convenience static
//  accessors.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructMapFieldTests: XCTestCase {

    func testPrimitiveDescriptions() {
        XCTAssertEqual(StructField.uint8.description, "uint8")
        XCTAssertEqual(StructField.int8.description, "int8")
        XCTAssertEqual(StructField.uint16.description, "uint16")
        XCTAssertEqual(StructField.int16.description, "int16")
        XCTAssertEqual(StructField.uint24.description, "uint24")
        XCTAssertEqual(StructField.int24.description, "int24")
        XCTAssertEqual(StructField.uint32.description, "uint32")
        XCTAssertEqual(StructField.int32.description, "int32")
        XCTAssertEqual(StructField.uint64.description, "uint64")
        XCTAssertEqual(StructField.int64.description, "int64")
        XCTAssertEqual(StructField.float.description, "float")
        XCTAssertEqual(StructField.double.description, "double")
        XCTAssertEqual(StructField.losslessFloat.description, "lossless_float")
        XCTAssertEqual(StructField.losslessDouble.description, "lossless_double")
        XCTAssertEqual(StructField.boolean.description, "boolean")
        XCTAssertEqual(StructField.void.description, "void")
    }

    func testCharacterDescriptions() {
        XCTAssertEqual(StructField.primitive(.character(.utf8)).description, "char_utf8")
        XCTAssertEqual(StructField.primitive(.character(.gsColo)).description, "char_gsColo")
    }

    func testArrayDescription() {
        XCTAssertEqual(StructField.array(.uint16, count: 3).description, "uint16[3]")
    }

    func testNestedArrayDescription() {
        XCTAssertEqual(StructField.array(.array(.uint8, count: 2), count: 3).description, "uint8[2][3]")
    }

    func testSubStructDescription() {
        XCTAssertEqual(StructField.subStruct(name: "Inner").description, "struct Inner")
    }

    func testEnumerationDescription() {
        XCTAssertEqual(StructField.enumeration(name: "Colors").description, "enum Colors")
    }

    func testLabelDescription() {
        XCTAssertEqual(StructField.label.description, "label")
        XCTAssertEqual(StructField.labelPointer, .label)
    }

    func testPaddingDescription() {
        XCTAssertEqual(StructField.padding(length: 12).description, "void[12]")
    }

    func testStringHelperExpandsToCharArray() {
        XCTAssertEqual(StructField.string(format: .utf16_big, length: 8),
                       .array(.primitive(.character(.utf16_big)), count: 8))
    }

    func testStaticAccessorsMapToPrimitives() {
        XCTAssertEqual(StructField.void, .primitive(.void))
        XCTAssertEqual(StructField.boolean, .primitive(.boolean))
        XCTAssertEqual(StructField.uint32, .primitive(.integer(.uint32)))
    }
}
