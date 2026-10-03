//
//  BPSPatchTests.swift
//
//  Coverage for the BPS codec: the action layout against hand-authored bytes,
//  the two copy actions our writer never emits but every reader must handle,
//  the overlap rule that makes TargetCopy a run, and round trips cross-checked
//  through an independent applier.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class BPSPatchTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func patchBytes(_ source: [UInt8], _ target: [UInt8]) throws -> [UInt8] {
        try BPSPatchCodec().createPatch(source: data(source), target: data(target)).allBytes().rawBytes
    }

    /// Assemble a patch from action bytes, with a correct header and footer, so
    /// a test can hand the reader actions the writer never produces.
    private func assemble(
        source: [UInt8],
        target: [UInt8],
        metadata: [UInt8] = [],
        actions: [UInt8]
    ) -> [UInt8] {
        var patch = BPSPatch.magic
        patch += PatchVariableLengthInteger.encode(UInt64(source.count))
        patch += PatchVariableLengthInteger.encode(UInt64(target.count))
        patch += PatchVariableLengthInteger.encode(UInt64(metadata.count))
        patch += metadata
        patch += actions
        patch += littleEndian(CRC32.compute(source))
        patch += littleEndian(CRC32.compute(target))
        patch += littleEndian(CRC32.compute(patch))
        return patch
    }

    private func littleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    private func action(_ command: Int, length: Int) -> [UInt8] {
        PatchVariableLengthInteger.encode(UInt64(length - 1) << 2 | UInt64(command))
    }

    private func roundTrip(
        _ source: [UInt8],
        _ target: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let patch = try patchBytes(source, target)
        let applied = try BPSPatchCodec().apply(
            patch: data(patch), to: data(source), direction: nil, validateInput: true
        )
        XCTAssertEqual(
            try applied.output.allBytes().rawBytes, target, "apply", file: file, line: line
        )
        XCTAssertNoThrow(
            try BPSPatchCodec().validate(output: data(target), of: applied),
            "output checksum", file: file, line: line
        )
        XCTAssertEqual(
            ReferenceBPS.apply(patch, to: source), target, "reference apply", file: file, line: line
        )
        let header = ReferenceBPS.header(patch)
        XCTAssertEqual(header.sourceSize, source.count, "source size", file: file, line: line)
        XCTAssertEqual(header.targetSize, target.count, "target size", file: file, line: line)
        XCTAssertEqual(header.sourceCRC, ReferenceUPS.crc32(source), "source CRC", file: file, line: line)
        XCTAssertEqual(header.targetCRC, ReferenceUPS.crc32(target), "target CRC", file: file, line: line)
        XCTAssertEqual(
            header.patchCRC, ReferenceUPS.crc32(Array(patch[0 ..< (patch.count - 4)])),
            "patch CRC", file: file, line: line
        )
    }

    // MARK: - Layout

    func testActionLayoutForASingleDifference() throws {
        let source: [UInt8] = [1, 2, 3, 4]
        let target: [UInt8] = [1, 9, 3, 4]
        let patch = try patchBytes(source, target)

        var expected: [UInt8] = BPSPatch.magic
        expected += [0x84, 0x84, 0x80]    // sizes 4 and 4, no metadata
        expected += [0x80]                // SourceRead, 1 byte
        expected += [0x81, 0x09]          // TargetRead, 1 byte
        expected += [0x84]                // SourceRead, 2 bytes
        XCTAssertEqual(Array(patch[0 ..< expected.count]), expected)
        XCTAssertEqual(patch.count, expected.count + 12)
        try roundTrip(source, target)
    }

    func testIdenticalFilesAreOneSourceRead() throws {
        let bytes: [UInt8] = [1, 2, 3, 4, 5]
        let patch = try patchBytes(bytes, bytes)
        let parsed = try BPSPatch.parse(data(patch))
        XCTAssertEqual(parsed.actions, [.sourceRead(length: 5)])
        try roundTrip(bytes, bytes)
    }

    func testARunOfDifferencesIsOneTargetRead() throws {
        let source = [UInt8](repeating: 0, count: 300)
        let target = [UInt8](repeating: 0xAB, count: 300)
        let parsed = try BPSPatch.parse(data(try patchBytes(source, target)))
        XCTAssertEqual(parsed.actions.count, 1)
        XCTAssertEqual(parsed.actions.first?.length, 300)
        try roundTrip(source, target)
    }

    func testGrowingAndShrinkingTargets() throws {
        try roundTrip([1, 2, 3], [1, 2, 3, 4, 5, 6])
        try roundTrip([1, 2, 3, 4, 5, 6], [1, 2, 3])
        try roundTrip([], [1, 2, 3])
        try roundTrip([1, 2, 3], [])
    }

    // MARK: - Actions only a reader sees

    func testTargetCopyOverlapsItselfToSpellARun() throws {
        // One literal byte, then a copy of nine bytes from offset 0 — which is
        // still being written. Byte at a time, that fills ten of the same byte;
        // as a block move it would copy nine zeros.
        let target = [UInt8](repeating: 0xAA, count: 10)
        var actions = action(1, length: 1) + [0xAA]
        actions += action(3, length: 9) + BPSPatch.encodeSignedInteger(0)
        let patch = assemble(source: [], target: target, actions: actions)

        let applied = try BPSPatchCodec().apply(
            patch: data(patch), to: data([]), direction: nil, validateInput: true
        )
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target)
        XCTAssertEqual(ReferenceBPS.apply(patch, to: []), target)
    }

    func testSourceCopyTakesBytesFromAnywhereInTheSource() throws {
        // The halves of the source, swapped — which a linear writer cannot
        // express and a reader must.
        let source: [UInt8] = [1, 2, 3, 4]
        let target: [UInt8] = [3, 4, 1, 2]
        var actions = action(2, length: 2) + BPSPatch.encodeSignedInteger(2)    // cursor 0 → 2
        actions += action(2, length: 2) + BPSPatch.encodeSignedInteger(-4)      // cursor 4 → 0
        let patch = assemble(source: source, target: target, actions: actions)

        let parsed = try BPSPatch.parse(data(patch))
        XCTAssertEqual(parsed.actions, [
            .sourceCopy(sourceOffset: 2, length: 2),
            .sourceCopy(sourceOffset: 0, length: 2),
        ])
        let applied = try BPSPatchCodec().apply(
            patch: data(patch), to: data(source), direction: nil, validateInput: true
        )
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target)
        XCTAssertEqual(ReferenceBPS.apply(patch, to: source), target)
    }

    func testSignedOffsetsRoundTripThroughTheirEncoding() throws {
        for value in [0, 1, -1, 63, -63, 64, -64, 1_000_000, -1_000_000] {
            let bytes = BPSPatch.encodeSignedInteger(value)
            // Decode the way the spec says: low bit is the sign.
            var cursor = 0
            let raw = try PatchVariableLengthInteger.decode(nextByte: {
                defer { cursor += 1 }
                return cursor < bytes.count ? bytes[cursor] : nil
            })
            let decoded = raw & 1 == 1 ? -Int(raw >> 1) : Int(raw >> 1)
            XCTAssertEqual(decoded, value)
        }
    }

    func testMetadataIsKept() throws {
        let metadata = Array("<patch><author>nobody</author></patch>".utf8)
        let source: [UInt8] = [1, 2]
        let target: [UInt8] = [1, 2]
        let patch = assemble(source: source, target: target, metadata: metadata, actions: action(0, length: 2))
        let parsed = try BPSPatch.parse(data(patch))
        XCTAssertEqual(parsed.metadata, metadata)
        let applied = try BPSPatchCodec().apply(
            patch: data(patch), to: data(source), direction: nil, validateInput: true
        )
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target)
    }

    // MARK: - Malformed

    func testActionsThatDoNotFillTheTargetAreRejected() {
        let patch = assemble(source: [1, 2, 3, 4], target: [1, 2, 3, 4], actions: action(0, length: 2))
        XCTAssertThrowsError(try BPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testAnActionWritingPastTheTargetIsRejected() {
        let patch = assemble(source: [1, 2], target: [1, 2], actions: action(0, length: 9))
        XCTAssertThrowsError(try BPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testATargetCopyFromUnwrittenOutputIsRejected() {
        // The copy starts at the output position, so its first byte is itself.
        var actions = action(1, length: 1) + [0xAA]
        actions += action(3, length: 1) + BPSPatch.encodeSignedInteger(1)
        let patch = assemble(source: [], target: [0xAA, 0xAA], actions: actions)
        XCTAssertThrowsError(try BPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testASourceReadPastTheSourceIsRejected() {
        let patch = assemble(source: [1, 2], target: [1, 2, 3, 4], actions: action(0, length: 4))
        XCTAssertThrowsError(try BPSPatch.parse(data(patch))) { error in
            guard case PatchError.malformedPatch = error else {
                return XCTFail("expected a malformed patch, got \(error)")
            }
        }
    }

    func testWrongMagicAndShortPatches() {
        XCTAssertThrowsError(try BPSPatch.parse(data(Array("UPS1".utf8) + [UInt8](repeating: 0, count: 20))))
        XCTAssertThrowsError(try BPSPatch.parse(data(Array("BPS1".utf8))))
    }

    func testCorruptPatchFailsItsOwnChecksum() throws {
        var patch = try patchBytes([1, 2, 3, 4], [1, 9, 3, 4])
        patch[patch.count - 13] ^= 0xFF   // an action byte: structurally broken as well as corrupt
        XCTAssertThrowsError(try BPSPatch.parse(data(patch))) { error in
            guard case PatchError.patchChecksumMismatch = error else {
                return XCTFail("expected a patch checksum mismatch, got \(error)")
            }
        }
    }

    // MARK: - Applying

    func testApplyingBackwardsIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertThrowsError(try BPSPatchCodec().apply(
            patch: data(patch), to: data([1, 9, 3]), direction: .reverse, validateInput: true
        )) { error in
            guard case PatchError.directionNotSupported = error else {
                return XCTFail("expected an unsupported direction, got \(error)")
            }
        }
    }

    func testTheWrongInputIsRefusedUnlessChecksumsAreIgnored() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertThrowsError(try BPSPatchCodec().apply(
            patch: data(patch), to: data([4, 5, 6]), direction: nil, validateInput: true
        )) { error in
            guard case PatchError.inputChecksumMismatch = error else {
                return XCTFail("expected an input checksum mismatch, got \(error)")
            }
        }
        let forced = try BPSPatchCodec().apply(
            patch: data(patch), to: data([4, 5, 6]), direction: nil, validateInput: false
        )
        XCTAssertFalse(forced.warnings.isEmpty)
        XCTAssertEqual(try forced.output.allBytes().rawBytes, [4, 9, 6])
    }

    func testAnInputOfTheWrongSizeIsRefused() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertThrowsError(try BPSPatchCodec().apply(
            patch: data(patch), to: data([1, 2, 3, 4]), direction: nil, validateInput: false
        )) { error in
            guard case PatchError.inputSizeMismatch = error else {
                return XCTFail("expected a size mismatch, got \(error)")
            }
        }
    }

    func testFuzzedPairsRoundTrip() throws {
        var state: UInt32 = 0xBEEF_F00D
        func next() -> UInt8 {
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        for _ in 0 ..< 60 {
            let sourceLength = Int(next()) % 250
            let targetLength = Int(next()) % 250
            let source = (0 ..< sourceLength).map { _ in next() }
            var target = (0 ..< targetLength).map { _ in next() }
            if next() % 2 == 0 {
                for index in 0 ..< min(sourceLength, targetLength) where next() % 5 != 0 {
                    target[index] = source[index]
                }
            }
            try roundTrip(source, target)
        }
    }

    func testFormatDetection() throws {
        let patch = try patchBytes([1, 2, 3], [1, 9, 3])
        XCTAssertEqual(PatchFormat.detect(data(patch)), .bps)
    }

    func testTheOutputIsNotABufferUntilItIsBuilt() throws {
        let source = WindowOnlyReadable([1, 2, 3, 4, 5])
        let target = WindowOnlyReadable([1, 2, 9, 4, 5])
        let codec = BPSPatchCodec()
        let patch = try codec.createPatch(source: source, target: target)
        XCTAssertNil(patch.allData, "the patch is a view")
        let applied = try codec.apply(
            patch: try patch.allBytes(), to: source, direction: nil, validateInput: true
        )
        XCTAssertNil(applied.output.allData, "nothing is built until it is read")
        XCTAssertEqual(try applied.output.allBytes().rawBytes, target.bytes)
        XCTAssertNotNil(applied.output.allData, "and the built target is then held")
    }
}
