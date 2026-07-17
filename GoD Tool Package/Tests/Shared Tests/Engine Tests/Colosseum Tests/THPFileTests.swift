//
//  THPFileTests.swift
//
//  Bit-identical roundtrip tests for the paired THH + THD format. No
//  real frame decoder is involved — we synthesise a minimal THH that
//  only exercises the parts the split/join path actually reads (the
//  0x28 and 0x2C frame-offset fields) plus some dummy THD bytes.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GeniusSonority

final class THPFileTests: XCTestCase {

    /// Synthesise a THH with the two frame-offset fields pre-populated
    /// and the rest of the base header zeroed. The actual THP format
    /// has more fields, but only 0x28/0x2C matter for the join/split
    /// path.
    private func makeTHH(
        size: Int = 0x40,
        firstFrameOffsetInTHD: UInt32 = 0,
        lastFrameOffsetInTHD: UInt32 = 0
    ) -> GoDData {
        precondition(size >= 0x30, "THH must fit the 0x28 + 0x2C fields")
        let d = GoDData(length: size, byteOrder: .big)
        // Magic "THP\0" at 0x00 (informational; the split/join path
        // doesn't check it, but a realistic header helps human
        // inspection of failures).
        _ = d.write(UInt8(0x54), atAddress: 0x00)
        _ = d.write(UInt8(0x48), atAddress: 0x01)
        _ = d.write(UInt8(0x50), atAddress: 0x02)
        _ = d.write(UInt8(0x00), atAddress: 0x03)
        _ = d.write(firstFrameOffsetInTHD, atAddress: 0x28)
        _ = d.write(lastFrameOffsetInTHD, atAddress: 0x2C)
        return d
    }

    private func makeTHD(byteCount: Int) -> GoDData {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for i in 0..<byteCount {
            bytes.append(UInt8(i & 0xFF))
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Concat + fixup

    func testConcat_appliesPointerFixupToCombinedThp() throws {
        let thh = makeTHH(size: 0x80)
        let thd = makeTHD(byteCount: 0x200)
        let thp = try THPFile(thh: thh, thd: thd, name: "sample")

        XCTAssertEqual(thp.thhSize, 0x80)
        XCTAssertEqual(thp.combined.length, 0x80 + 0x200)

        // Combined[0x28] should now hold `thhSize` (the original split
        // value was 0).
        let firstFrameOffset: UInt32 = thp.combined.readSafely(atAddress: 0x28)
        let lastFrameOffset: UInt32 = thp.combined.readSafely(atAddress: 0x2C)
        XCTAssertEqual(firstFrameOffset, UInt32(thp.thhSize))
        XCTAssertEqual(lastFrameOffset, UInt32(thp.thhSize))
    }

    func testConcat_preservesRemainingTHHBytes() throws {
        // Stamp a recognisable byte outside the fixup fields and
        // verify it survives the concat.
        let thh = makeTHH(size: 0x40)
        _ = thh.write(UInt8(0xAB), atAddress: 0x10)
        let thd = makeTHD(byteCount: 32)
        let thp = try THPFile(thh: thh, thd: thd, name: "sample")
        XCTAssertEqual(thp.combined.rawBytes[0x10], 0xAB)
        // And the THD bytes live at thhSize..
        XCTAssertEqual(thp.combined.rawBytes[thp.thhSize], 0x00)
        XCTAssertEqual(thp.combined.rawBytes[thp.thhSize + 1], 0x01)
    }

    // MARK: - Split reverses concat

    func testSplitCombined_reproducesOriginalTHHAndTHD() throws {
        let originalTHH = makeTHH(size: 0x50)
        _ = originalTHH.write(UInt8(0x42), atAddress: 0x08)
        _ = originalTHH.write(UInt8(0x99), atAddress: 0x20)
        let originalTHD = makeTHD(byteCount: 512)

        let thp = try THPFile(thh: originalTHH, thd: originalTHD, name: "round")
        let (rebuiltTHH, rebuiltTHD) = try thp.splitCombined()

        XCTAssertEqual(rebuiltTHH.rawBytes, originalTHH.rawBytes,
                       "THH not byte-identical after split")
        XCTAssertEqual(rebuiltTHD.rawBytes, originalTHD.rawBytes,
                       "THD not byte-identical after split")
    }

    func testInitBinaries_pairRecoversSameCombinedBytes() throws {
        let thh = makeTHH(size: 0x40)
        let thd = makeTHD(byteCount: 256)
        let thp1 = try THPFile(thh: thh, thd: thd, name: "track")

        let binaries = try thp1.binaries
        let thp2 = try THPFile(binaries: binaries)
        XCTAssertEqual(thp2.combined.rawBytes, thp1.combined.rawBytes)
        XCTAssertEqual(thp2.thhSize, thp1.thhSize)
    }

    // MARK: - Outputs (single .thp, no sidecar)

    func testOutputs_emitSingleCombinedThp() throws {
        let thh = makeTHH(size: 0x40)
        let thd = makeTHD(byteCount: 128)
        var thp = try THPFile(thh: thh, thd: thd, name: "video")
        thp.name = "video"

        let artifacts = try thp.outputs
        XCTAssertEqual(artifacts.count, 1, "THP outputs are a single self-describing .thp — no JSON sidecar")
        XCTAssertEqual(artifacts[0].file, File("video.thp"))
        XCTAssertEqual(artifacts[0].data.rawBytes, thp.combined.rawBytes)

        let rebuilt = try THPFile(outputs: artifacts)
        XCTAssertEqual(rebuilt.combined.rawBytes, thp.combined.rawBytes)
        XCTAssertEqual(rebuilt.thhSize, thp.thhSize)
    }

    func testFullRoundTripThroughOutputs() throws {
        // THH + THD → combined .thp → parse .thp → split back to
        // THH + THD. Byte-identical at both ends.
        let originalTHH = makeTHH(size: 0x60)
        _ = originalTHH.write(UInt8(0xDE), atAddress: 0x05)
        _ = originalTHH.write(UInt8(0xAD), atAddress: 0x06)
        let originalTHD = makeTHD(byteCount: 800)
        let source = try THPFile(thh: originalTHH, thd: originalTHD, name: "cutscene")

        let artifacts = try source.outputs
        let rebuilt = try THPFile(outputs: artifacts)
        let (rebuiltTHH, rebuiltTHD) = try rebuilt.splitCombined()

        XCTAssertEqual(rebuiltTHH.rawBytes, originalTHH.rawBytes)
        XCTAssertEqual(rebuiltTHD.rawBytes, originalTHD.rawBytes)
    }
}
