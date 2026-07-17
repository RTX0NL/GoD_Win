//
//  CacheTests.swift
//
//  Coverage for the NSCache-backed Cache wrapper.
//

import Foundation
import XCTest
@testable import GoDFoundation

private final class Box {
    let value: Int
    init(_ value: Int) { self.value = value }
}

final class CacheTests: XCTestCase {

    func testSetAndGet() {
        let cache = Cache<Box>()
        cache["key"] = Box(42)
        XCTAssertEqual(cache["key"]?.value, 42)
    }

    func testMissingKeyReturnsNil() {
        let cache = Cache<Box>()
        XCTAssertNil(cache["absent"])
    }

    func testSetNilRemovesObject() {
        let cache = Cache<Box>()
        cache["key"] = Box(1)
        XCTAssertNotNil(cache["key"])
        cache["key"] = nil
        XCTAssertNil(cache["key"])
    }

    func testOverwriteValue() {
        let cache = Cache<Box>()
        cache["key"] = Box(1)
        cache["key"] = Box(2)
        XCTAssertEqual(cache["key"]?.value, 2)
    }

    func testResetClearsAll() {
        let cache = Cache<Box>()
        cache["a"] = Box(1)
        cache["b"] = Box(2)
        cache.reset()
        XCTAssertNil(cache["a"])
        XCTAssertNil(cache["b"])
    }
}
