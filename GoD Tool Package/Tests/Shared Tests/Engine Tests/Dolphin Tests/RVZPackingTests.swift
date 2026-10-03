import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// RVZ packing is the preprocessing pass that sits between raw disc
/// data and Zstd/LZMA. These tests cover wire-format roundtripping and
/// PRNG determinism — cross-check against real RVZ output is deferred
/// until the full RVZ pipeline lands.
final class RVZPackingTests: XCTestCase {
    typealias Seg = RVZPacking.Segment

    // MARK: - PRNG

    func testPRNG_sameSeedSameOutput() {
        let seed = (0..<68).map { UInt8(truncatingIfNeeded: $0) }
        var a = RVZPacking.PRNG(seed: seed)
        var b = RVZPacking.PRNG(seed: seed)
        XCTAssertEqual(a.read(1024), b.read(1024))
    }

    func testPRNG_differentSeedDifferentOutput() {
        let s1 = (0..<68).map { UInt8(truncatingIfNeeded: $0) }
        var s2 = s1
        s2[0] ^= 0xFF
        var a = RVZPacking.PRNG(seed: s1)
        var b = RVZPacking.PRNG(seed: s2)
        XCTAssertNotEqual(a.read(512), b.read(512))
    }

    func testPRNG_streamingMatchesOneShot() {
        let seed = (0..<68).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        let chunks = [7, 100, 1, 521 * 4, 2000, 467]       // sum = 4659
        let total = chunks.reduce(0, +)
        var oneShotPRNG = RVZPacking.PRNG(seed: seed)
        var streamingPRNG = RVZPacking.PRNG(seed: seed)
        let oneShot = oneShotPRNG.read(total)
        var streaming = [UInt8]()
        // Exercise partial-word continuation by pulling odd-sized
        // chunks that don't fall on 4-byte boundaries.
        for size in chunks {
            streaming.append(contentsOf: streamingPRNG.read(size))
        }
        XCTAssertEqual(oneShot, streaming)
    }

    func testPRNG_outputIsNotTrivial() {
        let seed = (0..<68).map { UInt8(truncatingIfNeeded: $0) }
        var prng = RVZPacking.PRNG(seed: seed)
        let head = prng.read(256)
        XCTAssertGreaterThan(Set(head).count, 32)
    }

    // MARK: - Wire-format roundtrips

    func testPacking_literalSegmentRoundtrip() throws {
        let bytes: [UInt8] = (0..<100).map { UInt8(truncatingIfNeeded: $0) }
        let segs: [Seg] = [.literal(bytes: bytes)]
        let encoded = RVZPacking.encode(segs)
        // Header: 4-byte BE length = 100 (0x64). No MSB.
        XCTAssertEqual(Array(encoded[0..<4]), [0, 0, 0, 0x64])
        XCTAssertEqual(try RVZPacking.decode(encoded), segs)
    }

    func testPacking_packedSegmentRoundtrip() throws {
        let seed = (0..<68).map { UInt8(truncatingIfNeeded: $0 &* 3) }
        let segs: [Seg] = [.packed(size: 0x1234, seed: seed)]
        let encoded = RVZPacking.encode(segs)
        // Header's MSB set (tag) | size = 0x80001234.
        XCTAssertEqual(Array(encoded[0..<4]), [0x80, 0x00, 0x12, 0x34])
        XCTAssertEqual(try RVZPacking.decode(encoded), segs)
    }

    func testPacking_multiSegmentRoundtrip() throws {
        let seed = [UInt8](repeating: 0x42, count: 68)
        let lit1: [UInt8] = (0..<16).map { UInt8($0) }
        let lit2: [UInt8] = (100..<132).map { UInt8($0) }
        let segs: [Seg] = [
            .literal(bytes: lit1),
            .packed(size: 2048, seed: seed),
            .literal(bytes: lit2),
            .packed(size: 512, seed: seed),
        ]
        let encoded = RVZPacking.encode(segs)
        XCTAssertEqual(try RVZPacking.decode(encoded), segs)
    }

    // MARK: - expand() gives the same bytes the PRNG would

    func testExpand_packedUsesPRNG() {
        let seed = (0..<68).map { UInt8(truncatingIfNeeded: $0 &* 5) }
        let size: UInt32 = 3000
        let segs: [Seg] = [.packed(size: size, seed: seed)]

        let expanded = RVZPacking.expand(segs)
        var prng = RVZPacking.PRNG(seed: seed)
        let reference = prng.read(Int(size))
        XCTAssertEqual(expanded, reference)
    }

    func testExpand_literalPassesThrough() {
        let literal: [UInt8] = (200..<400).map { UInt8(truncatingIfNeeded: $0) }
        let segs: [Seg] = [.literal(bytes: literal)]
        XCTAssertEqual(RVZPacking.expand(segs), literal)
    }

    // MARK: - Errors

    func testDecode_rejectsTruncatedHeader() {
        let truncated: [UInt8] = [0x00, 0x00]
        XCTAssertThrowsError(try RVZPacking.decode(truncated))
    }

    func testDecode_rejectsTruncatedLiteral() {
        // Header says 100 bytes, but we only supply 10.
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x64]
        bytes.append(contentsOf: [UInt8](repeating: 0xAA, count: 10))
        XCTAssertThrowsError(try RVZPacking.decode(bytes))
    }

    func testDecode_rejectsTruncatedSeed() {
        // Header says packed, but fewer than 68 bytes of seed follow.
        var bytes: [UInt8] = [0x80, 0x00, 0x10, 0x00]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 40))
        XCTAssertThrowsError(try RVZPacking.decode(bytes))
    }
}

// MARK: - PRNG golden vectors

