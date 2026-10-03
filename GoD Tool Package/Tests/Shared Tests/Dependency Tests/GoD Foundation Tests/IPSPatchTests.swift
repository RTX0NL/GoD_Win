//
//  IPSPatchTests.swift
//
//  Coverage for the IPS codec: the record layout against hand-authored bytes,
//  run records, growth and truncation, the two offset rules the three-byte
//  field forces, and round trips cross-checked through an independent applier.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class IPSPatchTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func patchBytes(_ source: [UInt8], _ target: [UInt8]) throws -> [UInt8] {
        try IPSPatchCodec().createPatch(source: data(source), target: data(target)).materialized().rawBytes
    }

    /// Create, apply through the production view, and check the same patch
    /// through the independent reference applier.
    private func roundTrip(
        _ source: [UInt8],
        _ target: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let patch = try patchBytes(source, target)
        let applied = try IPSPatchCodec().apply(
            patch: data(patch), to: data(source), direction: nil, validateInput: true
        )
        XCTAssertEqual(
            try applied.output.materialized().rawBytes, target,
            "apply", file: file, line: line
        )
        XCTAssertEqual(
            ReferenceIPS.apply(patch, to: source), target,
            "reference apply", file: file, line: line
        )
        XCTAssertNil(applied.expectedOutputChecksum, "IPS has no checksums", file: file, line: line)
        XCTAssertFalse(applied.warnings.isEmpty, "the absence of checksums is reported", file: file, line: line)
    }

    // MARK: - Layout

    func testRecordLayoutForASingleDifference() throws {
        let patch = try patchBytes([0x11, 0x22, 0x33], [0x11, 0x99, 0x33])
        var expected: [UInt8] = Array("PATCH".utf8)
        expected += [0x00, 0x00, 0x01]   // offset 1
        expected += [0x00, 0x01]         // one byte
        expected += [0x99]
        expected += Array("EOF".utf8)
        XCTAssertEqual(patch, expected)
        try roundTrip([0x11, 0x22, 0x33], [0x11, 0x99, 0x33])
    }

    func testARepeatedByteBecomesARunRecord() throws {
        let source = [UInt8](repeating: 0x00, count: 40)
        var target = source
        for index in 8 ..< 32 { target[index] = 0xEE }
        let patch = try patchBytes(source, target)
        var expected: [UInt8] = Array("PATCH".utf8)
        expected += [0x00, 0x00, 0x08]   // offset 8
        expected += [0x00, 0x00]         // size 0 marks a run
        expected += [0x00, 0x18]         // 24 bytes
        expected += [0xEE]
        expected += Array("EOF".utf8)
        XCTAssertEqual(patch, expected)
        try roundTrip(source, target)
    }

    func testAShortRepeatStaysALiteral() throws {
        // Three repeated bytes cost less spelled out than as a run record.
        let patch = try patchBytes([0, 0, 0, 0, 0], [0, 7, 7, 7, 0])
        XCTAssertEqual(patch[5 ..< 10], [0x00, 0x00, 0x01, 0x00, 0x03])
        try roundTrip([0, 0, 0, 0, 0], [0, 7, 7, 7, 0])
    }

    func testAGrowingTargetIsWrittenPastTheInputsEnd() throws {
        try roundTrip([1, 2, 3], [1, 2, 3, 4, 5, 6])
        try roundTrip([], [9, 9, 9])
    }

    func testAShrinkingTargetUsesTheTruncationField() throws {
        let source: [UInt8] = [1, 2, 3, 4, 5, 6]
        let target: [UInt8] = [1, 2, 3]
        let patch = try patchBytes(source, target)
        XCTAssertEqual(Array(patch.suffix(6)), Array("EOF".utf8) + [0x00, 0x00, 0x03])
        try roundTrip(source, target)
        XCTAssertEqual(try IPSPatch.parse(data(patch)).truncation, 3)
    }

    func testIdenticalFilesProduceAnEmptyPatch() throws {
        let bytes: [UInt8] = [1, 2, 3]
        XCTAssertEqual(try patchBytes(bytes, bytes), Array("PATCH".utf8) + Array("EOF".utf8))
        try roundTrip(bytes, bytes)
    }

    func testALongDifferenceIsSplitAtTheRecordCeiling() throws {
        // One run longer than a two-byte size field can describe, with no
        // repeats to turn it into a run record.
        var state: UInt8 = 1
        let source = [UInt8](repeating: 0, count: 0x12000)
        let target = (0 ..< 0x12000).map { _ -> UInt8 in
            state = state &* 7 &+ 13
            return state | 1
        }
        let patch = try patchBytes(source, target)
        let records = try IPSPatch.parse(data(patch)).records
        XCTAssertGreaterThan(records.count, 1)
        XCTAssertTrue(records.allSatisfy { $0.length <= IPSPatch.maximumRecordLength })
        try roundTrip(source, target)
    }

    // MARK: - The two offset rules

    func testNoRecordStartsAtTheOffsetThatSpellsEOF() throws {
        // 0x454F46 is "EOF" as a three-byte offset, so a record there would
        // end the patch for every reader. It starts a byte earlier instead.
        let size = IPSPatch.terminatorOffset + 4
        let source = GeneratedReadable(length: size, fill: 0xAA)
        let target = GeneratedReadable(length: size, fill: 0xAA, overrides: [IPSPatch.terminatorOffset: 0x55])
        let patch = try IPSPatchCodec().createPatch(source: source, target: target).materialized()
        let records = try IPSPatch.parse(patch).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].offset, IPSPatch.terminatorOffset - 1)
        XCTAssertEqual(records[0].length, 2, "it covers one byte of context plus the difference")

        let applied = try IPSPatchCodec().apply(patch: patch, to: source, direction: nil, validateInput: true)
        let window = try XCTUnwrap(applied.output.read(atAddress: IPSPatch.terminatorOffset - 1, length: 3))
        XCTAssertEqual(window.rawBytes, [0xAA, 0x55, 0xAA])
    }

    func testADifferenceBeyondSixteenMebibytesIsRefused() {
        let size = IPSPatch.maximumOffset + 2
        let source = GeneratedReadable(length: size, fill: 0)
        let target = GeneratedReadable(length: size, fill: 0, overrides: [IPSPatch.maximumOffset + 1: 1])
        XCTAssertThrowsError(try IPSPatchCodec().createPatch(source: source, target: target)) { error in
            guard case let PatchError.offsetBeyondFormatLimit(_, offset, limit) = error else {
                return XCTFail("expected the format's ceiling, got \(error)")
            }
            XCTAssertEqual(offset, IPSPatch.maximumOffset + 1)
            XCTAssertEqual(limit, IPSPatch.maximumOffset)
        }
    }

    // MARK: - Applying

    func testLaterRecordsWinWhereTwoOverlap() throws {
        // Hand-authored: two records over the same byte. The format applies
        // them in order, so the second one's byte is what survives.
        var patch: [UInt8] = Array("PATCH".utf8)
        patch += [0x00, 0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB]
        patch += [0x00, 0x00, 0x01, 0x00, 0x01, 0xCC]
        patch += Array("EOF".utf8)
        let applied = try IPSPatchCodec().apply(
            patch: data(patch), to: data([0, 0, 0]), direction: nil, validateInput: true
        )
        XCTAssertEqual(try applied.output.materialized().rawBytes, [0xAA, 0xCC, 0x00])
        XCTAssertEqual(ReferenceIPS.apply(patch, to: [0, 0, 0]), [0xAA, 0xCC, 0x00])
    }

    func testApplyingBackwardsIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertThrowsError(try IPSPatchCodec().apply(
            patch: data(patch), to: data([1, 9, 3]), direction: .reverse, validateInput: true
        )) { error in
            guard case PatchError.directionNotSupported = error else {
                return XCTFail("expected an unsupported direction, got \(error)")
            }
        }
    }

    func testFuzzedPairsRoundTrip() throws {
        var state: UInt32 = 0xC0FFEE
        func next() -> UInt8 {
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        for _ in 0 ..< 60 {
            let sourceLength = Int(next()) % 300
            let targetLength = Int(next()) % 300
            let source = (0 ..< sourceLength).map { _ in next() }
            var target = (0 ..< targetLength).map { _ in next() }
            if next() % 2 == 0 {
                for index in 0 ..< min(sourceLength, targetLength) where next() % 6 != 0 {
                    target[index] = source[index]
                }
            }
            // Plant runs so the run-record path is exercised too.
            if targetLength > 40, next() % 2 == 0 {
                let start = Int(next()) % (targetLength - 30)
                for index in start ..< start + 25 { target[index] = 0x5A }
            }
            try roundTrip(source, target)
        }
    }

    // MARK: - Corrupt patches

    func testWrongMagic() {
        XCTAssertThrowsError(try IPSPatch.parse(data(Array("PATCX".utf8) + Array("EOF".utf8))))
    }

    func testUnterminatedRecords() {
        var patch: [UInt8] = Array("PATCH".utf8)
        patch += [0x00, 0x00, 0x00, 0x00, 0x01, 0xAA]
        XCTAssertThrowsError(try IPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testARecordRunningPastTheEndOfThePatch() {
        var patch: [UInt8] = Array("PATCH".utf8)
        patch += [0x00, 0x00, 0x00, 0x00, 0x10, 0xAA]   // claims 16 bytes, carries one
        patch += Array("EOF".utf8)
        XCTAssertThrowsError(try IPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testUnexpectedTrailingBytes() {
        let patch: [UInt8] = Array("PATCH".utf8) + Array("EOF".utf8) + [1, 2]
        XCTAssertThrowsError(try IPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testFormatDetection() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertEqual(PatchFormat.detect(data(patch)), .ips)
    }
}
