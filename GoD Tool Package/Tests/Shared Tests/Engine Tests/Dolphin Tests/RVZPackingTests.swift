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
