//
//  Yay0CompressorTests.swift
//
//  Coverage for the Yay0 codec. The compression decisions are Yaz0's, so
//  what these mostly exercise is the three-table layout: that the offsets
//  in the header land on the right tables, that the mask table stays a
//  whole number of 32-bit words, and that literals and long-match counts
//  interleave in the chunk table in operation order.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class Yay0CompressorTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func roundTrip(
        _ bytes: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sut = Yay0Compressor()
        let compressed = sut.compress(data(bytes))

        let decompressed = try sut.decompress(compressed)
        XCTAssertEqual(decompressed.rawBytes, bytes, "round-trip mismatch", file: file, line: line)

        XCTAssertEqual(
            ReferenceYay0.decode(compressed.rawBytes),
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
        try roundTrip((0 ..< 10_000).map { UInt8(($0 * 31 + ($0 / 13)) & 0xFF) })
    }

    func testRoundTripLongRunExceedsMaximumMatchLength() throws {
        try roundTrip([UInt8](repeating: 0x00, count: 9000))
    }

    /// Exactly 32 operations would fill one mask word; a couple more force
    /// a second word whose unused bits are never reached.
    func testRoundTripAcrossMaskWordBoundary() throws {
        try roundTrip((0 ..< 35).map { UInt8(truncatingIfNeeded: $0 &* 97) })
    }

    // MARK: - Known-good stream (hand-authored, not encoder output)

    /// The same "ABCABCABCABCD" as the Yaz0 tests, repacked into Yay0's
    /// three tables: one mask word, one link, four literals.
    func testDecompressHandAuthoredStream() throws {
        let stream: [UInt8] = [
            0x59, 0x61, 0x79, 0x30,                 // "Yay0"
            0x00, 0x00, 0x00, 0x0D,                 // 13 bytes out
            0x00, 0x00, 0x00, 0x14,                 // link table at 0x14
            0x00, 0x00, 0x00, 0x16,                 // chunk table at 0x16
            0b1110_1000, 0x00, 0x00, 0x00,          // mask word
            0x70, 0x02,                             // distance 3, length 9
            0x41, 0x42, 0x43, 0x44,                 // 'A' 'B' 'C' 'D'
        ]
        let out = try Yay0Compressor().decompress(data(stream))
        XCTAssertEqual(out.string(format: .utf8), "ABCABCABCABCD")
    }

    // MARK: - Layout

    func testHeaderOffsetsBoundTheTablesInOrder() throws {
        let compressed = Yay0Compressor().compress(data([UInt8](repeating: 0x33, count: 600)))
        let header = try Yay0Compressor.header(of: compressed)

        XCTAssertEqual(header.uncompressedSize, 600)
        XCTAssertGreaterThanOrEqual(header.linkTableOffset, Yay0Compressor.headerLength)
        XCTAssertLessThanOrEqual(header.linkTableOffset, header.chunkTableOffset)
        XCTAssertLessThanOrEqual(header.chunkTableOffset, compressed.length)
    }

    func testMaskTableIsAWholeNumberOfWords() throws {
        // One operation only, so the mask table is a single byte's worth of
        // flags and has to be padded out to four.
        let compressed = Yay0Compressor().compress(data([0x01]))
        let header = try Yay0Compressor.header(of: compressed)
        let maskTableLength = header.linkTableOffset - Yay0Compressor.headerLength
        XCTAssertEqual(maskTableLength % 4, 0)
        XCTAssertEqual(maskTableLength, 4)
    }

    func testAllLiteralInputHasAnEmptyLinkTable() throws {
        // Four bytes with nothing repeated: every operation is a literal.
        let compressed = Yay0Compressor().compress(data([0x01, 0x02, 0x03, 0x04]))
        let header = try Yay0Compressor.header(of: compressed)
        XCTAssertEqual(header.linkTableOffset, header.chunkTableOffset)
        XCTAssertEqual(compressed.length - header.chunkTableOffset, 4)
    }

    func testCompressWritesMagic() {
        let compressed = Yay0Compressor().compress(data([UInt8](repeating: 0x11, count: 300)))
        XCTAssertEqual(Array(compressed.rawBytes[0 ..< 4]), Yay0Compressor.magic)
    }

    func testCompressOfEmptyInputIsHeaderOnly() throws {
        let compressed = Yay0Compressor().compress(data([]))
        XCTAssertEqual(compressed.length, Yay0Compressor.headerLength)
        XCTAssertEqual(try Yay0Compressor().decompress(compressed).length, 0)
    }

    func testCompressedIsSmallerForRepetitiveData() {
        let input = data([UInt8](repeating: 0x77, count: 4000))
        XCTAssertLessThan(Yay0Compressor().compress(input).length, input.length)
    }

    /// Both codecs make the same decisions, so they should agree on how
    /// many bytes of literal data there are to store.
    func testChunkTableMatchesLiteralAndLongMatchCount() throws {
        var bytes = Array("MYSTERY DUNGEON ".utf8)
        for _ in 0 ..< 8 { bytes += bytes.prefix(16) }
        bytes += [UInt8](repeating: 0, count: 300)
        var state: UInt32 = 0x5941_5930
        bytes += (0 ..< 120).map { _ in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(state >> 24)
        }
        let input = data(bytes)
        let compressed = Yay0Compressor().compress(input)
        let header = try Yay0Compressor.header(of: compressed)
        let chunkTableLength = compressed.length - header.chunkTableOffset

        let tokens = LZ77Encoder().tokenize(input.rawBytes)
        let expected = tokens.reduce(0) { total, token in
            switch token {
            case .literal: return total + 1
            case let .match(_, length): return total + (length >= 0x12 ? 1 : 0)
            }
        }
        XCTAssertEqual(chunkTableLength, expected)
    }

    // MARK: - Error paths

    func testDecompressThrowsOnWrongMagic() {
        let stream = data([0x59, 0x61, 0x7A, 0x30] + [UInt8](repeating: 0, count: 12))
        XCTAssertThrowsError(try Yay0Compressor().decompress(stream)) { error in
            guard case let LZ77StreamError.wrongMagic(format, _) = error else {
                return XCTFail("expected wrongMagic, got \(error)")
            }
            XCTAssertEqual(format, "Yay0")
        }
    }

    func testDecompressThrowsOnTruncatedHeader() {
        XCTAssertThrowsError(try Yay0Compressor().decompress(data([0x59, 0x61, 0x79, 0x30]))) { error in
            guard case LZ77StreamError.headerTruncated = error else {
                return XCTFail("expected headerTruncated, got \(error)")
            }
        }
    }

    func testDecompressThrowsWhenATableOffsetPointsOutsideTheStream() {
        let stream = data([
            0x59, 0x61, 0x79, 0x30,
            0x00, 0x00, 0x00, 0x20,                 // wants 32 bytes
            0x00, 0x00, 0xFF, 0x00,                 // link table past the end
            0x00, 0x00, 0xFF, 0x00,                 // chunk table past the end
            0b0000_0000, 0x00, 0x00, 0x00,
        ])
        XCTAssertThrowsError(try Yay0Compressor().decompress(stream)) { error in
            guard case LZ77StreamError.unexpectedEndOfInput = error else {
                return XCTFail("expected unexpectedEndOfInput, got \(error)")
            }
        }
    }

    func testDecompressThrowsOnBackReferenceBeforeStart() {
        let stream = data([
            0x59, 0x61, 0x79, 0x30,
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00, 0x00, 0x14,
            0x00, 0x00, 0x00, 0x16,
            0b0000_0000, 0x00, 0x00, 0x00,          // first operation is a match
            0x70, 0x02,                             // distance 3, nothing behind it
            0x00, 0x00,
        ])
        XCTAssertThrowsError(try Yay0Compressor().decompress(stream)) { error in
            guard case let LZ77StreamError.backReferenceOutOfRange(_, distance, _) = error else {
                return XCTFail("expected backReferenceOutOfRange, got \(error)")
            }
            XCTAssertEqual(distance, 3)
        }
    }
}
