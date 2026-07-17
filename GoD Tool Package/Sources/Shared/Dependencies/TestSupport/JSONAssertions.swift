//
//  JSONAssertions.swift
//
//  Semantic JSON comparison so decode tests aren't coupled to the exact
//  whitespace / key ordering a given `JSONEncoder` happens to emit. Keys
//  are compared order-insensitively; array order is preserved (it's
//  meaningful — e.g. MSG entry order, ATX frame order).
//

import XCTest
import Foundation

/// Asserts two JSON documents are semantically equal (object key order
/// ignored, array order significant, values compared after normalisation).
public func assertJSONEqual(
    _ actual: Data,
    _ expected: Data,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let label = message().isEmpty ? "" : "\(message()): "
    let opts: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed]

    guard let actualObj = try? JSONSerialization.jsonObject(with: actual, options: [.fragmentsAllowed]) else {
        XCTFail("\(label)actual is not valid JSON", file: file, line: line); return
    }
    guard let expectedObj = try? JSONSerialization.jsonObject(with: expected, options: [.fragmentsAllowed]) else {
        XCTFail("\(label)expected is not valid JSON", file: file, line: line); return
    }
    guard let actualNorm = try? JSONSerialization.data(withJSONObject: actualObj, options: opts),
          let expectedNorm = try? JSONSerialization.data(withJSONObject: expectedObj, options: opts) else {
        XCTFail("\(label)failed to normalise JSON for comparison", file: file, line: line); return
    }

    if actualNorm != expectedNorm {
        let a = String(data: actualNorm, encoding: .utf8) ?? "<non-utf8>"
        let e = String(data: expectedNorm, encoding: .utf8) ?? "<non-utf8>"
        XCTFail("\(label)JSON differs.\n  expected: \(e)\n  actual:   \(a)", file: file, line: line)
    }
}
