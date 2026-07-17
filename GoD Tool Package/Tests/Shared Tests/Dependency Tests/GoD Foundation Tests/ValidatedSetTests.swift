//
//  ValidatedSetTests.swift
//
//  Coverage for ValidatedSet.init(validated:).
//

import Foundation
import XCTest
@testable import GoDFoundation

private struct Element: Nameable, Equatable {
    let name: String
}

private struct Registry: ValidatedSet {
    typealias Item = Element
    static var allItems: [Element] {
        [Element(name: "alpha"), Element(name: "beta"), Element(name: "gamma")]
    }
    let items: [Element]
    init(unchecked items: [Element]) {
        self.items = items
    }
}

final class ValidatedSetTests: XCTestCase {

    func testDefaultInitUsesAllItems() {
        let registry = Registry()
        XCTAssertEqual(registry.items, Registry.allItems)
    }

    func testValidatedSucceedsWhenAllNamesPresent() throws {
        let items = [Element(name: "alpha"), Element(name: "beta"), Element(name: "gamma")]
        let registry = try Registry(validated: items)
        XCTAssertEqual(registry.items.count, 3)
    }

    func testValidatedSucceedsWithExtraItems() throws {
        let items = Registry.allItems + [Element(name: "delta")]
        let registry = try Registry(validated: items)
        XCTAssertEqual(registry.items.count, 4)
    }

    func testValidatedThrowsWithMissingNames() {
        let items = [Element(name: "alpha")] // beta + gamma missing
        XCTAssertThrowsError(try Registry(validated: items)) { error in
            guard case let ValidatedSetError.missingElements(_, missing, _) = error else {
                return XCTFail("expected missingElements, got \(error)")
            }
            XCTAssertEqual(Set(missing), ["beta", "gamma"])
        }
    }

    func testValidatedErrorDescriptionMentionsMissing() {
        do {
            _ = try Registry(validated: [])
            XCTFail("expected throw")
        } catch let error as ValidatedSetError {
            XCTAssertTrue(error.description.contains("beta"))
            XCTAssertTrue(error.description.contains("gamma"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
