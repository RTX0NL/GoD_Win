//
//  VCDIFFPatchTests.swift
//
//  Coverage for the VCDIFF codec: the integer encoding against the RFC's own
//  example, the default code table at every boundary the spec's ranges imply,
//  the address caches, round trips through the encoder, and the features that
//  are refused by name rather than misread.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class VCDIFFPatchTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func patchBytes(_ source: [UInt8], _ target: [UInt8], encoder: VCDIFFEncoder = VCDIFFEncoder()) throws -> [UInt8] {
        try VCDIFFPatchCodec(encoder: encoder)
            .createPatch(source: data(source), target: data(target))
            .allBytes()
            .rawBytes
    }

    private func roundTrip(
        _ source: [UInt8],
        _ target: [UInt8],
        encoder: VCDIFFEncoder = VCDIFFEncoder(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let patch = try patchBytes(source, target, encoder: encoder)
        let codec = VCDIFFPatchCodec()
        let applied = try codec.apply(patch: data(patch), to: data(source), direction: nil, validateInput: true)
        XCTAssertEqual(
            try applied.output.allBytes().rawBytes, target, "apply", file: file, line: line
        )
        XCTAssertEqual(
            ReferenceVCDIFF.apply(patch, to: source), target, "reference apply", file: file, line: line
        )
    }

    // MARK: - Integers

    func testIntegerEncodingMatchesTheSpecExample() throws {
        // RFC 3284 §2: 123456789 is BA EF 9A 15.
        XCTAssertEqual(VCDIFFInteger.encode(123_456_789), [0xBA, 0xEF, 0x9A, 0x15])
        XCTAssertEqual(VCDIFFInteger.encode(0), [0x00])
        XCTAssertEqual(VCDIFFInteger.encode(127), [0x7F])
        XCTAssertEqual(VCDIFFInteger.encode(128), [0x81, 0x00])
    }

    func testIntegersRoundTripAndAreNotTheOtherFormatsEncoding() throws {
        for value in [0, 1, 127, 128, 255, 16_383, 16_384, 123_456_789, 1_459_978_240] {
            let bytes = VCDIFFInteger.encode(value)
            var cursor = 0
            let decoded = try VCDIFFInteger.decode(nextByte: {
                defer { cursor += 1 }
                return cursor < bytes.count ? bytes[cursor] : nil
            })
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(cursor, bytes.count)
        }
        // The two conventions really do differ: UPS writes 128 as 00 80.
        XCTAssertEqual(PatchVariableLengthInteger.encode(128), [0x00, 0x80])
        XCTAssertEqual(VCDIFFInteger.encode(128), [0x81, 0x00])
    }

    func testTruncatedAndOverlongIntegersAreRejected() {
        XCTAssertThrowsError(try VCDIFFInteger.decode(nextByte: { nil }))
        XCTAssertThrowsError(try VCDIFFInteger.decode(nextByte: { 0x80 }))
    }

    // MARK: - The default code table
    //
    // Asserted against the ranges RFC 3284 states, not against the generator —
    // the point is to catch the generator being subtly wrong, which a wrong
    // table hides by decoding most streams anyway.

    func testCodeTableShape() {
        let table = VCDIFFCodeTable.default
        XCTAssertEqual(table.count, 256)

        // 0: RUN, size from the stream.
        XCTAssertEqual(table[0].0, VCDIFFInstruction(type: .run, size: 0, mode: 0))
        XCTAssertEqual(table[0].1.type, .noop)

        // 1-18: ADD — size from the stream, then 1...17.
        XCTAssertEqual(table[1].0, VCDIFFInstruction(type: .add, size: 0, mode: 0))
        XCTAssertEqual(table[2].0, VCDIFFInstruction(type: .add, size: 1, mode: 0))
        XCTAssertEqual(table[18].0, VCDIFFInstruction(type: .add, size: 17, mode: 0))

        // 19-162: COPY, nine modes of sixteen — size from the stream, then 4...18.
        XCTAssertEqual(table[19].0, VCDIFFInstruction(type: .copy, size: 0, mode: 0))
        XCTAssertEqual(table[20].0, VCDIFFInstruction(type: .copy, size: 4, mode: 0))
        XCTAssertEqual(table[34].0, VCDIFFInstruction(type: .copy, size: 18, mode: 0))
        XCTAssertEqual(table[35].0, VCDIFFInstruction(type: .copy, size: 0, mode: 1))
        XCTAssertEqual(table[162].0, VCDIFFInstruction(type: .copy, size: 18, mode: 8))

        // 163-234: ADD 1...4 then COPY 4...6, for modes 0...5.
        XCTAssertEqual(table[163].0, VCDIFFInstruction(type: .add, size: 1, mode: 0))
        XCTAssertEqual(table[163].1, VCDIFFInstruction(type: .copy, size: 4, mode: 0))
        XCTAssertEqual(table[164].1, VCDIFFInstruction(type: .copy, size: 5, mode: 0))
        XCTAssertEqual(table[234].0, VCDIFFInstruction(type: .add, size: 4, mode: 0))
        XCTAssertEqual(table[234].1, VCDIFFInstruction(type: .copy, size: 6, mode: 5))

        // 235-246: the same-cache modes pair with copy size 4 only.
        XCTAssertEqual(table[235].0, VCDIFFInstruction(type: .add, size: 1, mode: 0))
        XCTAssertEqual(table[235].1, VCDIFFInstruction(type: .copy, size: 4, mode: 6))
        XCTAssertEqual(table[246].0, VCDIFFInstruction(type: .add, size: 4, mode: 0))
        XCTAssertEqual(table[246].1, VCDIFFInstruction(type: .copy, size: 4, mode: 8))

        // 247-255: COPY 4 then ADD 1, one per mode.
        XCTAssertEqual(table[247].0, VCDIFFInstruction(type: .copy, size: 4, mode: 0))
        XCTAssertEqual(table[247].1, VCDIFFInstruction(type: .add, size: 1, mode: 0))
        XCTAssertEqual(table[255].0, VCDIFFInstruction(type: .copy, size: 4, mode: 8))
        XCTAssertEqual(table[255].1, VCDIFFInstruction(type: .add, size: 1, mode: 0))

        // Every entry is one of the four instruction types, and a second
        // instruction is never a RUN.
        for (first, second) in table {
            XCTAssertNotEqual(first.type, .noop)
            XCTAssertNotEqual(second.type, .run)
        }
    }

    func testAddressCacheModes() throws {
        var cache = VCDIFFAddressCache()
        // SELF: the address as written.
        var integers = [100]
        var bytes = [UInt8]()
        func nextInteger() throws -> Int { integers.removeFirst() }
        func nextByte() throws -> UInt8 { bytes.removeFirst() }
        XCTAssertEqual(try cache.decodeAddress(mode: 0, here: 500, nextInteger: nextInteger, nextByte: nextByte), 100)

        // HERE: counted back from the current position.
        integers = [40]
        XCTAssertEqual(try cache.decodeAddress(mode: 1, here: 500, nextInteger: nextInteger, nextByte: nextByte), 460)

        // Near: the most recent addresses plus an offset. 100 then 460 went in,
        // so slot 0 holds 100 and slot 1 holds 460.
        integers = [5]
        XCTAssertEqual(try cache.decodeAddress(mode: 2, here: 500, nextInteger: nextInteger, nextByte: nextByte), 105)
        integers = [1]
        XCTAssertEqual(try cache.decodeAddress(mode: 3, here: 500, nextInteger: nextInteger, nextByte: nextByte), 461)

        // Same: indexed by a byte, holding whatever address last landed in that
        // slot — 100 went to slot 100 of row 0.
        bytes = [100]
        XCTAssertEqual(try cache.decodeAddress(mode: 6, here: 900, nextInteger: nextInteger, nextByte: nextByte), 100)
    }

    // MARK: - Round trips

    func testIdenticalFilesBecomeOneCopy() throws {
        let bytes = (0 ..< 500).map { UInt8($0 % 251) }
        let patch = try patchBytes(bytes, bytes)
        XCTAssertLessThan(patch.count, 60, "a whole-file match should be a few bytes of instructions")
        try roundTrip(bytes, bytes)
    }

    func testMovedDataIsCopiedRatherThanRepeated() throws {
        // The thing this format exists for: the same blocks, reordered. A patch
        // that can only describe bytes in place would carry the whole target.
        var first = [UInt8]()
        var second = [UInt8]()
        var state: UInt32 = 12345
        for _ in 0 ..< 4_000 {
            state = 1_103_515_245 &* state &+ 12345
            first.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        for _ in 0 ..< 4_000 {
            state = 1_103_515_245 &* state &+ 12345
            second.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        let source = first + second
        let target = second + first
        let patch = try patchBytes(source, target)
        XCTAssertLessThan(patch.count, target.count / 4, "the halves should be copies, not literals")
        try roundTrip(source, target)
    }

    func testLiteralsWhereNothingMatches() throws {
        let source = [UInt8](repeating: 0, count: 100)
        var state: UInt32 = 999
        let target = (0 ..< 100).map { _ -> UInt8 in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24) | 1
        }
        try roundTrip(source, target)
    }

    func testRunsBecomeRunInstructions() throws {
        let source = [UInt8](repeating: 1, count: 50)
        let target = [UInt8](repeating: 0xC3, count: 5_000)
        let patch = try patchBytes(source, target)
        XCTAssertLessThan(patch.count, 80, "a repeat should be a RUN, not 5,000 literals")
        try roundTrip(source, target)
    }

    func testEmptyAndTinyFiles() throws {
        try roundTrip([], [])
        try roundTrip([], [1, 2, 3])
        try roundTrip([1, 2, 3], [])
        try roundTrip([1], [2])
    }

    func testMultipleWindows() throws {
        // A window size smaller than the target, so the patch has several and
        // each is decoded on its own.
        let encoder = VCDIFFEncoder(windowSize: 1_024, blockSize: 16, minimumRun: 16)
        var state: UInt32 = 4242
        let source = (0 ..< 5_000).map { _ -> UInt8 in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        var target = source
        target.replaceSubrange(2_000 ..< 2_100, with: [UInt8](repeating: 0x7F, count: 100))
        let patch = try patchBytes(source, target, encoder: encoder)
        let parsed = try VCDIFFPatch.parse(data(patch))
        XCTAssertEqual(parsed.windows.count, 5)
        XCTAssertEqual(parsed.targetSize, target.count)
        try roundTrip(source, target, encoder: encoder)
    }

    func testFuzzedPairsRoundTrip() throws {
        let encoder = VCDIFFEncoder(windowSize: 512, blockSize: 8, maximumMatch: 256, minimumRun: 8)
        var state: UInt32 = 0x5EED
        func next() -> UInt8 {
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        for _ in 0 ..< 40 {
            let sourceLength = Int(next()) % 400
            let targetLength = Int(next()) % 400
            let source = (0 ..< sourceLength).map { _ in next() }
            var target = (0 ..< targetLength).map { _ in next() }
            if next() % 2 == 0, sourceLength > 0, targetLength > 0 {
                // Splice a stretch of the source in, so there is something to copy.
                let take = min(sourceLength, targetLength) / 2
                if take > 0 {
                    target.replaceSubrange(0 ..< take, with: source[(sourceLength - take) ..< sourceLength])
                }
            }
            try roundTrip(source, target, encoder: encoder)
        }
    }

    // MARK: - Checksums

    func testAWindowChecksumIsVerifiedWhenPresent() throws {
        // Our writer doesn't stamp one, so this builds a window that does: a
        // single ADD of three bytes, with xdelta3's checksum flag set.
        let bytes: [UInt8] = [0x41, 0x42, 0x43]
        func realPatch(withChecksum checksum: UInt32) -> [UInt8] {
            var instructions: [UInt8] = [UInt8(VCDIFFCodeTable.addWithExplicitSize)]
            instructions += VCDIFFInteger.encode(bytes.count)
            var delta = VCDIFFInteger.encode(bytes.count)      // target window length
            delta.append(0)                                     // delta indicator
            delta += VCDIFFInteger.encode(bytes.count)          // data length
            delta += VCDIFFInteger.encode(instructions.count)   // instruction length
            delta += VCDIFFInteger.encode(0)                    // address length
            delta += [
                UInt8((checksum >> 24) & 0xFF), UInt8((checksum >> 16) & 0xFF),
                UInt8((checksum >> 8) & 0xFF), UInt8(checksum & 0xFF),
            ]
            delta += bytes
            delta += instructions
            var out = VCDIFFPatch.magic + [0x00, 0x00]
            out.append(VCDIFFPatch.WindowIndicator.adler32)
            out += VCDIFFInteger.encode(delta.count)
            out += delta
            return out
        }

        let good = realPatch(withChecksum: Adler32.compute(bytes))
        let applied = try VCDIFFPatchCodec().apply(
            patch: data(good), to: data([]), direction: nil, validateInput: true
        )
        XCTAssertEqual(try applied.output.allBytes().rawBytes, bytes)
        XCTAssertTrue(applied.warnings.isEmpty, "a checksummed patch needs no caveat")

        let bad = realPatch(withChecksum: 0xDEAD_BEEF)
        let parsed = try VCDIFFPatch.parse(data(bad))
        XCTAssertThrowsError(try VCDIFFWindowDecoder.decode(
            window: parsed.windows[0], patch: data(bad), source: nil
        )) { error in
            guard case PatchError.windowChecksumMismatch = error else {
                return XCTFail("expected a window checksum mismatch, got \(error)")
            }
        }
    }

    func testAPatchWithoutChecksumsSaysSo() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        let applied = try VCDIFFPatchCodec().apply(
            patch: data(patch), to: data([1, 2, 3]), direction: nil, validateInput: true
        )
        XCTAssertFalse(applied.warnings.isEmpty)
        XCTAssertNil(applied.expectedOutputChecksum)
    }

    func testAdler32MatchesKnownValues() {
        XCTAssertEqual(Adler32.compute([]), 1)
        XCTAssertEqual(Adler32.compute(Array("Wikipedia".utf8)), 0x11E6_0398)
    }

    // MARK: - Refusals

    func testSecondaryCompressionIsRefusedByName() {
        let patch = VCDIFFPatch.magic + [0x00, 0x01, 0x01]
        XCTAssertThrowsError(try VCDIFFPatch.parse(data(patch))) { error in
            guard case let PatchError.unsupportedFeature(_, feature) = error else {
                return XCTFail("expected an unsupported feature, got \(error)")
            }
            XCTAssertTrue(feature.contains("secondary"))
        }
    }

    func testACustomCodeTableIsRefused() {
        let patch = VCDIFFPatch.magic + [0x00, 0x02, 0x00]
        XCTAssertThrowsError(try VCDIFFPatch.parse(data(patch))) { error in
            guard case PatchError.unsupportedFeature = error else {
                return XCTFail("expected an unsupported feature, got \(error)")
            }
        }
    }

    func testATargetWindowIsRefused() {
        var patch = VCDIFFPatch.magic + [0x00, 0x00]
        patch.append(VCDIFFPatch.WindowIndicator.target)
        patch += VCDIFFInteger.encode(4) + VCDIFFInteger.encode(0)
        patch += VCDIFFInteger.encode(4) + VCDIFFInteger.encode(4) + [0x00]
        XCTAssertThrowsError(try VCDIFFPatch.parse(data(patch))) { error in
            guard case let PatchError.unsupportedFeature(_, feature) = error else {
                return XCTFail("expected an unsupported feature, got \(error)")
            }
            XCTAssertTrue(feature.contains("VCD_TARGET"))
        }
    }

    func testPerSectionCompressionIsRefused() {
        var patch = VCDIFFPatch.magic + [0x00, 0x00]
        patch.append(0x00)
        let delta = VCDIFFInteger.encode(4) + [0x01]
        patch += VCDIFFInteger.encode(delta.count) + delta
        XCTAssertThrowsError(try VCDIFFPatch.parse(data(patch))) { error in
            guard case PatchError.unsupportedFeature = error else {
                return XCTFail("expected an unsupported feature, got \(error)")
            }
        }
    }

    func testApplyingBackwardsIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertThrowsError(try VCDIFFPatchCodec().apply(
            patch: data(patch), to: data([1, 9, 3]), direction: .reverse, validateInput: true
        )) { error in
            guard case PatchError.directionNotSupported = error else {
                return XCTFail("expected an unsupported direction, got \(error)")
            }
        }
    }

    func testFormatDetectionAndAppHeader() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertEqual(PatchFormat.detect(data(patch)), .xdelta)
        XCTAssertEqual(try VCDIFFPatch.parse(data(patch)).appHeader, [], "our writer writes none")
    }
}
