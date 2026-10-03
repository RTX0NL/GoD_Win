//
//  ZstdDecoderTests.swift
//
//  Decode tests for the pure-Swift Zstandard decompressor.
//
//  Validation is by cross-implementation rather than round trip: GoD-Tool
//  has no Zstandard *encoder*, so every compressed fixture here was produced
//  by the reference `zstd` CLI (1.5.x) and the test asserts we recover the
//  original bytes. That is the same trick `ReferenceLZ77Decoders` plays for
//  Yaz0 — an independent implementation on the other side of the codec, so
//  the test can't pass by being wrong in matching ways.
//
//  `zstd_sample.bin` is built to reach every branch of the decoder: runs of
//  zeroes (RLE blocks and RLE literals), incompressible noise (raw blocks),
//  natural-language text (Huffman literals with FSE-coded weights), a small
//  alphabet, and long repeats (the high match-length codes). At 167 KB it
//  spans more than one 128 KiB block, which is what makes the second block
//  reuse the first's Huffman tree (treeless literals) and FSE tables
//  (repeat mode) — paths a single-block fixture never reaches.
//
//  Regenerate: `zstd -1 / -19 / -3 --check` over `zstd_sample.bin`.
//

import XCTest
import Foundation
@testable import GoDFoundation
import TestSupport

final class ZstdDecoderTests: XCTestCase {

    // MARK: - Fixtures

    func testDecodesReferenceStreamAtLevel1() throws {
        try assertFixtureDecodes("zstd_sample.l1.zst", to: "zstd_sample.bin")
    }

    func testDecodesReferenceStreamAtLevel19() throws {
        try assertFixtureDecodes("zstd_sample.l19.zst", to: "zstd_sample.bin")
    }

    /// The `--check` variant carries an XXH64 content checksum, so this also
    /// exercises verification rather than just skipping the trailing four
    /// bytes.
    func testDecodesReferenceStreamWithContentChecksum() throws {
        try assertFixtureDecodes("zstd_sample.l3-check.zst", to: "zstd_sample.bin")
    }

    /// A small alphabet keeps each block's literals under 1 KiB, which is
    /// where the encoder uses the single-stream literals form instead of the
    /// usual four.
    func testDecodesSmallAlphabetStream() throws {
        try assertFixtureDecodes("zstd_small_alphabet.zst", to: "zstd_small_alphabet.bin")
    }

    /// One fixture holding 25 back-to-back frames, each a `--check` frame
    /// over a payload of a different length (0 through 1000), and one plain
    /// file holding their payloads concatenated.
    ///
    /// This is what pins XXH64 against the reference implementation: the
    /// checksums are the ones real `zstd` computed, and the lengths are
    /// chosen to cross every branch of the hash — under 32 bytes skips the
    /// stripe loop entirely, and the tail handles 8-, 4- and 1-byte
    /// remainders in turn. It also exercises decoding several frames from
    /// one buffer, which is how an RVZ group's payload can arrive.
    func testDecodesReferenceStreamsWithChecksumsAtEveryLength() throws {
        try assertFixtureDecodes("zstd_checksum_lengths.zst", to: "zstd_checksum_lengths.bin")
    }

    /// A real Dolphin-produced frame carrying a sequence whose extra-bit
    /// fields are long enough to overrun the bit reader's 64-bit window.
    ///
    /// Two of the 35,859 groups in a 2.6 GB RVZ hit this, and nothing
    /// smaller did: the common sequence asks for an offset and two short
    /// lengths, well inside one window, so a decoder that reads all three
    /// plus the three state updates without reloading is right almost
    /// always. It is kept as a fixture because "almost always" is exactly
    /// what a regression here would look like again.
    ///
    /// The expected content is pinned by its SHA-1 rather than a second
    /// fixture — `shasum -a 1` over the reference `zstd -d` output — because
    /// the plain form is 127 KB and says nothing a digest doesn't.
    func testDecodesAFrameWithMaximalSequenceExtraBits() throws {
        let stream = try Fixtures.data("zstd_long_sequence.zst").rawBytes
        let decoded = try Zstd.decompress(stream)
        XCTAssertEqual(decoded.count, 126_978)
        XCTAssertEqual(
            SHA1.hash(decoded).map { String(format: "%02x", $0) }.joined(),
            "94f05b235504fd29ba89e7d5bebac676854f1d28"
        )
    }

