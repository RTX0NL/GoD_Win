//
//  StructPropertyCoverageTests.swift
//
//  Fills in the property-metadata paths not covered by
//  StructPropertyTests: IntegerProperties (isSigned / description /
//  from(name:) round trips), StructPrimitives (void, from(name:),
//  description), and StructProperty (alignment, label/padding/enum
//  length, descriptions).
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructPropertyCoverageTests: XCTestCase {

    // MARK: - IntegerProperties

    func testIntegerLengths() {
        XCTAssertEqual(IntegerProperties.uint8.length, 1)
        XCTAssertEqual(IntegerProperties.int24.length, 3)
        XCTAssertEqual(IntegerProperties.uint64.length, 8)
    }

    func testIntegerIsSigned() {
        for signed in [IntegerProperties.int8, .int16, .int24, .int32, .int64] {
            XCTAssertTrue(signed.isSigned, "\(signed) should be signed")
        }
        for unsigned in [IntegerProperties.uint8, .uint16, .uint24, .uint32, .uint64] {
            XCTAssertFalse(unsigned.isSigned, "\(unsigned) should be unsigned")
        }
    }

    func testIntegerDescriptionAndFromNameRoundTrip() {
        for prop in IntegerProperties.allCases {
            XCTAssertEqual(IntegerProperties.from(name: prop.description), prop)
        }
    }

    func testIntegerFromInvalidNameIsNil() {
        XCTAssertNil(IntegerProperties.from(name: "int128"))
        XCTAssertNil(IntegerProperties.from(name: ""))
    }

    // MARK: - StructPrimitives

    func testPrimitiveVoidLengthIsZero() {
        XCTAssertEqual(StructPrimitives.void.length, 0)
    }

    func testPrimitiveLosslessLengths() {
        XCTAssertEqual(StructPrimitives.lossless_float.length, 4)
        XCTAssertEqual(StructPrimitives.lossless_double.length, 8)
        XCTAssertEqual(StructPrimitives.boolean.length, 1)
    }

    func testPrimitiveDescriptionAndFromNameRoundTrip() {
        let primitives: [StructPrimitives] = [
            .void, .float, .double, .lossless_float, .lossless_double, .boolean,
            .integer(.uint8), .integer(.int64),
            .character(.utf8), .character(.utf16_big), .character(.ascii_big), .character(.unicode_big),
            .character(.utf16_little), .character(.ascii_little), .character(.unicode_little),
            .character(.gsColo), .character(.gsXD), .character(.gsPBR), .character(.gs),
        ]
        for prim in primitives {
            XCTAssertEqual(StructPrimitives.from(name: prim.description), prim, "round trip failed for \(prim)")
        }
    }

    func testPrimitiveCharAliasMapsToUInt8() {
        XCTAssertEqual(StructPrimitives.from(name: "char"), .integer(.uint8))
    }

    func testPrimitiveFromInvalidNameIsNil() {
        XCTAssertNil(StructPrimitives.from(name: "notAType"))
    }

    // MARK: - StructProperty length

    func testLabelLength() {
        XCTAssertEqual(StructProperty.label.length, 4)
    }

    func testPaddingLength() {
        XCTAssertEqual(StructProperty.padding(length: 7).length, 7)
    }

    func testEnumerationLengthFollowsBackingType() {
        XCTAssertEqual(StructProperty.enumeration(weekEnum).length, 1)          // uint8-backed
        XCTAssertEqual(StructProperty.enumeration(moonPhasesEnum).length, 1)    // int8-backed
    }

    func testStringHelperLength() {
        XCTAssertEqual(StructProperty.string(format: .utf16_big, length: 4).length, 8)
    }

    func testBitsLengthIsItsStorage() {
        for storage in [IntegerProperties.uint8, .uint16, .uint24, .uint32, .uint64] {
            let bitCount = storage.length * 8
            let property = StructProperty.bits(BitFieldLayout(
                storage: storage,
                fields: [.number(name: "whole", bits: 0...(bitCount - 1))]
            ))
            XCTAssertEqual(property.length, storage.length)
        }
    }

    // MARK: - StructProperty alignment

    func testAlignment24BitIsOne() {
        XCTAssertEqual(StructProperty.uint24.alignment, 1)
        XCTAssertEqual(StructProperty.int24.alignment, 1)
    }

    func testAlignmentPrimitiveIsWidth() {
        XCTAssertEqual(StructProperty.uint32.alignment, 4)
        XCTAssertEqual(StructProperty.primitive(.double).alignment, 8)
        XCTAssertEqual(StructProperty.primitive(.void).alignment, 1)   // max(0,1)
    }

    func testAlignmentArrayFollowsElementButOneWhenEmpty() {
        XCTAssertEqual(StructProperty.array(.uint32, count: 3).alignment, 4)
        XCTAssertEqual(StructProperty.array(.uint32, count: 0).alignment, 1)
    }

    func testAlignmentLabelAndPadding() {
        XCTAssertEqual(StructProperty.label.alignment, 4)
        XCTAssertEqual(StructProperty.padding(length: 5).alignment, 1)
    }

    func testAlignmentEnumeration() {
        XCTAssertEqual(StructProperty.enumeration(weekEnum).alignment, 1)
    }

    func testAlignmentBitsFollowsItsStorage() {
        func property(_ storage: IntegerProperties) -> StructProperty {
            .bits(BitFieldLayout(
                storage: storage,
                fields: [.number(name: "whole", bits: 0...(storage.length * 8 - 1))]
            ))
        }
        XCTAssertEqual(property(.uint8).alignment, 1)
        XCTAssertEqual(property(.uint16).alignment, 2)
        XCTAssertEqual(property(.uint24).alignment, 1)   // same as a uint24 field
        XCTAssertEqual(property(.uint32).alignment, 4)
    }

    func testAlignmentSubStruct() {
        let def = StructDefinition(name: "S", wordSize: 4, alignmentStyle: .cStyle,
                                   properties: [.uint8(name: "a"), .uint32(name: "b")])
        XCTAssertEqual(StructProperty.subStruct(def).alignment, def.longestAlignment)
        XCTAssertEqual(StructProperty.subStruct(def).alignment, 4)
    }

    // MARK: - StructProperty description

    func testDescriptions() {
        XCTAssertEqual(StructProperty.uint16.description, "uint16")
        XCTAssertEqual(StructProperty.array(.uint16, count: 3).description, "uint16[3]")
        XCTAssertEqual(StructProperty.label.description, "label")
        XCTAssertEqual(StructProperty.padding(length: 4).description, "void[4]")
        XCTAssertEqual(StructProperty.enumeration(weekEnum).description, "enum DaysOfWeek")
        let def = StructDefinition(name: "Inner", wordSize: 1, alignmentStyle: .none, properties: [.uint8(name: "x")])
        XCTAssertEqual(StructProperty.subStruct(def).description, "struct Inner")
        XCTAssertEqual(
            StructProperty.bits(BitFieldLayout(
                storage: .uint16,
                fields: [.number(name: "whole", bits: 0...15)]
            )).description,
            "bits(uint16)"
        )
    }

    func testStaticAccessors() {
        XCTAssertEqual(StructProperty.void, .primitive(.void))
        XCTAssertEqual(StructProperty.losslessFloat, .primitive(.lossless_float))
        XCTAssertEqual(StructProperty.labelPointer, .label)
    }
}
