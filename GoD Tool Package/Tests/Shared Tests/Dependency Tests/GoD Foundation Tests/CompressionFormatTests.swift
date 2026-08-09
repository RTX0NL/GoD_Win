//
//  CompressionFormatTests.swift
//
//  Coverage for sniffing a compressed stream and dispatching to its codec.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class CompressionFormatTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private let sample = Array("PHENAC CITY PHENAC CITY PHENAC CITY".utf8)

    // MARK: - Detection

    func testDetectsYaz0() {
        let stream = Yaz0Compressor().compress(data(sample))
        XCTAssertEqual(CompressionFormat.detect(stream), .yaz0)
        XCTAssertTrue(CompressionFormat.isCompressed(stream))
    }

    func testDetectsYay0() {
        let stream = Yay0Compressor().compress(data(sample))
        XCTAssertEqual(CompressionFormat.detect(stream), .yay0)
        XCTAssertTrue(CompressionFormat.isCompressed(stream))
    }

    func testDoesNotDetectPlainData() {
        XCTAssertNil(CompressionFormat.detect(data(sample)))
        XCTAssertFalse(CompressionFormat.isCompressed(data(sample)))
    }

    func testDoesNotDetectDataShorterThanAMagic() {
        XCTAssertNil(CompressionFormat.detect(data([0x59, 0x61, 0x7A])))
        XCTAssertNil(CompressionFormat.detect(data([])))
    }

    /// Yaz0 and Yay0 differ in one byte, so the sniffer must not be
    /// matching a shared prefix.
    func testDoesNotConfuseTheTwoSimilarMagics() {
        XCTAssertNil(CompressionFormat.detect(data(Array("Yaz1".utf8) + [UInt8](repeating: 0, count: 16))))
        XCTAssertNil(CompressionFormat.detect(data(Array("Yay1".utf8) + [UInt8](repeating: 0, count: 16))))
    }

    func testMagicLengthCoversEveryFormat() {
        for format in CompressionFormat.allCases {
            XCTAssertLessThanOrEqual(format.magic.count, CompressionFormat.magicLength)
            XCTAssertFalse(format.name.isEmpty)
        }
        XCTAssertEqual(CompressionFormat.magicLength, 4)
    }

    // MARK: - Dispatch

    func testMakeCompressorRoundTripsEveryFormat() throws {
        for format in CompressionFormat.allCases {
            let compressor = format.makeCompressor()
            let compressed = compressor.compress(data(sample))
            XCTAssertEqual(
                CompressionFormat.detect(compressed), format,
                "\(format.name) stream should be detected as itself"
            )
            XCTAssertEqual(
                try compressor.decompress(compressed).rawBytes, sample,
                "\(format.name) failed to round-trip"
            )
        }
    }

    func testUncompressedSizeReadsWithoutDecompressing() throws {
        for format in CompressionFormat.allCases {
            let compressed = format.makeCompressor().compress(data(sample))
            XCTAssertEqual(try format.uncompressedSize(of: compressed), sample.count)
        }
    }

    func testUncompressedSizeThrowsOnAForeignStream() {
        XCTAssertThrowsError(try CompressionFormat.yaz0.uncompressedSize(of: data(sample)))
        XCTAssertThrowsError(try CompressionFormat.yay0.uncompressedSize(of: data(sample)))
    }

    func testDecompressIfRecognizedUnwrapsCompressedInput() throws {
        for format in CompressionFormat.allCases {
            let compressed = format.makeCompressor().compress(data(sample))
            let unwrapped = try CompressionFormat.decompressIfRecognized(compressed)
            XCTAssertEqual(unwrapped.rawBytes, sample)
        }
    }

    func testDecompressIfRecognizedPassesPlainInputThrough() throws {
        let plain = data(sample)
        let result = try CompressionFormat.decompressIfRecognized(plain)
        XCTAssertEqual(result.rawBytes, sample)
    }

    // MARK: - Serialization

    /// The raw values end up in config files, so they are part of the
    /// public surface and must not drift.
    func testRawValuesAreStable() {
        XCTAssertEqual(CompressionFormat.yaz0.rawValue, "yaz0")
        XCTAssertEqual(CompressionFormat.yay0.rawValue, "yay0")
        XCTAssertEqual(CompressionFormat(rawValue: "yaz0"), .yaz0)
        XCTAssertNil(CompressionFormat(rawValue: "Yaz0"))
    }

    func testCodableRoundTrip() throws {
        // Annotated because the codebase adds a `GoDData`-returning
        // overload of `encode`.
        let encoded: Data = try JSONEncoder().encode(CompressionFormat.allCases)
        let decoded = try JSONDecoder().decode([CompressionFormat].self, from: encoded)
        XCTAssertEqual(decoded, CompressionFormat.allCases)
    }
}
