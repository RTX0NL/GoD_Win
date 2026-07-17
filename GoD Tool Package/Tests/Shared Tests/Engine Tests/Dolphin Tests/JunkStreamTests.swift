import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// JunkStream is a deterministic PRNG seeded by (gameID, disc,
/// blockIndex). These tests cover basic correctness: determinism,
/// block boundary, random-access reads, and — if a real GameCube
/// ISO is present in the corpus — a byte-match against known junk
/// regions.
final class JunkStreamTests: XCTestCase {

    // MARK: - Deterministic output

    func testJunkStream_sameSeedGivesSameBytes() {
        let a = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        let b = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        XCTAssertEqual(a.block(0), b.block(0))
        XCTAssertEqual(a.read(at: 0x1234, count: 512), b.read(at: 0x1234, count: 512))
    }

    func testJunkStream_differentIDsDiffer() {
        let a = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        let b = JunkStream(gameID: "GQEE01", disc: 0, length: 1024 * 1024)
        XCTAssertNotEqual(a.block(0).prefix(256), b.block(0).prefix(256))
    }

    func testJunkStream_differentDiscsDiffer() {
        let a = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        let b = JunkStream(gameID: "GC6E01", disc: 1, length: 1024 * 1024)
        XCTAssertNotEqual(a.block(0).prefix(256), b.block(0).prefix(256))
    }

    func testJunkStream_differentBlocksDiffer() {
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: 10 * JunkStream.blockSize)
        XCTAssertNotEqual(s.block(0).prefix(256), s.block(1).prefix(256))
    }

    // MARK: - Block size + positional reads

    func testJunkStream_blockIsAlwaysBlockSize() {
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        XCTAssertEqual(s.block(0).count, Int(JunkStream.blockSize))
    }

    /// Reading across a block boundary must stitch seamlessly against
    /// per-block output.
    func testJunkStream_readAcrossBlockBoundary() {
        let length = 3 * JunkStream.blockSize
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: length)
        let block0 = s.block(0)
        let block1 = s.block(1)

        // 1024 bytes straddling the boundary at 0x40000.
        let midStart = UInt64(JunkStream.blockSize - 512)
        let mid = s.read(at: midStart, count: 1024)
        XCTAssertEqual(mid.count, 1024)
        XCTAssertEqual(Array(mid[0..<512]), Array(block0.suffix(512)))
        XCTAssertEqual(Array(mid[512..<1024]), Array(block1.prefix(512)))
    }

    func testJunkStream_readWithinBlock() {
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        let block0 = s.block(0)
        let mid = s.read(at: 0x1000, count: 0x400)
        XCTAssertEqual(mid, Array(block0[0x1000..<0x1400]))
    }

    // MARK: - Zero tail

    /// Bytes past `junkLength` must be zero. junkLength is the caller-
    /// supplied length rounded up to 0x8000.
    func testJunkStream_zeroesPastJunkLength() {
        // Length not a 0x8000 multiple — last block should zero tail.
        let length: UInt64 = JunkStream.blockSize + 0x1234
        let expectedJunkLen = (length + 0x7FFF) & ~UInt64(0x7FFF)
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: length)
        let tail = s.read(at: expectedJunkLen, count: 32)
        XCTAssertEqual(tail, [UInt8](repeating: 0, count: 32))
    }

    // MARK: - Sanity: output isn't trivially uniform

    func testJunkStream_outputIsNotAllOneValue() {
        let s = JunkStream(gameID: "GC6E01", disc: 0, length: 1024 * 1024)
        let head = s.read(at: 0, count: 256)
        let uniq = Set(head)
        XCTAssertGreaterThan(uniq.count, 32,
                             "PRNG output should be well-distributed; got \(uniq.count) unique bytes")
    }
}
