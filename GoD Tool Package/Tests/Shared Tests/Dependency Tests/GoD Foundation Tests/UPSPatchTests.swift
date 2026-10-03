//
//  UPSPatchTests.swift
//
//  Coverage for the UPS codec: the variable-width integer on its own, the
//  on-wire layout against hand-authored bytes, behavioural round trips
//  cross-checked through an independent applier, and the error paths a
//  corrupt or mismatched patch has to take.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class UPSPatchTests: XCTestCase {

    // MARK: - Helpers

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func patchBytes(_ source: [UInt8], _ target: [UInt8]) throws -> [UInt8] {
        let patch = try UPSPatchCodec().createPatch(source: data(source), target: data(target))
        return try patch.allBytes().rawBytes
    }

    /// Create a patch between the two, then check it applies both ways —
    /// through the production view *and* through the independent reference
    /// applier, so an encoder and decoder that are wrong in matching ways
    /// cannot pass.
    private func roundTrip(
        _ source: [UInt8],
        _ target: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let codec = UPSPatchCodec()
        let patch = try patchBytes(source, target)

        let forward = try codec.apply(
            patch: data(patch), to: data(source), direction: nil, validateInput: true
        )
        XCTAssertEqual(forward.direction, .forward, "direction", file: file, line: line)
        XCTAssertEqual(
            try forward.output.allBytes().rawBytes, target,
            "forward apply", file: file, line: line
        )
        XCTAssertNoThrow(
            try codec.validate(output: data(target), of: forward),
            "forward output checksum", file: file, line: line
        )

        let reverse = try codec.apply(
            patch: data(patch), to: data(target), direction: nil, validateInput: true
        )
        // Identical files make a patch whose two sides are indistinguishable,
        // so "forward" is the honest answer there.
        XCTAssertEqual(
            try reverse.output.allBytes().rawBytes, source,
            "reverse apply", file: file, line: line
        )

        XCTAssertEqual(
            ReferenceUPS.apply(patch, to: source), target,
            "reference forward apply", file: file, line: line
        )
        XCTAssertEqual(
            ReferenceUPS.apply(patch, to: target), source,
            "reference reverse apply", file: file, line: line
        )

        let parsed = ReferenceUPS.parse(patch)
        XCTAssertEqual(parsed.sourceSize, source.count, "source size", file: file, line: line)
        XCTAssertEqual(parsed.targetSize, target.count, "target size", file: file, line: line)
        XCTAssertEqual(parsed.sourceCRC, ReferenceUPS.crc32(source), "source CRC", file: file, line: line)
        XCTAssertEqual(parsed.targetCRC, ReferenceUPS.crc32(target), "target CRC", file: file, line: line)
        XCTAssertEqual(
            parsed.patchCRC, ReferenceUPS.crc32(Array(patch[0 ..< (patch.count - 4)])),
            "patch CRC", file: file, line: line
        )
    }

    // MARK: - Variable-width integers

    func testVariableLengthIntegerCanonicalSpellings() {
        // The spellings byuu's encoder produces. A base-128 varint would
        // write 0x80 as [0x01, 0x80] rather than [0x00, 0x80].
        XCTAssertEqual(PatchVariableLengthInteger.encode(0), [0x80])
        XCTAssertEqual(PatchVariableLengthInteger.encode(1), [0x81])
        XCTAssertEqual(PatchVariableLengthInteger.encode(0x7F), [0xFF])
        XCTAssertEqual(PatchVariableLengthInteger.encode(0x80), [0x00, 0x80])
        XCTAssertEqual(PatchVariableLengthInteger.encode(0x81), [0x01, 0x80])
        XCTAssertEqual(PatchVariableLengthInteger.encode(0x407F), [0x7F, 0xFF])
        XCTAssertEqual(PatchVariableLengthInteger.encode(0x4080), [0x00, 0x00, 0x80])
    }

    func testVariableLengthIntegerRoundTrips() throws {
        var values: [UInt64] = [
            0, 1, 2, 0x7E, 0x7F, 0x80, 0x81, 0x407F, 0x4080,
            1_000, 0xFFFF, 0x10_0000, 1_459_978_240, 4_699_979_776,
            UInt64(UInt32.max), UInt64(Int.max),
        ]
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        for _ in 0 ..< 500 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            values.append(state >> 16)
        }
        for value in values {
            let bytes = PatchVariableLengthInteger.encode(value)
            XCTAssertEqual(bytes.count, PatchVariableLengthInteger.encodedLength(of: value), "\(value)")
            var cursor = 0
            let decoded = try PatchVariableLengthInteger.decode(nextByte: {
                defer { cursor += 1 }
                return cursor < bytes.count ? bytes[cursor] : nil
            })
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(cursor, bytes.count, "consumed exactly the encoded bytes for \(value)")
        }
    }

    func testVariableLengthIntegerRejectsTruncatedAndOverflowingInput() {
        XCTAssertThrowsError(try PatchVariableLengthInteger.decode(nextByte: { nil }))
        // Continuation bytes forever: the multiplier overflows 64 bits.
        XCTAssertThrowsError(try PatchVariableLengthInteger.decode(nextByte: { 0x7F }))
    }

    // MARK: - On-wire layout

    func testPatchLayoutForASingleDifference() throws {
        let source: [UInt8] = [0x11, 0x22, 0x33]
        let target: [UInt8] = [0x11, 0xFF, 0x33]
        let patch = try patchBytes(source, target)

        var expected: [UInt8] = Array("UPS1".utf8)
        expected += [0x83, 0x83]          // both sizes: 3
        expected += [0x81]                // relative offset: 1
        expected += [UInt8(0x22 ^ 0xFF)]  // the XOR byte
        expected += [0x00]                // hunk terminator
        XCTAssertEqual(Array(patch[0 ..< expected.count]), expected)
        XCTAssertEqual(patch.count, expected.count + 12)
        try roundTrip(source, target)
    }

    func testSecondHunkOffsetCountsTheTerminator() throws {
        // Differences at 0 and at 5. The first hunk ends at position 1 and
        // its terminator takes position 1, so the second offset is 5 - 2 = 3.
        // An implementation that forgets the terminator writes 4 here.
        let source: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        let target: [UInt8] = [0xFF, 0x01, 0x02, 0x03, 0x04, 0xA5, 0x06]
        let patch = try patchBytes(source, target)

        var expected: [UInt8] = Array("UPS1".utf8)
        expected += [0x87, 0x87]          // both sizes: 7
        expected += [0x80, 0xFF, 0x00]    // offset 0, one XOR byte, terminator
        expected += [0x83, UInt8(0x05 ^ 0xA5), 0x00]
        XCTAssertEqual(Array(patch[0 ..< expected.count]), expected)
        try roundTrip(source, target)
    }

    func testIdenticalFilesProduceAPatchWithNoHunks() throws {
        let bytes: [UInt8] = [1, 2, 3, 4, 5]
        let patch = try patchBytes(bytes, bytes)
        XCTAssertEqual(patch.count, 4 + 1 + 1 + 12)
        XCTAssertEqual(try UPSPatch.parse(data(patch)).hunks, [])
        try roundTrip(bytes, bytes)
    }

    func testEmptyFilesProduceTheShortestLegalPatch() throws {
        let patch = try patchBytes([], [])
        XCTAssertEqual(patch.count, UPSPatch.minimumLength)
        let parsed = try UPSPatch.parse(data(patch))
        XCTAssertEqual(parsed.sourceSize, 0)
        XCTAssertEqual(parsed.targetSize, 0)
        XCTAssertEqual(parsed.hunks, [])
    }

    // MARK: - Shapes that break implementations

    func testTargetLongerThanSource() throws {
        try roundTrip([1, 2, 3], [1, 2, 3, 4, 5, 6])
        try roundTrip([1, 2, 3], [9, 9, 9, 9, 9, 9, 9, 9])
    }

    func testTargetShorterThanSource() throws {
        try roundTrip([1, 2, 3, 4, 5, 6], [1, 2, 3])
        try roundTrip([1, 2, 3, 4, 5, 6], [7])
    }

    func testEmptyOnEitherSide() throws {
        try roundTrip([], [1, 2, 3])
        try roundTrip([1, 2, 3], [])
    }

    func testADifferenceAtTheVeryLastByte() throws {
        // The hunk's terminator lands one past the end of both files, which
        // is legal: the terminator is a patch byte, not an output byte.
        try roundTrip([1, 2, 3], [1, 2, 4])
        try roundTrip([1, 2, 3], [1, 2, 3, 4])
    }

    func testTrailingZeroesAreStillADifference() throws {
        // A tail of zeroes XORs to zero against a file that ends early, so a
        // zero-extension bug shows up as a target that comes back short.
        try roundTrip([1, 2, 3], [1, 2, 3, 0, 0, 0])
        try roundTrip([1, 2, 3, 0, 0, 0], [1, 2, 3])
    }

    func testRunsSpanningManyWindows() throws {
        // Longer than the diff window, so runs are stitched across windows.
        let window = 1 << 22
        var source = [UInt8](repeating: 0xAA, count: window + 1000)
        var target = source
        for index in (window - 10) ..< (window + 10) { target[index] = 0x55 }
        source[0] = 0x01
        target[0] = 0x02
        let codec = UPSPatchCodec()
        let patch = try codec.createPatch(source: data(source), target: data(target)).allBytes()
        let applied = try codec.apply(patch: patch, to: data(source), direction: nil, validateInput: true)
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target)
    }

    func testFuzzedPairsRoundTrip() throws {
        var state: UInt32 = 0x0BAD_F00D
        func next() -> UInt8 {
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        for _ in 0 ..< 60 {
            let sourceLength = Int(next()) % 200
            let targetLength = Int(next()) % 200
            var source = (0 ..< sourceLength).map { _ in next() }
            var target = (0 ..< targetLength).map { _ in next() }
            // Make them mostly similar about half the time, so both the
            // many-small-hunks and the one-big-hunk shapes get exercised.
            if next() % 2 == 0 {
                let shared = min(sourceLength, targetLength)
                for index in 0 ..< shared where next() % 8 != 0 {
                    target[index] = source[index]
                }
            }
            if sourceLength > 0, targetLength > 0, next() % 4 == 0 {
                source[0] = 0
                target[0] = 0
            }
            try roundTrip(source, target)
        }
    }

    // MARK: - Streaming

    func testNeitherDirectionAsksForAWholeBuffer() throws {
        // `allData` is the thing a disc-sized source must never be asked for,
        // so this readable refuses it and both directions still work.
        let source = WindowOnlyReadable([1, 2, 3, 4, 5, 6, 7, 8])
        let target = WindowOnlyReadable([1, 2, 0xFF, 4, 5, 6, 7, 9])
        let codec = UPSPatchCodec()
        let patch = try codec.createPatch(source: source, target: target)
        XCTAssertNil(patch.allData, "the patch is a view, not a buffer")

        let patchBytes = try patch.allBytes()
        let applied = try codec.apply(
            patch: WindowOnlyReadable(patchBytes.rawBytes),
            to: source,
            direction: nil,
            validateInput: true
        )
        XCTAssertNil(applied.output.allData, "the patched output is a view, not a buffer")
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target.bytes)
    }

    // MARK: - Corrupt patches

    func testPatchTooShort() {
        XCTAssertThrowsError(try UPSPatch.parse(data(Array("UPS1".utf8))))
    }

    func testWrongMagic() throws {
        var patch = try patchBytes([1, 2, 3], [1, 2, 4])
        patch.replaceSubrange(0 ..< 4, with: Array("BPS1".utf8))
        XCTAssertThrowsError(try UPSPatch.parse(data(patch)))
    }

    func testCorruptPatchFailsItsOwnChecksum() throws {
        var patch = try patchBytes([1, 2, 3], [1, 2, 4])
        patch[7] ^= 0xFF
        XCTAssertThrowsError(try UPSPatch.parse(data(patch))) { error in
            guard case PatchError.patchChecksumMismatch = error else {
                return XCTFail("expected a patch checksum mismatch, got \(error)")
            }
        }
        // Without the checksum check it parses: the corruption is in the
        // payload, which is bytes rather than structure.
        XCTAssertNoThrow(try UPSPatch.parse(data(patch), validatingChecksum: false))
    }

    func testUnterminatedHunkIsMalformed() {
        // "UPS1", sizes 3 and 3, one hunk at offset 0 whose XOR data runs
        // straight into the footer with no terminator.
        var patch: [UInt8] = Array("UPS1".utf8) + [0x83, 0x83, 0x80, 0x01, 0x02]
        patch += [UInt8](repeating: 0, count: 12)
        XCTAssertThrowsError(try UPSPatch.parse(data(patch), validatingChecksum: false)) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testHunkPastTheEndOfBothFilesIsMalformed() {
        // Sizes 2 and 2, but a hunk at offset 5.
        var patch: [UInt8] = Array("UPS1".utf8) + [0x82, 0x82, 0x85, 0x01, 0x00]
        patch += [UInt8](repeating: 0, count: 12)
        XCTAssertThrowsError(try UPSPatch.parse(data(patch), validatingChecksum: false)) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testHunkDataPastTheShorterSideIsKeptNotRejected() throws {
        // A patch whose target is longer carries the target's tail. Applying
        // it in reverse produces the shorter source, and the tail hunk simply
        // has nowhere to land — it must not be treated as corruption.
        let source: [UInt8] = [1, 2]
        let target: [UInt8] = [1, 2, 3, 4, 5]
        let patch = try patchBytes(source, target)
        let parsed = try UPSPatch.parse(data(patch))
        XCTAssertEqual(parsed.coverage, 5)
        XCTAssertTrue(parsed.hunks.contains { $0.outputOffset + $0.length > source.count })

        let reverse = try UPSPatchCodec().apply(
            patch: data(patch), to: data(target), direction: nil, validateInput: true
        )
        XCTAssertEqual(reverse.direction, .reverse)
        XCTAssertEqual(try reverse.output.allBytes().rawBytes, source)
    }

    func testAHunkAfterOneThatFilledThePatchIsMalformed() {
        // Sizes 2 and 2, so the patch covers two positions. The first hunk's
        // payload fills both — legal — which leaves the position one past the
        // end, and a second hunk then has nowhere to start. Rejecting it is
        // the point; computing the remaining room as an unsigned value here
        // used to trap instead.
        var patch: [UInt8] = Array("UPS1".utf8) + [0x82, 0x82]
        patch += [0x80, 0x01, 0x02, 0x00]
        patch += [0x80, 0x01, 0x00]
        patch += [UInt8](repeating: 0, count: 12)
        XCTAssertThrowsError(try UPSPatch.parse(data(patch), validatingChecksum: false)) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    // MARK: - Mismatched inputs

    func testApplyingToTheWrongFileIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 4])
        XCTAssertThrowsError(try UPSPatchCodec().apply(
            patch: data(patch), to: data([9, 9, 9]), direction: nil, validateInput: true
        )) { error in
            guard case PatchError.inputChecksumMismatch = error else {
                return XCTFail("expected an input checksum mismatch, got \(error)")
            }
        }
    }

    func testIgnoringChecksumsPatchesAnyway() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 4])
        let application = try UPSPatchCodec().apply(
            patch: data(patch), to: data([9, 9, 9]), direction: .forward, validateInput: false
        )
        XCTAssertFalse(application.warnings.isEmpty, "a mismatch that was let past must be reported")
        // The XOR still lands where the patch says, so the output is the
        // input with the same difference applied.
        XCTAssertEqual(try application.output.allBytes().rawBytes, [9, 9, UInt8(9 ^ 3 ^ 4)])
        // ...and it is not the file the patch promised, which the output
        // check is what catches.
        XCTAssertThrowsError(try UPSPatchCodec().validate(
            output: try application.output.allBytes(), of: application
        )) { error in
            guard case PatchError.outputChecksumMismatch = error else {
                return XCTFail("expected an output checksum mismatch, got \(error)")
            }
        }
    }

    func testAnInputThatIsNeitherSizeIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 3, 4])
        XCTAssertThrowsError(try UPSPatchCodec().apply(
            patch: data(patch), to: data([1, 2, 3, 4, 5, 6]), direction: nil, validateInput: false
        )) { error in
            guard case PatchError.inputMatchesNeitherSide = error else {
                return XCTFail("expected neither-side, got \(error)")
            }
        }
    }

    func testAmbiguousDirectionIsRefusedRatherThanGuessed() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 4])
        XCTAssertThrowsError(try UPSPatchCodec().apply(
            patch: data(patch), to: data([9, 9, 9]), direction: nil, validateInput: false
        )) { error in
            guard case PatchError.ambiguousDirection = error else {
                return XCTFail("expected ambiguous direction, got \(error)")
            }
        }
    }

    func testANamedDirectionWithTheWrongSizeIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 3, 4])
        XCTAssertThrowsError(try UPSPatchCodec().apply(
            patch: data(patch), to: data([1, 2, 3]), direction: .reverse, validateInput: true
        )) { error in
            guard case PatchError.inputSizeMismatch = error else {
                return XCTFail("expected a size mismatch, got \(error)")
            }
        }
    }

    // MARK: - Format detection

    func testFormatDetection() throws {
        let patch = try patchBytes([1, 2, 3], [1, 2, 4])
        XCTAssertEqual(PatchFormat.detect(data(patch)), .ups)
        XCTAssertEqual(PatchFormat.detect(data(Array("BPS1".utf8) + [0, 0, 0, 0])), .bps)
        XCTAssertEqual(PatchFormat.detect(data(Array("PATCH".utf8))), .ips)
        XCTAssertNil(PatchFormat.detect(data(Array("Yaz0".utf8))))
        XCTAssertNil(PatchFormat.detect(data([])))
    }
}
