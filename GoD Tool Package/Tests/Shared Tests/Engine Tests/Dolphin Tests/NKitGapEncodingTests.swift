import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// `decode(encode(gap)) == gap` for every gap variant. Separately,
/// `expand(gap, junk)` regenerates the expected byte stream.
final class NKitGapEncodingTests: XCTestCase {
    typealias G = NKitGapEncoding.Gap
    typealias B = NKitGapEncoding.MixedBlock

    private func roundtrip(_ gap: G, file: StaticString = #file, line: UInt = #line) throws {
        let encoded = NKitGapEncoding.encode(gap)
        let (decoded, _) = try NKitGapEncoding.decode(from: encoded, cursor: 0)
        XCTAssertEqual(decoded, gap, file: file, line: line)
    }

    // MARK: - Simple gap types

    func testGap_allJunk() throws {
        try roundtrip(.allJunk(length: 0))
        try roundtrip(.allJunk(length: 0x1000))
        try roundtrip(.allJunk(length: 0x1FF_FFFFC))  // fits in 30 bits
    }

    func testGap_allScrubbed() throws {
        try roundtrip(.allScrubbed(length: 0))
        try roundtrip(.allScrubbed(length: 0x800))
    }

    func testGap_junkFile() throws {
        try roundtrip(.junkFile(length: 0x4000, streamOffset: 0x8000_0000))
        try roundtrip(.junkFile(length: 0x200, streamOffset: 0xDEAD_BEEF_CAFE_BABE))
    }

    // MARK: - Mixed blocks

    func testMixed_singleJunkBlock() throws {
        try roundtrip(.mixed(length: 0x200, blocks: [.junk(count: 2)]))
    }

    func testMixed_nonJunk() throws {
        let bytes = (0..<0x200).map { UInt8(truncatingIfNeeded: $0) }
        try roundtrip(.mixed(length: 0x200, blocks: [.nonJunk(bytes: bytes)]))
    }

    func testMixed_byteFill() throws {
        try roundtrip(.mixed(length: 0x300, blocks: [.byteFill(byte: 0xFF, count: 3)]))
    }

    func testMixed_repeat() throws {
        let bytes = [UInt8](repeating: 0xAB, count: 0x100)
        try roundtrip(.mixed(length: 0x300, blocks: [
            .nonJunk(bytes: bytes),
            .repeatPrevious(count: 2)
        ]))
    }

    func testMixed_combination() throws {
        let bytes = (0..<0x200).map { UInt8(truncatingIfNeeded: $0) }
        // Totals: 0x400 (junk) + 0x200 (nonJunk) + 0x400 (byteFill) +
        //         0x200 (1 × 0x200 repeat of NonJunk) = 0xC00.
        try roundtrip(.mixed(length: 0xC00, blocks: [
            .junk(count: 4),
            .nonJunk(bytes: bytes),
            .byteFill(byte: 0x42, count: 4),
            .repeatPrevious(count: 1),
        ]))
    }

    // MARK: - Length continuation

    func testGap_longJunkSplitsHeader() throws {
        // Requires two continuation headers: 0xFFFFFFFC + 0xFFFFFFFC + remainder.
        let bigLength: UInt64 = 0x1_FFFF_FFFC + 0x4
        try roundtrip(.allJunk(length: bigLength))
    }

    // MARK: - Expand against a real JunkStream

    func testExpand_allJunkMatchesStream() {
        let junk = JunkStream(gameID: "GC6E01", disc: 0, length: 4 * JunkStream.blockSize)
        let gap = G.allJunk(length: 0x1000)
        let expanded = NKitGapEncoding.expand(gap, junk: junk, junkOffset: 0x2000)
        let direct = junk.read(at: 0x2000, count: 0x1000)
        XCTAssertEqual(expanded, direct)
    }

    func testExpand_allScrubbedIsZeros() {
        let junk = JunkStream(gameID: "GC6E01", disc: 0, length: 0x1000)
        let gap = G.allScrubbed(length: 0x800)
        XCTAssertEqual(NKitGapEncoding.expand(gap, junk: junk, junkOffset: 0),
                       [UInt8](repeating: 0, count: 0x800))
    }

    func testExpand_mixedCombinesSources() {
        let junk = JunkStream(gameID: "GC6E01", disc: 0, length: 0x10000)
        let literal = (0..<0x100).map { UInt8(truncatingIfNeeded: $0 + 1) }
        let gap = G.mixed(length: 0x300, blocks: [
            .junk(count: 1),
            .nonJunk(bytes: literal),
            .byteFill(byte: 0xEE, count: 1),
        ])
        let expanded = NKitGapEncoding.expand(gap, junk: junk, junkOffset: 0)
        XCTAssertEqual(expanded.count, 0x300)
        XCTAssertEqual(Array(expanded[0..<0x100]), junk.read(at: 0, count: 0x100))
        XCTAssertEqual(Array(expanded[0x100..<0x200]), literal)
        XCTAssertEqual(Array(expanded[0x200..<0x300]), [UInt8](repeating: 0xEE, count: 0x100))
    }
}
