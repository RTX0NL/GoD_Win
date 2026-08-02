import XCTest
import Foundation
import GoDFoundation
import TestSupport

/// Golden encode/decode tests for `LZSSCompressor` (the codec inside FSYS
/// entries). Behavioral round-trips live in `LZSSCompressorTests`; this
/// file pins the on-wire stream format with checked-in fixtures (defined
/// by `LZSSFixtures` in `FixtureCatalog`): `lzss_sample.bin` is a known
/// mixed-compressibility input and `lzss_sample.lzss` its compressed form.
/// Any encoder change that alters the stream (and could break FSYS
/// rebuilds or game compatibility) fails encode; any decoder change that
/// misreads real streams fails decode.
///
/// Regenerate: `swift run FixtureGen`
final class LZSSGoldenTests: XCTestCase {

    private let compressor = LZSSCompressor()

    /// DECODE: the frozen compressed stream decompresses to the original.
    func testLZSS_decompress_producesGoldenPlaintext() throws {
        let compressed = try Fixtures.data("lzss_sample.lzss")
        let expected = try Fixtures.data("lzss_sample.bin")
        let decompressed = try compressor.decompress(compressed, expectedSize: expected.length)
        assertBytesEqual(decompressed, expected)
    }

    /// ENCODE: the frozen input compresses to the frozen stream byte-for-
    /// byte (the encoder is deterministic).
    func testLZSS_compress_producesGoldenStream() throws {
        let input = try Fixtures.data("lzss_sample.bin")
        let expected = try Fixtures.data("lzss_sample.lzss")
        assertBytesEqual(compressor.compress(input), expected)
    }

    /// The frozen stream must actually be smaller than the input — guards
    /// against freezing a degenerate all-literal stream.
    func testLZSS_goldenStream_isSmallerThanInput() throws {
        let input = try Fixtures.data("lzss_sample.bin")
        let compressed = try Fixtures.data("lzss_sample.lzss")
        XCTAssertLessThan(compressed.length, input.length)
    }
}
