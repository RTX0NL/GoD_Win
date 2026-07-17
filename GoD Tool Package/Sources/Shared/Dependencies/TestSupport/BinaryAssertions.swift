//
//  BinaryAssertions.swift
//
//  Shared byte-buffer comparison that reports the first diverging offset,
//  extracting the `zip(...).enumerated().first { differ }?.offset` idiom
//  copy-pasted across the existing corpus round-trip tests into one place.
//

import XCTest
import GoDFoundation

/// Asserts two byte buffers are identical. On failure reports the first
/// diverging offset (in hex + decimal) with both bytes, or the length
/// mismatch when one is a prefix of the other.
public func assertBytesEqual(
    _ actual: [UInt8],
    _ expected: [UInt8],
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual == expected { return }

    let prefix = message()
    let label = prefix.isEmpty ? "" : "\(prefix): "
    let commonCount = min(actual.count, expected.count)
    let firstDiff = (0..<commonCount).first { actual[$0] != expected[$0] }

    if let i = firstDiff {
        XCTFail(
            "\(label)bytes differ at offset 0x\(hex(i)) (\(i)): "
            + "expected 0x\(hex(expected[i])), got 0x\(hex(actual[i])) "
            + "[expected \(expected.count) bytes, actual \(actual.count)]",
            file: file, line: line
        )
    } else {
        XCTFail(
            "\(label)byte length differs: expected \(expected.count), "
            + "actual \(actual.count) (the common \(commonCount)-byte prefix matches)",
            file: file, line: line
        )
    }
}

/// `GoDData` overload — compares the raw byte contents.
public func assertBytesEqual(
    _ actual: GoDData,
    _ expected: GoDData,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertBytesEqual(actual.rawBytes, expected.rawBytes, message(), file: file, line: line)
}

private func hex<T: BinaryInteger>(_ value: T) -> String {
    String(value, radix: 16, uppercase: true)
}
