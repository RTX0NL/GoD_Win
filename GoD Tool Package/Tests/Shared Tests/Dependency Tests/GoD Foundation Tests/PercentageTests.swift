//
//  PercentageTests.swift
//
//  Coverage for the Percentage value type.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class PercentageTests: XCTestCase {

    func testValueInit() {
        XCTAssertEqual(Percentage(50.0).value, 50.0)
        XCTAssertEqual(Percentage(0.0).value, 0.0)
        XCTAssertEqual(Percentage(100.0).value, 100.0)
    }

    func testIntegerLiteral() {
        let p: Percentage = 25
        XCTAssertEqual(p.value, 25.0)
    }

    func testFloatLiteral() {
        let p: Percentage = 12.5
        XCTAssertEqual(p.value, 12.5)
    }

    func testDescriptionFormatsToOneDecimal() {
        XCTAssertEqual(Percentage(50.0).description, "50.0%")
        XCTAssertEqual(Percentage(33.333).description, "33.3%")
        XCTAssertEqual(Percentage(66.666).description, "66.7%")
        XCTAssertEqual(Percentage(0.0).description, "0.0%")
    }
}
