//
//  NintendoCompressionGoldenTests.swift
//
//  Golden encode/decode tests for Yaz0 and Yay0. Behavioral round-trips
//  live in the per-codec test files; this one pins the on-wire streams with
//  checked-in fixtures (defined by `NintendoCompressionFixtures` in
//  `FixtureCatalog`): `nintendo_lz77_sample.bin` is a known
//  mixed-compressibility input and the `.yaz0` / `.yay0` files are its
//  compressed forms.
//
//  An encoder change that alters a stream fails encode; a decoder change
//  that misreads a frozen stream fails decode. Neither direction is
//  evidence the streams match Nintendo's tooling — the hand-authored
//  streams in the codec tests are what stands in for that.
//
//  Regenerate: `swift run FixtureGen`
//

import XCTest
import Foundation
import GoDFoundation
import TestSupport

final class NintendoCompressionGoldenTests: XCTestCase {

    // MARK: - Yaz0

    /// DECODE: the frozen stream decompresses to the original.
    func testYaz0_decompress_producesGoldenPlaintext() throws {
        let compressed = try Fixtures.data("nintendo_lz77_sample.yaz0")
        let expected = try Fixtures.data("nintendo_lz77_sample.bin")
        assertBytesEqual(try Yaz0Compressor().decompress(compressed), expected)
    }

    /// ENCODE: the frozen input compresses to the frozen stream byte-for-
    /// byte (the encoder is deterministic).
    func testYaz0_compress_producesGoldenStream() throws {
        let input = try Fixtures.data("nintendo_lz77_sample.bin")
        let expected = try Fixtures.data("nintendo_lz77_sample.yaz0")
        assertBytesEqual(Yaz0Compressor().compress(input), expected)
    }

    // MARK: - Yay0

    func testYay0_decompress_producesGoldenPlaintext() throws {
        let compressed = try Fixtures.data("nintendo_lz77_sample.yay0")
        let expected = try Fixtures.data("nintendo_lz77_sample.bin")
        assertBytesEqual(try Yay0Compressor().decompress(compressed), expected)
    }

    func testYay0_compress_producesGoldenStream() throws {
        let input = try Fixtures.data("nintendo_lz77_sample.bin")
        let expected = try Fixtures.data("nintendo_lz77_sample.yay0")
        assertBytesEqual(Yay0Compressor().compress(input), expected)
    }

    // MARK: - Sanity

    /// Guards against freezing a degenerate all-literal stream, which would
    /// pass the encode tests while proving nothing about the match finder.
    func testGoldenStreamsAreSmallerThanTheInput() throws {
        let input = try Fixtures.data("nintendo_lz77_sample.bin")
        for name in ["nintendo_lz77_sample.yaz0", "nintendo_lz77_sample.yay0"] {
            XCTAssertLessThan(try Fixtures.data(name).length, input.length, "\(name) is not compressed")
        }
    }

    /// Both codecs encode the same decisions, so the format sniffer should
    /// place each frozen stream with its own format.
    func testGoldenStreamsAreDetectedAsTheirFormat() throws {
        XCTAssertEqual(CompressionFormat.detect(try Fixtures.data("nintendo_lz77_sample.yaz0")), .yaz0)
        XCTAssertEqual(CompressionFormat.detect(try Fixtures.data("nintendo_lz77_sample.yay0")), .yay0)
    }
}
