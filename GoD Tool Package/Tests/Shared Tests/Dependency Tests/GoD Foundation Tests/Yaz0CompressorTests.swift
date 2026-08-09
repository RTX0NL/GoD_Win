//
//  Yaz0CompressorTests.swift
//
//  Coverage for the Yaz0 codec: behavioral round-trips, hand-authored
//  streams as independent ground truth for the on-wire format, and the
//  error paths a corrupt stream has to take.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class Yaz0CompressorTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// Compresses, checks the stream decodes back through *both* our
    /// decoder and the independent reference one.
    private func roundTrip(
        _ bytes: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sut = Yaz0Compressor()
        let compressed = sut.compress(data(bytes))

        let decompressed = try sut.decompress(compressed)
        XCTAssertEqual(decompressed.rawBytes, bytes, "round-trip mismatch", file: file, line: line)

        XCTAssertEqual(
            ReferenceYaz0.decode(compressed.rawBytes),
            bytes,
            "stream does not decode to the input under an independent decoder",
            file: file,
            line: line
        )
    }

    // MARK: - Round trips

    func testRoundTripEmpty() throws {
        try roundTrip([])
    }

    func testRoundTripSingleByte() throws {
        try roundTrip([0x42])
    }

    func testRoundTripShorterThanMinimumMatch() throws {
        try roundTrip([0x01, 0x02])
    }

    func testRoundTripFewBytes() throws {
        try roundTrip([0x01, 0x02, 0x03, 0x04, 0x05])
    }

    func testRoundTripHighlyRepetitive() throws {
        try roundTrip([UInt8](repeating: 0xAB, count: 500))
    }

    func testRoundTripRepeatingPattern() throws {
        try roundTrip((0 ..< 300).map { UInt8($0 % 7) })
    }

    func testRoundTripPseudoRandomIncompressible() throws {
        var state: UInt32 = 0x1234_5678
        var bytes = [UInt8]()
        for _ in 0 ..< 400 {
            state = 1_664_525 &* state &+ 1_013_904_223
            bytes.append(UInt8(state >> 24))
        }
        try roundTrip(bytes)
    }

    func testRoundTripLargerThanWindow() throws {
        // The window is 0x1000; go well past it with mixed content so
        // matches have to be rejected for being out of range.
        try roundTrip((0 ..< 10_000).map { UInt8(($0 * 31 + ($0 / 13)) & 0xFF) })
    }

    func testRoundTripLongRunExceedsMaximumMatchLength() throws {
        // A run far longer than 0x111 has to split across several matches.
        try roundTrip([UInt8](repeating: 0x00, count: 9000))
    }

    func testRoundTripTextWithLongRangeRepeats() throws {
        var bytes = Array("Pokemon Colosseum ".utf8)
        bytes += deterministicNoise(2000)
        bytes += Array("Pokemon Colosseum ".utf8)
        try roundTrip(bytes)
    }

    /// A quarter megabyte of the mix a real archive holds: repeated
    /// structure, long zero runs, and incompressible blobs.
    ///
    /// No wall-clock assertion — this guards against the match finder
    /// degenerating on the input shapes that would blow it up, which for a
    /// sliding-window search means long runs of one value. Those make every
    /// position in the window a candidate, so an encoder that walks the
    /// whole chain before settling goes quadratic and this test stops
    /// finishing rather than fails.
    func testRoundTripLargeArchiveShapedData() throws {
        var bytes: [UInt8] = []
        var state: UInt32 = 0x5A50_0000
        while bytes.count < 1 << 18 {
            bytes += Array("MODEL_ENTRY\u{0}\u{0}\u{0}\u{0}".utf8)
            bytes += [UInt8](repeating: 0, count: 400)
            bytes += (0 ..< 200).map { _ in
                state = 1_664_525 &* state &+ 1_013_904_223
                return UInt8(state >> 24)
            }
        }
        try roundTrip(bytes)
    }

    // MARK: - Known-good streams (hand-authored, not encoder output)

    /// "ABCABCABCABCD": three literals, an overlapping 9-byte match three
    /// bytes back, then one more literal.
    func testDecompressHandAuthoredStreamWithOverlappingMatch() throws {
        let stream: [UInt8] = [
            0x59, 0x61, 0x7A, 0x30,                 // "Yaz0"
            0x00, 0x00, 0x00, 0x0D,                 // 13 bytes out
            0x00, 0x00, 0x00, 0x00,                 // alignment
            0x00, 0x00, 0x00, 0x00,                 // reserved
            0b1110_1000,                            // literal ×3, match, literal
            0x41, 0x42, 0x43,                       // 'A' 'B' 'C'
            0x70, 0x02,                             // distance 3, length 9
            0x44,                                   // 'D'
        ]
        let out = try Yaz0Compressor().decompress(data(stream))
        XCTAssertEqual(out.string(format: .utf8), "ABCABCABCABCD")
    }

    /// A 40-byte run: one literal then a 39-byte match one byte back, which
    /// is long enough to need the three-byte encoding.
    func testDecompressHandAuthoredStreamWithLongMatchForm() throws {
        let stream: [UInt8] = [
            0x59, 0x61, 0x7A, 0x30,
            0x00, 0x00, 0x00, 0x28,                 // 40 bytes out
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0b1000_0000,                            // literal, match
            0x5A,                                   // 'Z'
            0x00, 0x00, 0x15,                       // distance 1, length 0x15 + 0x12 = 39
        ]
        let out = try Yaz0Compressor().decompress(data(stream))
        XCTAssertEqual(out.rawBytes, [UInt8](repeating: 0x5A, count: 40))
    }

    // MARK: - Header

    func testHeaderReadsAllFields() throws {
        let stream: [UInt8] = [
            0x59, 0x61, 0x7A, 0x30,
            0x00, 0x00, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x20,
            0x00, 0x00, 0x00, 0x00,
        ]
        let header = try Yaz0Compressor.header(of: data(stream))
        XCTAssertEqual(header.uncompressedSize, 0x100)
        XCTAssertEqual(header.alignment, 0x20)
        XCTAssertEqual(header.reserved, 0)
    }

    func testCompressWritesDeclaredSizeAndMagic() {
        let input = [UInt8](repeating: 0x11, count: 300)
        let compressed = Yaz0Compressor().compress(data(input))
        XCTAssertEqual(Array(compressed.rawBytes[0 ..< 4]), Yaz0Compressor.magic)
        XCTAssertEqual(try? Yaz0Compressor.header(of: compressed).uncompressedSize, 300)
    }

    func testCompressPreservesAlignmentHint() throws {
        let compressed = Yaz0Compressor(alignment: 0x80).compress(data([1, 2, 3, 4]))
        XCTAssertEqual(try Yaz0Compressor.header(of: compressed).alignment, 0x80)
    }

    func testCompressOfEmptyInputIsHeaderOnly() throws {
        let compressed = Yaz0Compressor().compress(data([]))
        XCTAssertEqual(compressed.length, Yaz0Compressor.headerLength)
        XCTAssertEqual(try Yaz0Compressor().decompress(compressed).length, 0)
    }

    func testCompressedIsSmallerForRepetitiveData() {
        let input = data([UInt8](repeating: 0x77, count: 4000))
        XCTAssertLessThan(Yaz0Compressor().compress(input).length, input.length)
    }

    // MARK: - Error paths

    func testDecompressThrowsOnWrongMagic() {
        let stream = data([0x59, 0x61, 0x7A, 0x31] + [UInt8](repeating: 0, count: 12))
        XCTAssertThrowsError(try Yaz0Compressor().decompress(stream)) { error in
            guard case let LZ77StreamError.wrongMagic(format, found) = error else {
                return XCTFail("expected wrongMagic, got \(error)")
            }
            XCTAssertEqual(format, "Yaz0")
            XCTAssertEqual(found, [0x59, 0x61, 0x7A, 0x31])
        }
    }

    func testDecompressThrowsOnTruncatedHeader() {
        XCTAssertThrowsError(try Yaz0Compressor().decompress(data([0x59, 0x61, 0x7A, 0x30]))) { error in
            guard case let LZ77StreamError.headerTruncated(_, length) = error else {
                return XCTFail("expected headerTruncated, got \(error)")
            }
            XCTAssertEqual(length, 4)
        }
    }

    func testDecompressThrowsWhenBodyRunsOutEarly() {
        // Header promises 64 bytes but the body holds one literal.
        let stream = data([
            0x59, 0x61, 0x7A, 0x30,
            0x00, 0x00, 0x00, 0x40,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0b1000_0000, 0x41,
        ])
        XCTAssertThrowsError(try Yaz0Compressor().decompress(stream)) { error in
            guard case LZ77StreamError.unexpectedEndOfInput = error else {
                return XCTFail("expected unexpectedEndOfInput, got \(error)")
            }
        }
    }

    func testDecompressThrowsOnBackReferenceBeforeStart() {
        // The very first operation is a match, so there is nothing behind
        // it to copy from.
        let stream = data([
            0x59, 0x61, 0x7A, 0x30,
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0b0000_0000, 0x70, 0x02,
        ])
        XCTAssertThrowsError(try Yaz0Compressor().decompress(stream)) { error in
            guard case let LZ77StreamError.backReferenceOutOfRange(_, distance, position) = error else {
                return XCTFail("expected backReferenceOutOfRange, got \(error)")
            }
            XCTAssertEqual(distance, 3)
            XCTAssertEqual(position, 0)
        }
    }

    /// A stream whose final match overshoots the declared size is trimmed
    /// to it rather than over-producing.
    func testDecompressTrimsOvershootingFinalMatch() throws {
        let stream = data([
            0x59, 0x61, 0x7A, 0x30,
            0x00, 0x00, 0x00, 0x05,                 // only 5 bytes wanted
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0b1000_0000,
            0x5A,
            0x00, 0x00, 0x00,                       // distance 1, length 0x12
        ])
        let out = try Yaz0Compressor().decompress(stream)
        XCTAssertEqual(out.rawBytes, [UInt8](repeating: 0x5A, count: 5))
    }

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [LZ77StreamError] = [
            .wrongMagic(format: "Yaz0", found: [0, 1, 2, 3]),
            .headerTruncated(format: "Yaz0", length: 4),
            .unexpectedEndOfInput(format: "Yaz0", position: 3, length: 2),
            .backReferenceOutOfRange(format: "Yaz0", distance: 5, outputPosition: 1),
            .truncatedOutput(format: "Yaz0", produced: 1, expected: 5),
        ]
        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    // MARK: - Helpers

    private func deterministicNoise(_ count: Int) -> [UInt8] {
        var state: UInt32 = 0x0BAD_F00D
        return (0 ..< count).map { _ in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(state >> 24)
        }
    }
}
