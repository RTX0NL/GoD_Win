//
//  StructErrorTests.swift
//
//  Exercises the StructError descriptions (missing key / type mismatch),
//  including the throwing dynamic-member accessors that raise them.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructErrorTests: XCTestCase {

    private func sample() -> StructData {
        let def = StructDefinition(
            name: "Mon",
            wordSize: 1,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "hp"),
                .uint16(name: "attack"),
            ]
        )
        return StructData(definition: def, data: GoDData(byteStream: [0x10, 0x00, 0x20], byteOrder: .big))
    }

    func testMissingKeyDescriptionListsKeys() {
        let error = StructError.MissingKey(key: "speed", struct: sample(), .init())
        let desc = error.description
        XCTAssertTrue(desc.contains("Couldn't find key 'speed'"))
        XCTAssertTrue(desc.contains("Mon"))
        XCTAssertTrue(desc.contains("hp"))
        XCTAssertTrue(desc.contains("attack"))
    }

    func testTypeMismatchDescription() {
        let error = StructError.TypeMismatch(
            key: "hp",
            propertyType: .uint8,
            type: String.self,
            struct: sample(),
            .init()
        )
        let desc = error.description
        XCTAssertTrue(desc.contains("Couldn't convert key 'hp'"))
        XCTAssertTrue(desc.contains("String"))
        XCTAssertTrue(desc.contains("Mon"))
    }

    func testThrowingDynamicMemberRaisesMissingKey() {
        let sut = sample()
        XCTAssertThrowsError(try sut[dynamicMember: "nonexistent"] as GoDData) { error in
            guard case StructError.MissingKey(let key, _, _) = error else {
                return XCTFail("expected MissingKey, got \(error)")
            }
            XCTAssertEqual(key, "nonexistent")
        }
    }

    func testThrowingEnumAccessorOnNonEnumRaisesTypeMismatch() {
        let sut = sample()
        XCTAssertThrowsError(try sut[dynamicMember: "hp"] as Enum.Case) { error in
            guard case StructError.TypeMismatch = error else {
                return XCTFail("expected TypeMismatch, got \(error)")
            }
        }
    }
}
