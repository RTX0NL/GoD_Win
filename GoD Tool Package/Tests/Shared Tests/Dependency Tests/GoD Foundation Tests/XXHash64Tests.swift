//
//  XXHash64Tests.swift
//
//  XXH64 exists here for one caller: a Zstandard frame's optional content
//  checksum is the low 32 bits of the XXH64 of its content, and a decoder
//  that skipped it would report success on a stream it had mis-decoded.
//
//  What pins the values against the reference implementation is
//  `ZstdDecoderTests.testDecodesReferenceStreamsWithChecksumsAtEveryLength`:
//  those fixtures carry checksums the real `zstd` computed, over payloads
//  chosen to hit every length branch of the algorithm. Hard-coding "known"
//  constants here instead would only pin them against whatever this file
//  claimed they were.
//
//  So this file covers the invariants that cross-check can't see: that the
//  array and slice entry points agree, and that a slice is hashed as its own
//  bytes rather than from the start of its base array — the decoder hands in
//  `output[frameStart...]`, so a zero-based assumption would verify the
//  wrong range and still pass on a single-frame stream.
//
//  Reference: Cyan4973/xxHash `doc/xxhash_spec.md`
//

import XCTest
import GoDFoundation

final class XXHash64Tests: XCTestCase {

    /// A fixed byte sequence, long enough to run the four-accumulator stripe
    /// loop and leave an 8/4/1-byte tail.
    private let bytes: [UInt8] = (0..<301).map { UInt8(($0 * 37 + 11) % 251) }

    /// The array and slice entry points must agree at every length branch:
    /// under 32 bytes skips the stripe loop, and the tail handles 8-, 4- and
    /// 1-byte remainders in turn.
    func testArrayAndSliceAgreeAtEveryLengthBranch() {
        for length in [0, 1, 3, 4, 7, 8, 9, 15, 16, 31, 32, 33, 39, 40, 63, 64, 100, 128, 301] {
            let prefix = Array(bytes[0..<length])
            XCTAssertEqual(
                XXHash64.hash(prefix),
                XXHash64.hash(bytes[0..<length]),
                "array and slice disagree at length \(length)"
            )
        }
    }

    /// A slice starting past zero hashes as its own bytes.
    func testSliceOffsetIsRespected() {
        for (lower, upper) in [(1, 9), (7, 40), (57, 149), (200, 301), (300, 301)] {
            let slice = bytes[lower..<upper]
            XCTAssertEqual(
                XXHash64.hash(slice),
                XXHash64.hash(Array(slice)),
                "slice \(lower)..<\(upper) hashed from the wrong offset"
            )
        }
    }

    func testEmptyInputIsStable() {
        XCTAssertEqual(XXHash64.hash([]), XXHash64.hash(bytes[0..<0]))
        XCTAssertEqual(XXHash64.hash([]), XXHash64.hash(bytes[150..<150]))
    }

    func testSeedChangesTheResult() {
        XCTAssertNotEqual(XXHash64.hash(bytes, seed: 0), XXHash64.hash(bytes, seed: 1))
        XCTAssertNotEqual(XXHash64.hash([], seed: 0), XXHash64.hash([], seed: 1))
    }

    /// Distinct inputs of the same length must not collide on these small
    /// cases — a mixing step left out entirely would show up here.
    func testDistinctInputsDiffer() {
        var seen = Set<UInt64>()
        for i in 0..<64 {
            var variant = bytes
            variant[i] ^= 0x80
            seen.insert(XXHash64.hash(variant))
        }
        XCTAssertEqual(seen.count, 64)
    }
}
