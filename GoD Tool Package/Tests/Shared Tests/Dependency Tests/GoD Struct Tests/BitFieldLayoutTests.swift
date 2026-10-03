//
//  BitFieldLayoutTests.swift
//
//  The masking arithmetic and the validation rules, on their own — no
//  `GoDData`, no serialization. Bit 0 is the most significant bit of the
//  container, so every expectation here is written against a mask rather
//  than against a shift count: a sign error in the shift would still
//  produce a plausible number, and only the mask says which bits were
//  meant.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class BitFieldLayoutTests: XCTestCase {

    private let kinds = Enum(
        name: "Kinds",
        allowUnknownCases: true,
        values: [
            .init(name: "None", rawValue: 0),
            .init(name: "Field", rawValue: 1),
            .init(name: "Battle", rawValue: 2),
        ],
        propertyType: .uint8
    )

    // MARK: - Numbering

    func testBitZeroIsTheMostSignificantBit() {
        let top = BitFieldLayout.Field.flag(name: "top", bit: 0)
        let bottom = BitFieldLayout.Field.flag(name: "bottom", bit: 7)
        XCTAssertEqual(top.mask(inStorageOf: 8), 0x80)
        XCTAssertEqual(bottom.mask(inStorageOf: 8), 0x01)
        XCTAssertEqual(top.shift(inStorageOf: 8), 7)
        XCTAssertEqual(bottom.shift(inStorageOf: 8), 0)
    }

    func testTopThreeBitsOfAByte() {
        let field = BitFieldLayout.Field.number(name: "kind", bits: 0...2)
        XCTAssertEqual(field.mask(inStorageOf: 8), 0xE0)
        XCTAssertEqual(field.extract(fromStorage: 0xA0, bitCount: 8), 5)
        XCTAssertEqual(field.insert(5, intoStorage: 0x0F, bitCount: 8), 0xAF)
    }

    func testNumberingIsRelativeToTheContainerNotTheByte() {
        // Bit 0 of a uint16 is 0x8000, not 0x80.
        let field = BitFieldLayout.Field.flag(name: "top", bit: 0)
        XCTAssertEqual(field.mask(inStorageOf: 16), 0x8000)
        XCTAssertEqual(field.mask(inStorageOf: 32), 0x8000_0000)
        XCTAssertEqual(field.mask(inStorageOf: 64), 0x8000_0000_0000_0000)
    }

    func testPowerPCBitNumbersMapAcrossForA32BitContainer() {
        // `rlwinm` counts from the MSB of the register, so for a word the
        // index is ours unchanged — this is why MSB-0 was chosen.
        let field = BitFieldLayout.Field.flag(name: "bromide", bit: 28)
        XCTAssertEqual(field.mask(inStorageOf: 32), 0x08)
    }

    func testEightBitContainerIsRlwinmIndexMinusTwentyFour() {
        // A byte loaded by `lbz` lands in bits 24...31 of the register, so
        // `Pokemon.md`'s `fuseiFlag` (mask 0x20, register bit 26) is bit 2
        // of the byte here.
        let field = BitFieldLayout.Field.flag(name: "fusei", bit: 26 - 24)
        XCTAssertEqual(field.mask(inStorageOf: 8), 0x20)
    }

    // MARK: - Widths

    func testEveryStorageWidthRoundTrips() {
        for storage in IntegerProperties.allCases where !storage.isSigned {
            let bitCount = storage.length * 8
            let field = BitFieldLayout.Field.number(name: "low", bits: (bitCount - 4)...(bitCount - 1))
            let layout = BitFieldLayout(storage: storage, fields: [
                .number(name: "high", bits: 0...(bitCount - 5)),
                field,
            ])
            XCTAssertEqual(layout.issues, [], "\(storage) should validate")
            let stored = layout.insert(0xB, for: field, intoStorage: 0)
            XCTAssertEqual(stored, 0xB)
            XCTAssertEqual(layout.extract(field, fromStorage: stored), 0xB)
        }
    }

    func testAFullWidthFieldDoesNotOverflowItsMask() {
        let field = BitFieldLayout.Field.number(name: "whole", bits: 0...63)
        XCTAssertEqual(field.mask(inStorageOf: 64), UInt64.max)
        XCTAssertEqual(field.extract(fromStorage: UInt64.max, bitCount: 64), -1)
    }

    func testSignedFieldSignExtendsFromItsOwnTopBit() {
        let field = BitFieldLayout.Field.number(name: "delta", bits: 4...7, signed: true)
        XCTAssertEqual(field.extract(fromStorage: 0x0F, bitCount: 8), -1)
        XCTAssertEqual(field.extract(fromStorage: 0x08, bitCount: 8), -8)
        XCTAssertEqual(field.extract(fromStorage: 0x07, bitCount: 8), 7)
        XCTAssertEqual(field.insert(-1, intoStorage: 0, bitCount: 8), 0x0F)
    }

    func testUnsignedFieldDoesNotSignExtend() {
        let field = BitFieldLayout.Field.number(name: "value", bits: 4...7)
        XCTAssertEqual(field.extract(fromStorage: 0x0F, bitCount: 8), 15)
    }

    func testAnOverWideValueIsTruncatedRatherThanReachingANeighbour() {
        let field = BitFieldLayout.Field.number(name: "two", bits: 6...7)
        XCTAssertEqual(field.insert(0xFF, intoStorage: 0x00, bitCount: 8), 0x03)
    }

    func testInsertLeavesEveryOtherBitAlone() {
        let field = BitFieldLayout.Field.number(name: "middle", bits: 3...4)
        XCTAssertEqual(field.insert(0, intoStorage: 0xFF, bitCount: 8), 0xE7)
        XCTAssertEqual(field.insert(3, intoStorage: 0x00, bitCount: 8), 0x18)
    }

    // MARK: - Range spelling

    func testRangeParsing() {
        XCTAssertEqual(BitFieldLayout.range(from: "0:2"), 0...2)
        XCTAssertEqual(BitFieldLayout.range(from: "3"), 3...3)
        XCTAssertEqual(BitFieldLayout.range(from: " 4 : 6 "), 4...6)
        XCTAssertEqual(BitFieldLayout.range(from: "7:7"), 7...7)
    }

    func testRangeParsingRefusesAnythingAmbiguous() {
        // A descending spelling is refused rather than reversed: one
        // notation, so a declaration can't be read two ways.
        XCTAssertNil(BitFieldLayout.range(from: "2:0"))
        XCTAssertNil(BitFieldLayout.range(from: ""))
        XCTAssertNil(BitFieldLayout.range(from: ":"))
        XCTAssertNil(BitFieldLayout.range(from: "1:"))
        XCTAssertNil(BitFieldLayout.range(from: "-1:2"))
        XCTAssertNil(BitFieldLayout.range(from: "0:1:2"))
        XCTAssertNil(BitFieldLayout.range(from: "0x1"))
        XCTAssertNil(BitFieldLayout.range(from: "two"))
    }

    func testRangeTextRoundTrips() {
        for text in ["0", "7", "0:2", "4:6", "0:15"] {
            let range = BitFieldLayout.range(from: text)
            XCTAssertEqual(range.map(BitFieldLayout.text(for:)), text)
        }
    }

    // MARK: - Validation

    private func layout(_ fields: [BitFieldLayout.Field], storage: IntegerProperties = .uint8) -> BitFieldLayout {
        BitFieldLayout(storage: storage, fields: fields)
    }

    func testATilingLayoutHasNoIssues() {
        XCTAssertEqual(layout([
            .abstraction(name: "kind", bits: 0...2, enumeration: kinds),
            .flag(name: "visible", bit: 3),
            .number(name: "collision", bits: 4...5),
            .number(name: "unknown_6_7", bits: 6...7),
        ]).issues, [])
    }

    func testAGapIsReported() {
        XCTAssertEqual(
            layout([.flag(name: "top", bit: 0), .number(name: "rest", bits: 2...7)]).issues,
            [.uncoveredBits(1...1)]
        )
    }

    func testATrailingGapIsReported() {
        XCTAssertEqual(
            layout([.number(name: "high", bits: 0...3)]).issues,
            [.uncoveredBits(4...7)]
        )
    }

    func testAnOverlapIsReported() {
        XCTAssertEqual(
            layout([.number(name: "a", bits: 0...4), .number(name: "b", bits: 3...7)]).issues,
            [.overlappingFields(field: "b", with: "a")]
        )
    }

    func testOutOfOrderDeclarationIsReported() {
        XCTAssertEqual(
            layout([.number(name: "low", bits: 4...7), .number(name: "high", bits: 0...3)]).issues,
            [.fieldsOutOfOrder(field: "high", after: "low")]
        )
    }

    func testARangePastTheStorageIsReported() {
        XCTAssertEqual(
            layout([.number(name: "a", bits: 0...7), .flag(name: "b", bit: 8)]).issues,
            [.rangeOutsideStorage(field: "b", bits: 8...8, storageBits: 8)]
        )
    }

    func testAWideBooleanIsReported() {
        let issues = layout([
            .init(name: "pair", bits: 0...1, value: .boolean),
            .number(name: "rest", bits: 2...7),
        ]).issues
        XCTAssertEqual(issues, [.booleanWiderThanOneBit(field: "pair", width: 2)])
    }

    func testAnEnumCaseTooWideForItsRunIsReported() {
        // The run's width decides the field's size, so a case the run
        // can't hold would read back as something else entirely.
        let issues = layout([
            .abstraction(name: "kind", bits: 0...0, enumeration: kinds),
            .number(name: "rest", bits: 1...7),
        ]).issues
        XCTAssertEqual(issues, [.enumCaseOutsideRange(
            field: "kind", enumName: "Kinds", caseName: "Battle", rawValue: 2, width: 1
        )])
    }

    func testDuplicateAndInvalidNamesAreReported() {
        let issues = layout([
            .number(name: "a", bits: 0...3),
            .number(name: "a", bits: 4...7),
        ]).issues
        XCTAssertEqual(issues, [.duplicateFieldName("a")])

        let invalid = layout([.number(name: "1st", bits: 0...7)]).issues
        XCTAssertEqual(invalid, [.invalidFieldName("1st")])
    }

    func testAnEmptyLayoutIsReported() {
        XCTAssertEqual(layout([]).issues, [.noFields])
    }

    func testEveryIssueHasAMessage() {
        let issues: [BitFieldLayout.Issue] = [
            .rangeOutsideStorage(field: "a", bits: 0...1, storageBits: 8),
            .fieldsOutOfOrder(field: "a", after: "b"),
            .overlappingFields(field: "a", with: "b"),
            .uncoveredBits(1...1),
            .booleanWiderThanOneBit(field: "a", width: 2),
            .enumCaseOutsideRange(field: "a", enumName: "E", caseName: "C", rawValue: 9, width: 2),
            .invalidFieldName("1"),
            .duplicateFieldName("a"),
            .noFields,
        ]
        for issue in issues {
            XCTAssertFalse(issue.description.isEmpty, "\(issue) has no message")
        }
    }

    // MARK: - Property geometry

    func testABitsPropertyOccupiesItsStorage() {
        for storage in [IntegerProperties.uint8, .uint16, .uint24, .uint32, .uint64] {
            let bitCount = storage.length * 8
            let property = StructProperty.bits(
                layout([.number(name: "whole", bits: 0...(bitCount - 1))], storage: storage)
            )
            XCTAssertEqual(property.length, storage.length)
            XCTAssertEqual(
                property.alignment,
                StructProperty.primitive(.integer(storage)).alignment
            )
        }
    }

    func testValuesReadsEveryField() {
        let layout = layout([
            .number(name: "kind", bits: 0...2),
            .flag(name: "visible", bit: 3),
            .number(name: "rest", bits: 4...7),
        ])
        XCTAssertEqual(layout.values(inStorage: 0xA5), ["kind": 5, "visible": 0, "rest": 5])
    }

    func testFieldLookupByName() {
        let layout = layout([.number(name: "kind", bits: 0...7)])
        XCTAssertEqual(layout.field(named: "kind")?.name, "kind")
        XCTAssertNil(layout.field(named: "Kind"))
    }
}