/// Cross-checks against an independent implementation of the generator,
/// written from the published specification's formulation: state words kept
/// untransformed and the `>> 24 / >> 18 / >> 8 / raw` extraction applied at
/// output time.
///
/// `RVZPacking.PRNG` instead folds that extraction into the state at
/// initialization, which is what the reference decoder does — sound because
/// the transform is a mask-and-shift and so commutes with the generator's
/// XOR-only advance. These vectors are what says the two really do agree,
/// rather than that the reasoning sounded right.
extension RVZPackingTests {

    private static func seed(_ f: (Int) -> UInt8) -> [UInt8] {
        (0..<68).map(f)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testPRNGMatchesTheSpecificationsOutputForAKnownSeed() {
        var prng = RVZPacking.PRNG(seed: Self.seed { UInt8(($0 * 7 + 3) % 256) })
        XCTAssertEqual(
            hex(prng.read(32)),
            "caba85c0c54deb3eb69db66f0d4c923fae83055c3bdedb730fe39d62402a3c06"
        )
    }

    func testPRNGMatchesTheSpecificationForAnAllZeroSeed() {
        // An all-zero seed expands to an all-zero state, and the generator
        // is pure XOR — so it stays zero. Worth pinning because a decoder
        // that seeded wrongly would produce noise here.
        var prng = RVZPacking.PRNG(seed: [UInt8](repeating: 0, count: 68))
        XCTAssertEqual(prng.read(32), [UInt8](repeating: 0, count: 32))
    }

    func testPRNGMatchesTheSpecificationForAnAllOnesSeed() {
        var prng = RVZPacking.PRNG(seed: [UInt8](repeating: 0xFF, count: 68))
        XCTAssertEqual(
            hex(prng.read(32)),
            "1fc3fb32fe9cbf62f0053ce4fe9c8f43600017c7fbe04f608c19330107defc80"
        )
    }

    /// `forward` has to leave the generator exactly where reading and
    /// discarding would.
    func testForwardMatchesReadingAndDiscarding() {
        let seed = Self.seed { UInt8(($0 * 7 + 3) % 256) }
        var skipped = RVZPacking.PRNG(seed: seed)
        skipped.forward(0x1234)
        XCTAssertEqual(
            hex(skipped.read(32)),
            "5554af90ceaf1748f161854096897a6ee03c1413f94bc0405ab42d2c555bb9f8"
        )
        var read = RVZPacking.PRNG(seed: seed)
        _ = read.read(0x1234)
        var forwarded = RVZPacking.PRNG(seed: seed)
        forwarded.forward(0x1234)
        XCTAssertEqual(read.read(64), forwarded.read(64))
    }

    /// The state advances after every 521 words (2084 bytes), so a read that
    /// straddles that boundary is where an off-by-one shows up.
    func testPRNGCrossesItsCycleBoundary() {
        var prng = RVZPacking.PRNG(seed: Self.seed { UInt8(($0 * 7 + 3) % 256) })
        prng.forward(2084 - 5)
        XCTAssertEqual(hex(prng.read(16)), "76f027e1cb76b7e87bebfc2a7a0d531e")
    }

    // MARK: - Offset-aware unpacking

    /// A junk run does not start from the seed alone: the generator is first
    /// advanced by the run's offset modulo 32 KiB. Two runs with the same
    /// seed at different offsets therefore produce different bytes, which is
    /// the whole reason the offset is threaded through the decoder.
    func testUnpackPositionsTheGeneratorByTheRunsOffset() throws {
        let seed = Self.seed { UInt8($0 &+ 1) }
        let stream = RVZPacking.encode([.packed(size: 64, seed: seed)])

        let atZero = try RVZPacking.unpack(stream, expandedSize: 64, dataOffset: 0)
        let atBlock = try RVZPacking.unpack(stream, expandedSize: 64, dataOffset: 0x8000)
        let offBlock = try RVZPacking.unpack(stream, expandedSize: 64, dataOffset: 0x100)

        XCTAssertEqual(atZero, atBlock, "offsets a whole block apart are the same position")
        XCTAssertNotEqual(atZero, offBlock, "an offset inside a block must shift the stream")

        var expected = RVZPacking.PRNG(seed: seed)
        expected.forward(0x100)
        XCTAssertEqual(offBlock, expected.read(64))
    }

    func testUnpackMixesLiteralAndJunkSegmentsAndTracksTheOffset() throws {
        let seed = Self.seed { UInt8($0 &* 3 &+ 5) }
        let literal: [UInt8] = Array(repeating: 0xEE, count: 100)
        let stream = RVZPacking.encode([
            .literal(bytes: literal),
            .packed(size: 50, seed: seed),
        ])
        let unpacked = try RVZPacking.unpack(stream, expandedSize: 150, dataOffset: 0x20)
        XCTAssertEqual(Array(unpacked.prefix(100)), literal)
        // The junk run begins 100 bytes after the stream's own start.
        var expected = RVZPacking.PRNG(seed: seed)
        expected.forward(0x20 + 100)
        XCTAssertEqual(Array(unpacked.suffix(50)), expected.read(50))
    }

    /// A stream that expands to the wrong length means the group was
    /// mis-framed, and every byte after it in the chunk would be misplaced.
    func testUnpackRejectsAStreamOfTheWrongLength() {
        let stream = RVZPacking.encode([.literal(bytes: [1, 2, 3, 4])])
        XCTAssertThrowsError(try RVZPacking.unpack(stream, expandedSize: 5, dataOffset: 0))
        XCTAssertThrowsError(try RVZPacking.unpack(stream, expandedSize: 3, dataOffset: 0))
        XCTAssertNoThrow(try RVZPacking.unpack(stream, expandedSize: 4, dataOffset: 0))
    }
}
