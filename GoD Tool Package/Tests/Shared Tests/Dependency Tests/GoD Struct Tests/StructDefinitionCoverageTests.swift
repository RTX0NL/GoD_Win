//
//  StructDefinitionCoverageTests.swift
//
//  Edge cases for StructDefinition not covered by StructDefinitionTests:
//  keypath navigation failures, longestAlignment with label/padding/enum
//  members, and uint32SubstitutedDefinition (incl. nested + array label
//  substitution).
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructDefinitionCoverageTests: XCTestCase {

    // MARK: - offset / property edge cases

    func testOffsetForMissingKeyIsNil() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a")])
        XCTAssertNil(def.offset(for: "missing"))
        XCTAssertNil(def.property(for: "missing"))
    }

    func testOffsetForEmptyKeypathIsNil() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a")])
        XCTAssertNil(def.offset(for: ""))
        XCTAssertNil(def.property(for: ""))
    }

    func testKeypathIntoNonSubStructIsNil() {
        // "a" is a scalar; descending into it (a.b) must fail cleanly.
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a"), .uint16(name: "b")])
        XCTAssertNil(def.offset(for: "a.b"))
        XCTAssertNil(def.property(for: "a.b"))
    }

    func testKeypathWithUnknownSubMemberIsNil() {
        let inner = StructDefinition(name: "Inner", wordSize: 1, alignmentStyle: .none,
                                     properties: [.uint8(name: "x")])
        let def = StructDefinition(name: "Outer", wordSize: 1, alignmentStyle: .none,
                                   properties: [.subStruct(name: "sub", defintion: inner)])
        XCTAssertNil(def.offset(for: "sub.nope"))
        XCTAssertNil(def.property(for: "sub.nope"))
        // Valid sub member still resolves.
        XCTAssertEqual(def.offset(for: "sub.x"), 0)
        XCTAssertEqual(def.property(for: "sub.x"), .uint8)
    }

    /// Lookup is exact: a property is addressed by the name it was declared
    /// with, and nothing else. Folding underscores and case used to make
    /// `MaxHP`, `max_hp` and `maxhp` the same field, so a definition holding
    /// two of them silently wrote to whichever came first.
    func testKeyMatchingIsExact() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "MaxHP")])
        XCTAssertEqual(def.offset(for: "MaxHP"), 0)
        XCTAssertNil(def.offset(for: "max_hp"))
        XCTAssertNil(def.offset(for: "MAXHP"))
        XCTAssertNil(def.offset(for: "maxhp"))
    }

    /// Near misses carry a suggestion so an exact-match failure is
    /// diagnosable rather than just "field absent".
    func testClosestPropertyNameSuggestsTheDeclaredSpelling() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "file_data_pointer")])
        XCTAssertEqual(def.closestPropertyName(to: "fileDataPointer"), "file_data_pointer")
        XCTAssertEqual(def.closestPropertyName(to: "FILE_DATA_POINTER"), "file_data_pointer")
        // An exact hit isn't a near miss, and an unrelated name has no match.
        XCTAssertNil(def.closestPropertyName(to: "file_data_pointer"))
        XCTAssertNil(def.closestPropertyName(to: "somethingElse"))
    }

    // MARK: - Name validation

    func testValidPropertyNames() {
        for name in ["a", "_", "_leading", "file_data_pointer", "MaxHP", "x1", "BSS_RAM_address"] {
            XCTAssertTrue(StructDefinition.isValidPropertyName(name), "\(name) should be valid")
        }
    }

    func testInvalidPropertyNames() {
        for name in ["", "1leading", "has space", "has-dash", "has.dot", "has$sign", "a b"] {
            XCTAssertFalse(StructDefinition.isValidPropertyName(name), "\(name) should be invalid")
        }
    }

    func testInvalidPropertyNamesAreReported() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "ok"),
                                                .uint8(name: "not ok"),
                                                .uint8(name: "9bad")])
        XCTAssertEqual(def.invalidPropertyNames, ["9bad", "not ok"])
    }

    func testDuplicatePropertyNamesAreReported() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a"),
                                                .uint8(name: "b"),
                                                .uint8(name: "a")])
        XCTAssertEqual(def.duplicatePropertyNames, ["a"])
    }

    /// Padding is named `padding` for every run by design and is addressed
    /// positionally, so repeats of it aren't duplicates.
    func testRepeatedPaddingIsNotADuplicate() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.padding(length: 2),
                                                .uint8(name: "a"),
                                                .padding(length: 4)])
        XCTAssertEqual(def.duplicatePropertyNames, [])
    }

    // MARK: - longestAlignment

    func testLongestAlignmentWithLabelPaddingEnum() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .cStyle,
                                   properties: [
                                    .uint8(name: "a"),
                                    .label(name: "ptr"),               // alignment 4
                                    .padding(length: 3),               // 1
                                    .abstraction(name: "e", enumeration: weekEnum), // 1
                                   ])
        XCTAssertEqual(def.longestAlignment, 4)
    }

    func testLongestAlignmentEmptyIsZero() {
        let def = StructDefinition(name: "Empty", wordSize: 1, alignmentStyle: .cStyle, properties: [])
        XCTAssertEqual(def.longestAlignment, 0)
        // NOTE: `def.length` is deliberately NOT evaluated here — for an
        // empty (or all-zero-length) cStyle struct, longestAlignment == 0
        // and `length`'s final `sum % longestAlignment` traps with a
        // division-by-zero. Documented as a bug in the final report.
    }

    func testEmptyNoneStyleLengthIsZero() {
        let def = StructDefinition(name: "Empty", wordSize: 1, alignmentStyle: .none, properties: [])
        XCTAssertEqual(def.length, 0)
    }

    func testLongestAlignmentArrayElement() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .cStyle,
                                   properties: [.array(name: "a", count: 4, of: .uint32)])
        XCTAssertEqual(def.longestAlignment, 4)
    }

    // MARK: - length with label

    func testLengthCountsLabelAsFourBytes() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a"), .label(name: "ptr")])
        XCTAssertEqual(def.length, 5)
    }

    // MARK: - Property init

    /// Names are stored verbatim. Silently stripping spaces rewrote the
    /// caller's name instead of rejecting it, so the stored schema no longer
    /// matched what the author wrote; invalid names are reported by
    /// `invalidPropertyNames` and rejected when the engine loads.
    func testPropertyInitKeepsTheNameVerbatim() {
        let p = StructDefinition.Property(name: "some name", type: .uint8)
        XCTAssertEqual(p.name, "some name")
        XCTAssertFalse(StructDefinition.isValidPropertyName(p.name))
    }

    func testDefinitionInitKeepsTheNameVerbatim() {
        let def = StructDefinition(name: "My Struct", wordSize: 1, alignmentStyle: .none, properties: [])
        XCTAssertEqual(def.name, "My Struct")
    }

    // MARK: - uint32SubstitutedDefinition

    func testLabelSubstitutedToUInt32() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "a"), .label(name: "ptr")])
        let subbed = def.uint32SubstitutedDefinition()
        XCTAssertEqual(subbed.property(for: "ptr"), .uint32)
        XCTAssertEqual(subbed.property(for: "a"), .uint8)
        // Length unchanged (label was already 4 bytes).
        XCTAssertEqual(subbed.length, def.length)
    }

    func testLabelSubstitutionRecursesIntoSubStructAndArray() {
        let inner = StructDefinition(name: "Inner", wordSize: 1, alignmentStyle: .none,
                                     properties: [.label(name: "innerPtr"), .uint8(name: "x")])
        let def = StructDefinition(name: "Outer", wordSize: 1, alignmentStyle: .none,
                                   properties: [
                                    .subStruct(name: "sub", defintion: inner),
                                    .array(name: "ptrs", count: 3, of: .label),
                                   ])
        let subbed = def.uint32SubstitutedDefinition()
        XCTAssertEqual(subbed.property(for: "sub.innerPtr"), .uint32)
        XCTAssertEqual(subbed.property(for: "ptrs"), .array(.uint32, count: 3))
    }
}
