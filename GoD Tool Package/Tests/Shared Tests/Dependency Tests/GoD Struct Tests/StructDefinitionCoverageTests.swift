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

    func testKeyMatchingIgnoresSpacesUnderscoresAndCase() {
        let def = StructDefinition(name: "T", wordSize: 1, alignmentStyle: .none,
                                   properties: [.uint8(name: "MaxHP")])
        // Property.init strips spaces from the stored name; lookup then
        // normalises underscores + case.
        XCTAssertEqual(def.offset(for: "max_hp"), 0)
        XCTAssertEqual(def.offset(for: "MAXHP"), 0)
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

    func testPropertyInitStripsSpaces() {
        let p = StructDefinition.Property(name: "some name", type: .uint8)
        XCTAssertEqual(p.name, "somename")
    }

    func testDefinitionInitStripsSpacesFromName() {
        let def = StructDefinition(name: "My Struct", wordSize: 1, alignmentStyle: .none, properties: [])
        XCTAssertEqual(def.name, "MyStruct")
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
