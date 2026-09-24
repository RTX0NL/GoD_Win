//
//  LZSSHeaderedCompressorTests.swift
//
//  Coverage for the headered LZSS form — the 16-byte `LZSS` header an FSYS
//  entry carries in front of the bare stream.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class LZSSHeaderedCompressorTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// A hand-authored stream: flag byte 0xFF, then eight literals.
    private let literalText: [UInt8] = Array("Hello!?.".utf8)
    private var literalStream: [UInt8] { [0xFF] + literalText }

    /// `literalStream` behind its header.
    private func headered(_ stream: [UInt8], uncompressed: Int, compressed: Int? = nil, reserved: Int = 0) -> [UInt8] {
        LZSSHeaderedCompressor.magic
            + bigEndian(uncompressed)
            + bigEndian(compressed ?? (stream.count + LZSSHeaderedCompressor.headerLength))
            + bigEndian(reserved)
            + stream
    }

    // MARK: - Compress

    func testCompressWritesHeaderFields() throws {
        let input = [UInt8](repeating: 0x5A, count: 300)
        let output = LZSSHeaderedCompressor().compress(data(input))
        let header = try LZSSHeaderedCompressor.header(of: output)

        XCTAssertEqual(Array(output.rawBytes[0 ..< 4]), Array("LZSS".utf8))
        XCTAssertEqual(header.uncompressedSize, input.count)
        XCTAssertEqual(header.compressedSize, output.length, "compressed size counts the header")
        XCTAssertEqual(header.reserved, 0)
    }

    func testCompressBodyIsTheBareStream() {
        let input = Array("PHENAC CITY PHENAC CITY PHENAC CITY".utf8)
        let bare = LZSSCompressor().compress(data(input)).rawBytes
        let output = LZSSHeaderedCompressor().compress(data(input)).rawBytes
        XCTAssertEqual(Array(output[LZSSHeaderedCompressor.headerLength...]), bare)
    }

    func testCompressEmptyInputIsJustAHeader() throws {
        let output = LZSSHeaderedCompressor().compress(data([]))
        XCTAssertEqual(output.length, LZSSHeaderedCompressor.headerLength)
        let header = try LZSSHeaderedCompressor.header(of: output)
        XCTAssertEqual(header.uncompressedSize, 0)
        XCTAssertEqual(header.compressedSize, LZSSHeaderedCompressor.headerLength)
        XCTAssertEqual(try LZSSHeaderedCompressor().decompress(output).length, 0)
    }

    // MARK: - Decompress

    func testDecompressHandAuthoredStream() throws {
        let stream = data(headered(literalStream, uncompressed: literalText.count))
        let out = try LZSSHeaderedCompressor().decompress(stream)
        XCTAssertEqual(out.rawBytes, literalText)
    }

    func testDecompressIgnoresTrailingBytesBeyondCompressedSize() throws {
        let stream = data(headered(literalStream, uncompressed: literalText.count) + [0xDE, 0xAD, 0xBE, 0xEF])
        let out = try LZSSHeaderedCompressor().decompress(stream)
        XCTAssertEqual(out.rawBytes, literalText)
    }

    func testDecompressThrowsWhenCompressedSizeOverrunsData() {
        let stream = data(headered(literalStream, uncompressed: literalText.count, compressed: 0x100))
        XCTAssertThrowsError(try LZSSHeaderedCompressor().decompress(stream)) { error in
            guard case LZ77StreamError.unexpectedEndOfInput(let format, _, _) = error else {
                return XCTFail("expected unexpectedEndOfInput, got \(error)")
            }
            XCTAssertEqual(format, "LZSS")
        }
    }

    func testDecompressThrowsWhenCompressedSizeIsShorterThanTheHeader() {
        let stream = data(headered(literalStream, uncompressed: literalText.count, compressed: 8))
        XCTAssertThrowsError(try LZSSHeaderedCompressor().decompress(stream)) { error in
            guard case LZ77StreamError.unexpectedEndOfInput = error else {
                return XCTFail("expected unexpectedEndOfInput, got \(error)")
            }
        }
    }

    func testDecompressHonorsDeclaredUncompressedSize() throws {
        // Declaring fewer bytes trims the output to that size.
        let short = data(headered(literalStream, uncompressed: 5))
        XCTAssertEqual(try LZSSHeaderedCompressor().decompress(short).rawBytes, Array(literalText[0 ..< 5]))

        // Declaring more bytes than the stream produces is a truncated stream.
        let long = data(headered(literalStream, uncompressed: 20))
        XCTAssertThrowsError(try LZSSHeaderedCompressor().decompress(long)) { error in
            guard case LZSSError.truncatedOutput(let produced, let expected) = error else {
                return XCTFail("expected truncatedOutput, got \(error)")
            }
            XCTAssertEqual(produced, literalText.count)
            XCTAssertEqual(expected, 20)
        }
    }

    // MARK: - Header

    func testHeaderReadsAllFields() throws {
        let header = try LZSSHeaderedCompressor.header(
            of: data(headered(literalStream, uncompressed: 0x1234, compressed: 0x19, reserved: 0x0BAD_F00D))
        )
        XCTAssertEqual(header, .init(uncompressedSize: 0x1234, compressedSize: 0x19, reserved: 0x0BAD_F00D))
    }

    func testHeaderThrowsOnTruncatedInput() {
        XCTAssertThrowsError(try LZSSHeaderedCompressor.header(of: data(Array("LZSS".utf8) + [0, 0]))) { error in
            guard case LZ77StreamError.headerTruncated(let format, let length) = error else {
                return XCTFail("expected headerTruncated, got \(error)")
            }
            XCTAssertEqual(format, "LZSS")
            XCTAssertEqual(length, 6)
        }
    }

    func testHeaderThrowsOnWrongMagic() {
        let foreign = Array("Yaz0".utf8) + [UInt8](repeating: 0, count: 12)
        XCTAssertThrowsError(try LZSSHeaderedCompressor.header(of: data(foreign))) { error in
            guard case LZ77StreamError.wrongMagic(let format, let found) = error else {
                return XCTFail("expected wrongMagic, got \(error)")
            }
            XCTAssertEqual(format, "LZSS")
            XCTAssertEqual(found, Array("Yaz0".utf8))
        }
    }

    // MARK: - Round trips

    private func roundTrip(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws {
        let sut = LZSSHeaderedCompressor()
        let compressed = sut.compress(data(bytes))
        XCTAssertEqual(try LZSSHeaderedCompressor.header(of: compressed).uncompressedSize, bytes.count, file: file, line: line)
        XCTAssertEqual(try sut.decompress(compressed).rawBytes, bytes, "round-trip mismatch", file: file, line: line)
    }

    func testRoundTripEmpty() throws { try roundTrip([]) }
    func testRoundTripSingleByte() throws { try roundTrip([0x42]) }
    func testRoundTripHighlyRepetitive() throws { try roundTrip([UInt8](repeating: 0xAB, count: 5000)) }

    func testRoundTripIncompressible() throws {
        var state: UInt32 = 0x1234_5678
        var bytes = [UInt8]()
        for _ in 0 ..< 700 {
            state = 1_664_525 &* state &+ 1_013_904_223
            bytes.append(UInt8(state >> 24))
        }
        try roundTrip(bytes)
    }

    // MARK: - Custom codec

    func testCustomCodecIsUsedInBothDirections() throws {
        var bytes = [UInt8]()
        for i in 0 ..< 600 { bytes.append(UInt8(i % 9)) }
        let custom = LZSSHeaderedCompressor(codec: LZSSCompressor(EI: 10, EJ: 6, P: 1))
        let compressed = custom.compress(data(bytes))

        XCTAssertEqual(try custom.decompress(compressed).rawBytes, bytes)
        XCTAssertNotEqual(
            compressed.rawBytes, LZSSHeaderedCompressor().compress(data(bytes)).rawBytes,
            "a different geometry must produce a different stream"
        )
        // Reading it back with the default geometry misinterprets every pair.
        let misread = try? LZSSHeaderedCompressor().decompress(compressed)
        XCTAssertNotEqual(misread?.rawBytes, bytes)
    }
}
