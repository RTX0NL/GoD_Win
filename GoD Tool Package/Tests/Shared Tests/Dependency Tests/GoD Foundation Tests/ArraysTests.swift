//
//  ArraysTests.swift
//
//  Coverage for Array helpers in Arrays.swift.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class ArraysTests: XCTestCase {

    func testForEachIndexed() {
        let source = ["a", "b", "c"]
        var indices = [Int]()
        var elements = [String]()
        source.forEachIndexed { index, element in
            indices.append(index)
            elements.append(element)
        }
        XCTAssertEqual(indices, [0, 1, 2])
        XCTAssertEqual(elements, ["a", "b", "c"])
    }

    func testForEachIndexedEmpty() {
        var called = false
        ([] as [Int]).forEachIndexed { _, _ in called = true }
        XCTAssertFalse(called)
    }

    func testConditionalAppendWhenTrue() {
        let result = [1, 2].conditionalAppend(true, contents: [3, 4])
        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    func testConditionalAppendWhenFalse() {
        let result = [1, 2].conditionalAppend(false, contents: [3, 4])
        XCTAssertEqual(result, [1, 2])
    }
}