    private func assertFixtureDecodes(_ compressed: String, to plain: String) throws {
        let stream = try Fixtures.data(compressed).rawBytes
        let expected = try Fixtures.data(plain).rawBytes
        let decoded = try Zstd.decompress(stream, expectedSize: expected.count)
        XCTAssertEqual(decoded.count, expected.count, "\(compressed) decoded to the wrong length")
        XCTAssertEqual(decoded, expected, "\(compressed) did not reproduce \(plain)")
    }

    /// A corrupted checksum has to fail: the whole point of reading it is to
    /// catch a mis-decode, so a decoder that ignored it would report success
    /// on garbage.
    func testRejectsACorruptedContentChecksum() throws {
        var stream = try Fixtures.data("zstd_sample.l3-check.zst").rawBytes
        stream[stream.count - 1] ^= 0xFF
        XCTAssertThrowsError(try Zstd.decompress(stream)) { error in
            guard case ZstdError.checksumMismatch = error else {
                return XCTFail("expected a checksum mismatch, got \(error)")
            }
        }
    }

    // MARK: - Framing

    func testDetectsTheFrameMagic() {
        XCTAssertTrue(Zstd.isZstdFrame([0x28, 0xB5, 0x2F, 0xFD, 0x00]))
        XCTAssertFalse(Zstd.isZstdFrame([0x28, 0xB5, 0x2F, 0xFC]))
        XCTAssertFalse(Zstd.isZstdFrame([0x28, 0xB5]))
    }

