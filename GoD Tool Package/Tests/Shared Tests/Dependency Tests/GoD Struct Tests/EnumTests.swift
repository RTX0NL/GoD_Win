//
//  EnumTests.swift
//
//  Covers the Enum definition type: case lookup by name and raw value,
//  unknown-case handling, the Case string codec, the throwing dynamic
//  member / index subscripts, and the error descriptions.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class EnumTests: XCTestCase {

    private let colors = Enum(
        name: "Colors",
        allowUnknownCases: false,
        values: [
            .init(name: "Red", rawValue: 0),
            .init(name: "Green", rawValue: 1),
            .init(name: "Blue", rawValue: 2),
        ],
        propertyType: .uint8
    )

    private let openColors = Enum(
        name: "Open Colors",
        allowUnknownCases: true,
        values: [.init(name: "Red", rawValue: 0)],
        propertyType: .uint16
    )

    // MARK: - get(name:)

    func testGetByNameCaseInsensitive() throws {
        XCTAssertEqual(try colors.get("green").rawValue, 1)
        XCTAssertEqual(try colors.get("GREEN").rawValue, 1)
        XCTAssertEqual(try colors.get("Green").name, "Green")
    }

    func testGetByUnknownNameThrows() {
        XCTAssertThrowsError(try colors.get("Purple")) { error in
            guard case Enum.Errors.InvalidEnumCase(let caseName, let enumeration, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(caseName, "Purple")
            XCTAssertEqual(enumeration.name, "Colors")
        }
    }

    // MARK: - get(rawValue:)

    func testGetByRawValue() throws {
        XCTAssertEqual(try colors.get(2).name, "Blue")
    }

    func testGetByUnknownRawValueThrowsWhenClosed() {
        XCTAssertThrowsError(try colors.get(99)) { error in
            guard case Enum.Errors.InvalidEnumIndex(let index, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(index, 99)
        }
    }

    func testGetByUnknownRawValueSynthesizesWhenOpen() throws {
        // Spaces in the enum name become underscores in the synthesized case name.
        let unknown = try openColors.get(42)
        XCTAssertEqual(unknown.name, "Open_Colors_42")
        XCTAssertEqual(unknown.rawValue, 42)
    }

    // MARK: - Subscripts

    func testDynamicMemberSubscript() throws {
        XCTAssertEqual(try colors.red.rawValue, 0)
    }

    func testIndexSubscript() throws {
        XCTAssertEqual(try colors[1].name, "Green")
    }

    func testIndexSubscriptThrowsWhenClosed() {
        XCTAssertThrowsError(try colors[7])
    }

    // MARK: - Case Codable

    func testCaseEncodesAsNameEqualsValue() throws {
        let data = try XCTUnwrap(Enum.Case(name: "Half", rawValue: 2).encodeJSONString())
        XCTAssertEqual(data, "\"Half = 2\"")
    }

    func testCaseDecodesFromString() throws {
        let cases = try JSONDecoder().decode([Enum.Case].self, from: #"["Red = 0","Blue = 2"]"#.data(format: .utf8))
        XCTAssertEqual(cases, [.init(name: "Red", rawValue: 0), .init(name: "Blue", rawValue: 2)])
    }

    func testCaseDecodeRejectsMalformedString() {
        XCTAssertThrowsError(try JSONDecoder().decode([Enum.Case].self, from: #"["NoEquals"]"#.data(format: .utf8)))
    }

    // MARK: - Enum Codable round trip

    func testEnumRoundTripsThroughJSON() throws {
        let json = try XCTUnwrap(colors.encodeJSON())
        let decoded = try JSONDecoder().decode(Enum.self, from: json)
        XCTAssertEqual(decoded, colors)
        XCTAssertEqual(decoded.propertyType, .uint8)
        XCTAssertEqual(decoded.values.count, 3)
    }

    // MARK: - Case name validation

    func testValidCaseNames() {
        for name in ["Red", "_reserved", "B1_1.fsys", "D1_garage_B2_1.fsys", "Mr.Mime", "Farfetch'd", "U-turn", "x", "_"] {
            XCTAssertTrue(Enum.isValidCaseName(name), "expected '\(name)' to be valid")
        }
    }

    func testInvalidCaseNames() {
        // Leading digit / sign: indistinguishable from the raw value the name
        // stands for. Whitespace: breaks the "<name> = <rawValue>" codec.
        for name in ["", "22", "0x10", "2ndStage", "-1", "+1", " Red", "Red ", "Value 1", "HP = Max", "two\nlines", "tab\there"] {
            XCTAssertFalse(Enum.isValidCaseName(name), "expected '\(name)' to be invalid")
        }
    }

    func testInvalidCaseNamesAreReportedSortedAndDeduped() {
        let broken = Enum(
            name: "Broken",
            allowUnknownCases: false,
            values: [
                .init(name: "Fine", rawValue: 0),
                .init(name: "Value 1", rawValue: 1),
                .init(name: "2nd", rawValue: 2),
            ],
            propertyType: .uint8
        )
        XCTAssertEqual(broken.invalidCaseNames, ["2nd", "Value 1"])
        XCTAssertTrue(colors.invalidCaseNames.isEmpty)
    }

    func testSynthesizedUnknownCaseNameIsValid() throws {
        // The synthesized form folds the enum name's spaces to underscores
        // precisely so the result is a legal case name.
        XCTAssertTrue(Enum.isValidCaseName(try openColors.get(42).name))
    }

    // MARK: - Error descriptions

    func testErrorDescriptions() {
        let idxDesc = Enum.Errors.InvalidEnumIndex(index: 5, enumeration: colors, .init()).description
        XCTAssertTrue(idxDesc.contains("Invalid index '5'"))
        XCTAssertTrue(idxDesc.contains("Colors"))

        let caseDesc = Enum.Errors.InvalidEnumCase(caseName: "Pink", enumeration: colors, .init()).description
        XCTAssertTrue(caseDesc.contains("Invalid case 'Pink'"))

        let defDesc = Enum.Errors.InvalidEnumCaseDefinition(input: "junk", .init()).description
        XCTAssertTrue(defDesc.contains("junk"))
        XCTAssertTrue(defDesc.contains("Expected format"))
    }
}
