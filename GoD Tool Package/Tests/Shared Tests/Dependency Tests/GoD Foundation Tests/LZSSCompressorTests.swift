//
//  LZSSCompressorTests.swift
//
//  Coverage for the LZSS compressor/decompressor.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class LZSSCompressorTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func roundTrip(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws {
        let sut = LZSSCompressor()
        let original = data(bytes)
        let compressed = sut.compress(original)
        let decompressed = try sut.decompress(compressed)
        XCTAssertEqual(decompressed.rawBytes, bytes, "plain round-trip mismatch", file: file, line: line)

        // Round trip again supplying the expected size (exercises the trim /
        // early-stop path).
        let sized = try sut.decompress(compressed, expectedSize: bytes.count)
        XCTAssertEqual(sized.rawBytes, bytes, "sized round-trip mismatch", file: file, line: line)
    }

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
        // Long runs exercise the back-reference / match encoding path.
        try roundTrip([UInt8](repeating: 0xAB, count: 500))
    }

    func testRoundTripRepeatingPattern() throws {
        var bytes = [UInt8]()
        for i in 0 ..< 300 { bytes.append(UInt8(i % 7)) }
        try roundTrip(bytes)
    }

    func testRoundTripPseudoRandomIncompressible() throws {
        // Deterministic LCG — effectively incompressible, forces literal runs.
        var state: UInt32 = 0x1234_5678
        var bytes = [UInt8]()
        for _ in 0 ..< 400 {
            state = 1_664_525 &* state &+ 1_013_904_223
            bytes.append(UInt8(state >> 24))
        }
        try roundTrip(bytes)
    }

    func testRoundTripLargerThanWindow() throws {
        // Window is 1 << 12 = 4096; go well beyond it with mixed content.
        var bytes = [UInt8]()
        for i in 0 ..< 10_000 {
            bytes.append(UInt8((i * 31 + (i / 13)) & 0xFF))
        }
        try roundTrip(bytes)
    }

    func testRoundTripLargeRepetitiveAcrossWindow() throws {
        try roundTrip([UInt8](repeating: 0x00, count: 9000))
    }

    // MARK: - Known-good decompression

    func testDecompressKnownLiteralStream() throws {
        // Flag byte 0xFF => next 8 units are literals; then 8 literal bytes.
        let text: [UInt8] = Array("Hello!?.".utf8)
        let stream = data([0xFF] + text)
        let out = try LZSSCompressor().decompress(stream)
        XCTAssertEqual(out.rawBytes, text)
        XCTAssertEqual(out.string(format: .utf8), "Hello!?.")
    }

    // MARK: - Error paths

    func testDecompressThrowsUnexpectedEndOfInputOnTruncatedMatch() {
        // Flag byte with low bit 0 => a position/length pair is expected, but
        // only one of the two required bytes is present.
        let stream = data([0xFE, 0x10])
        XCTAssertThrowsError(try LZSSCompressor().decompress(stream)) { error in
            guard case LZSSError.unexpectedEndOfInput = error else {
                return XCTFail("expected unexpectedEndOfInput, got \(error)")
            }
        }
    }

    func testDecompressThrowsTruncatedOutputWhenUnderProducing() {
        // Valid but short stream: one literal 'A'. Ask for 5 bytes.
        let stream = data([0xFF, 0x41])
        XCTAssertThrowsError(try LZSSCompressor().decompress(stream, expectedSize: 5)) { error in
            guard case let LZSSError.truncatedOutput(produced, expected) = error else {
                return XCTFail("expected truncatedOutput, got \(error)")
            }
            XCTAssertEqual(produced, 1)
            XCTAssertEqual(expected, 5)
        }
    }

    func testExpectedSizeZeroOnEmptyStream() throws {
        let out = try LZSSCompressor().decompress(data([]), expectedSize: 0)
        XCTAssertEqual(out.length, 0)
    }

    func testErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(LZSSError.unexpectedEndOfInput(position: 3, length: 2).description.isEmpty)
        XCTAssertFalse(LZSSError.truncatedOutput(produced: 1, expected: 5).description.isEmpty)
    }

    // MARK: - Parameters

    /// The encoder packs the position's upper bits above the length field,
    /// so a stream cut with one geometry only decodes under that geometry.
    func testCustomParametersRoundTrip() throws {
        var bytes = [UInt8]()
        for i in 0 ..< 3000 { bytes.append(UInt8((i * 7 + i / 11) & 0x0F)) }
        for (ei, ej, p) in [(10, 6, 1), (13, 3, 2), (9, 7, 0), (15, 1, 5)] {
            let sut = LZSSCompressor(EI: ei, EJ: ej, P: p)
            let compressed = sut.compress(data(bytes))
            XCTAssertEqual(try sut.decompress(compressed).rawBytes, bytes, "\(ei)/\(ej)/\(p) round trip")
            XCTAssertEqual(try sut.decompress(compressed, expectedSize: bytes.count).rawBytes, bytes, "\(ei)/\(ej)/\(p) sized round trip")
        }
    }

    func testCustomParametersChangeTheStream() throws {
        var bytes = [UInt8]()
        for i in 0 ..< 600 { bytes.append(UInt8(i % 9)) }
        let custom = LZSSCompressor(EI: 10, EJ: 6, P: 1).compress(data(bytes))
        let standard = LZSSCompressor().compress(data(bytes))
        XCTAssertNotEqual(custom.rawBytes, standard.rawBytes)
        // The default decoder reads the wrong bits out of every pair.
        XCTAssertNotEqual((try? LZSSCompressor().decompress(custom))?.rawBytes, bytes)
    }

    func testCompressedIsSmallerForRepetitiveData() {
        let sut = LZSSCompressor()
        let original = data([UInt8](repeating: 0x77, count: 1000))
        let compressed = sut.compress(original)
        XCTAssertLessThan(compressed.length, original.length)
    }
}