    /// A raw block is stored verbatim, and a single-segment frame declares
    /// its content size in one byte. Hand-built so the framing is checked
    /// without leaning on the entropy coders.
    func testDecodesAHandBuiltRawBlockFrame() throws {
        let payload: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02]
        var frame = Zstd.magic
        frame.append(0x20)                                  // single segment, 1-byte content size
        frame.append(UInt8(payload.count))
        let header = UInt32(payload.count) << 3 | 0b001     // last block, type 0 (raw)
        frame.append(UInt8(truncatingIfNeeded: header))
        frame.append(UInt8(truncatingIfNeeded: header >> 8))
        frame.append(UInt8(truncatingIfNeeded: header >> 16))
        frame.append(contentsOf: payload)
        XCTAssertEqual(try Zstd.decompress(frame), payload)
    }

    /// An RLE block stores one byte and a length.
    func testDecodesAHandBuiltRLEBlockFrame() throws {
        let length = 300
        var frame = Zstd.magic
        frame.append(0xA0)                                  // single segment, 4-byte content size
        for i in 0..<4 { frame.append(UInt8(truncatingIfNeeded: length >> (8 * i))) }
        let header = UInt32(length) << 3 | 0b011            // last block, type 1 (RLE)
        frame.append(UInt8(truncatingIfNeeded: header))
        frame.append(UInt8(truncatingIfNeeded: header >> 8))
        frame.append(UInt8(truncatingIfNeeded: header >> 16))
        frame.append(0x5A)
        XCTAssertEqual(try Zstd.decompress(frame), [UInt8](repeating: 0x5A, count: length))
    }

    /// A skippable frame is stepped over without contributing output — the
    /// mechanism a container uses to interleave its own metadata.
    func testSkipsASkippableFrame() throws {
        var frame: [UInt8] = [0x50, 0x2A, 0x4D, 0x18, 0x03, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0xCC]
        let payload: [UInt8] = [0x11, 0x22]
        frame.append(contentsOf: Zstd.magic)
        frame.append(0x20)
        frame.append(UInt8(payload.count))
        let header = UInt32(payload.count) << 3 | 0b001
        frame.append(UInt8(truncatingIfNeeded: header))
        frame.append(UInt8(truncatingIfNeeded: header >> 8))
        frame.append(UInt8(truncatingIfNeeded: header >> 16))
        frame.append(contentsOf: payload)
        XCTAssertEqual(try Zstd.decompress(frame), payload)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try Zstd.decompress([0x00, 0x01, 0x02, 0x03, 0x04]))
        XCTAssertThrowsError(try Zstd.decompress([0x28, 0xB5, 0x2F]))
        // Block type 3 is reserved.
        var frame = Zstd.magic
        frame.append(contentsOf: [0x20, 0x04, 0x07, 0x00, 0x00])
        XCTAssertThrowsError(try Zstd.decompress(frame))
    }

    /// A frame that needs a dictionary is refused by name rather than
    /// decoded into wrong bytes — GoD-Tool never supplies one.
    func testRejectsADictionaryFrame() {
        var frame = Zstd.magic
        frame.append(0x21)                                  // single segment, 1-byte dictionary ID
        frame.append(0x07)                                  // dictionary ID 7
        frame.append(0x01)                                  // content size
        XCTAssertThrowsError(try Zstd.decompress(frame)) { error in
            guard case ZstdError.unsupported = error else {
                return XCTFail("expected an unsupported-stream error, got \(error)")
            }
        }
    }

    // MARK: - Huffman tree description

    /// The direct (nibble-per-weight) tree description. The reference
    /// encoder almost never emits it — FSE-coded weights are usually
    /// smaller — so it is built by hand here rather than waiting for a
    /// fixture to happen to contain one.
    func testBuildsATableFromDirectWeights() throws {
        // Four symbols: weights 2, 1, 1 transmitted; the fourth is implied.
        // Total = 2 + 1 + 1 = 4, so maxBits = 3 and 8 - 4 = 4 states are
        // left, giving the last symbol weight 3.
        let table = try ZstdHuffmanTable(weights: [2, 1, 1])
        XCTAssertEqual(table.maxBits, 3)
        XCTAssertEqual(table.entries.count, 8)
        // Codes go by weight ascending then symbol ascending: symbols 1 and
        // 2 (weight 1, 1 slot each), then symbol 0 (weight 2, 2 slots),
        // then symbol 3 (weight 3, 4 slots).
        XCTAssertEqual(table.entries.map(\.symbol), [1, 2, 0, 0, 3, 3, 3, 3])
        XCTAssertEqual(table.entries.map(\.nbBits), [3, 3, 2, 2, 1, 1, 1, 1])
    }

    func testRejectsWeightsThatDoNotLeaveOneSymbol() {
        // 4 + 1 = 5 states used of 8, leaving 3 — not a whole symbol's
        // worth, so the description can't be the one the encoder wrote.
        XCTAssertThrowsError(try ZstdHuffmanTable(weights: [3, 1]))
        XCTAssertThrowsError(try ZstdHuffmanTable(weights: []))
        // A weight past 11 would need a code longer than the format allows.
        XCTAssertThrowsError(try ZstdHuffmanTable(weights: [12, 1]))
    }

    // MARK: - Bit reader

    /// The reader walks backwards from the last byte, whose highest set bit
    /// is the end marker and is not data.
    func testBitReaderReadsBackwardFromTheEndMarker() throws {
        // 0b1_0110100 in the final byte: marker at bit 7, then 0110100.
        var reader = try ZstdBitReader(bytes: [0xB4], range: 0..<1)
        XCTAssertEqual(reader.readBits(3), 0b011)
        XCTAssertEqual(reader.readBits(4), 0b0100)
    }

    func testBitReaderRejectsAMissingEndMarker() {
        XCTAssertThrowsError(try ZstdBitReader(bytes: [0x00], range: 0..<1))
        XCTAssertThrowsError(try ZstdBitReader(bytes: [], range: 0..<0))
    }
}
