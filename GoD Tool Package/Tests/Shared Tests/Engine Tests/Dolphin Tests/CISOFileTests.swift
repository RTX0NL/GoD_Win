import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// CISO is a trivial format; these tests verify header parse/serialize
/// roundtrip and end-to-end ISO ↔ CISO roundtrip on synthetic data.
final class CISOFileTests: XCTestCase {

    // MARK: - Header roundtrip

    func testCISO_headerSerializeParseRoundtrip() throws {
        var map = [Bool](repeating: false, count: 8)
        map[0] = true
        map[3] = true
        map[7] = true
        let original = CISOFile(blockSize: 0x0020_0000, blockMap: map, discSize: 8 * 0x0020_0000)

        // Serialize and re-parse. Need to append some dummy body bytes
        // so the parser has a file to look at (parse only reads the
        // header, not body).
        let bytes = original.headerBytes
        let parsed = try CISOFile(binary: bytes, discSize: original.discSize)

        XCTAssertEqual(parsed.blockSize, original.blockSize)
        XCTAssertEqual(parsed.discSize, original.discSize)
        XCTAssertEqual(parsed.blockMap, original.blockMap)
    }

    func testCISO_parseRejectsBadMagic() {
        let bytes = GoDData(byteOrder: .little)
        bytes.append(UInt8(0x42))  // 'B' instead of 'C'
        bytes.append(UInt8(0x49))
        bytes.append(UInt8(0x53))
        bytes.append(UInt8(0x4F))
        bytes.append(CISOFile.defaultBlockSize)
        for _ in 0..<CISOFile.blockMapSize { bytes.append(UInt8(0)) }
        XCTAssertThrowsError(try CISOFile(binary: bytes))
    }

    func testCISO_parseRejectsTinyBlockSize() {
        let bytes = GoDData(byteOrder: .little)
        for b in CISOFile.magic { bytes.append(b) }
        bytes.append(UInt32(0x800))  // PSP CSO block size — not supported here
        for _ in 0..<CISOFile.blockMapSize { bytes.append(UInt8(0)) }
        XCTAssertThrowsError(try CISOFile(binary: bytes))
    }

    // MARK: - Block offset math

    func testCISO_fileOffsetOfPresentBlock() {
        var map = [Bool](repeating: false, count: 5)
        map[0] = true   // present at body[0]
        map[2] = true   // present at body[1]
        map[4] = true   // present at body[2]
        let ciso = CISOFile(blockSize: 0x0020_0000, blockMap: map, discSize: 0)
        XCTAssertEqual(ciso.fileOffset(ofBlock: 0), UInt64(CISOFile.headerSize))
        XCTAssertEqual(ciso.fileOffset(ofBlock: 1), nil)
        XCTAssertEqual(ciso.fileOffset(ofBlock: 2),
                       UInt64(CISOFile.headerSize) + UInt64(CISOFile.defaultBlockSize))
        XCTAssertEqual(ciso.fileOffset(ofBlock: 3), nil)
        XCTAssertEqual(ciso.fileOffset(ofBlock: 4),
                       UInt64(CISOFile.headerSize) + UInt64(CISOFile.defaultBlockSize) * 2)
    }

    // MARK: - End-to-end ISO ↔ CISO

    /// Build a synthetic "ISO": mix of zero blocks and non-zero blocks.
    /// Small block size (smaller than 2 MiB) to keep the test cheap;
    /// we feed the non-default size explicitly.
    private static func syntheticISO(pattern: [Bool], blockSize: Int) -> GoDData {
        let out = GoDData(byteOrder: .big)
        for (i, present) in pattern.enumerated() {
            if present {
                // Non-zero pattern, keyed by block index so each block
                // is distinguishable.
                for b in 0..<blockSize {
                    out.append(UInt8(truncatingIfNeeded: i * 13 + b))
                }
            } else {
                for _ in 0..<blockSize {
                    out.append(UInt8(0))
                }
            }
        }
        return out
    }

    func testCISO_roundtripMixedBlocks() throws {
        // Default block size = 2 MiB is too big for unit-test perf;
        // use 32 KiB (the spec's minimum) to keep it fast.
        let blockSize: UInt32 = 0x8000
        let pattern = [true, false, true, true, false, false, true]
        let iso = Self.syntheticISO(pattern: pattern, blockSize: Int(blockSize))

        let ciso = CISOConverter.build(iso: iso, blockSize: blockSize)
        let restored = try CISOConverter.dump(ciso: ciso, targetDiscSize: UInt64(iso.length))

        XCTAssertEqual(restored.length, iso.length)
        XCTAssertEqual(restored.rawBytes, iso.rawBytes)
    }

    func testCISO_roundtripAllZeroISO() throws {
        let blockSize: UInt32 = 0x8000
        let iso = Self.syntheticISO(pattern: [false, false, false], blockSize: Int(blockSize))
        let ciso = CISOConverter.build(iso: iso, blockSize: blockSize)

        // Body should be empty — all blocks omitted.
        XCTAssertEqual(ciso.length, CISOFile.headerSize, "no body bytes for all-zero ISO")

        let restored = try CISOConverter.dump(ciso: ciso, targetDiscSize: UInt64(iso.length))
        XCTAssertEqual(restored.rawBytes, iso.rawBytes)
    }

    func testCISO_roundtripAllNonZeroISO() throws {
        let blockSize: UInt32 = 0x8000
        let iso = Self.syntheticISO(pattern: [true, true, true], blockSize: Int(blockSize))
        let ciso = CISOConverter.build(iso: iso, blockSize: blockSize)

        // Body holds every block verbatim → totalFileSize matches.
        XCTAssertEqual(ciso.length, CISOFile.headerSize + 3 * Int(blockSize))

        let restored = try CISOConverter.dump(ciso: ciso, targetDiscSize: UInt64(iso.length))
        XCTAssertEqual(restored.rawBytes, iso.rawBytes)
    }
}
