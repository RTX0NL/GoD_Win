import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// `DiscImageFormat.detect` is cheap pattern-matching on known magic
/// bytes. These tests hand-build minimal fixtures rather than needing
/// real ISOs on disk.
final class DiscImageFormatTests: XCTestCase {

    private func zeroBuffer(size: Int = 0x400) -> GoDData {
        let d = GoDData(byteOrder: .big)
        for _ in 0..<size { d.append(UInt8(0)) }
        return d
    }

    // MARK: - Raw ISO

    func testDetect_gamecubeISO() {
        let b = zeroBuffer()
        // GC magic at 0x1C: 0xC2339F3D
        _ = b.write(UInt32(0xC233_9F3D), atAddress: 0x1C)
        XCTAssertEqual(DiscImageFormat.detect(in: b), .gamecubeISO)
    }

    func testDetect_wiiISO() {
        let b = zeroBuffer()
        _ = b.write(UInt32(0x5D1C_9EA3), atAddress: 0x18)
        XCTAssertEqual(DiscImageFormat.detect(in: b), .wiiISO)
    }

    // MARK: - CISO

    func testDetect_cisoWiiGC() {
        let b = zeroBuffer()
        for (i, by) in [UInt8(0x43), UInt8(0x49), UInt8(0x53), UInt8(0x4F)].enumerated() {
            _ = b.write(by, atAddress: i)
        }
        // block size = 0x00200000 little-endian = [0x00, 0x00, 0x20, 0x00]
        _ = b.write(UInt8(0x00), atAddress: 4)
        _ = b.write(UInt8(0x00), atAddress: 5)
        _ = b.write(UInt8(0x20), atAddress: 6)
        _ = b.write(UInt8(0x00), atAddress: 7)
        XCTAssertEqual(DiscImageFormat.detect(in: b), .ciso)
    }

    /// PSP CSO shares the `"CISO"` magic but uses a 2 KiB block size.
    /// Detector rejects it (returns .unknown).
    func testDetect_pspCSONotAccepted() {
        let b = zeroBuffer()
        for (i, by) in [UInt8(0x43), UInt8(0x49), UInt8(0x53), UInt8(0x4F)].enumerated() {
            _ = b.write(by, atAddress: i)
        }
        // PSP block size = 0x00000800 little-endian
        _ = b.write(UInt8(0x00), atAddress: 4)
        _ = b.write(UInt8(0x08), atAddress: 5)
        _ = b.write(UInt8(0x00), atAddress: 6)
        _ = b.write(UInt8(0x00), atAddress: 7)
        XCTAssertEqual(DiscImageFormat.detect(in: b), .unknown)
    }

    // MARK: - WBFS

    func testDetect_wbfs() {
        let b = zeroBuffer()
        for (i, by) in WBFSFile.magic.enumerated() {
            _ = b.write(by, atAddress: i)
        }
        _ = b.write(UInt8(9), atAddress: 8)    // 512-byte hd sectors
        _ = b.write(UInt8(21), atAddress: 9)   // 2 MiB blocks
        XCTAssertEqual(DiscImageFormat.detect(in: b), .wbfs)
    }

    func testDetect_wbfsMagicWithImpossibleGeometryIsUnknown() {
        let b = zeroBuffer()
        for (i, by) in WBFSFile.magic.enumerated() {
            _ = b.write(by, atAddress: i)
        }
        // Shifts left at zero: not a geometry libwbfs writes.
        XCTAssertEqual(DiscImageFormat.detect(in: b), .unknown)
    }

    // MARK: - WIA / RVZ

    func testDetect_wiaOrRVZ() {
        let b = zeroBuffer()
        // "WIA\x01"
        for (i, by) in [UInt8(0x57), UInt8(0x49), UInt8(0x41), UInt8(0x01)].enumerated() {
            _ = b.write(by, atAddress: i)
        }
        XCTAssertEqual(DiscImageFormat.detect(in: b), .wiaOrRVZ)
    }

    // MARK: - NKit

    func testDetect_nkitGC() {
        let b = zeroBuffer()
        // GC disc magic preserved in NKit, plus NKit magic at 0x200.
        _ = b.write(UInt32(0xC233_9F3D), atAddress: 0x1C)
        for (i, by) in NKitHeader.magic.enumerated() {
            _ = b.write(by, atAddress: 0x200 + i)
        }
        XCTAssertEqual(DiscImageFormat.detect(in: b), .nkitGC)
    }

    func testDetect_nkitWii() {
        let b = zeroBuffer()
        _ = b.write(UInt32(0x5D1C_9EA3), atAddress: 0x18)
        for (i, by) in NKitHeader.magic.enumerated() {
            _ = b.write(by, atAddress: 0x200 + i)
        }
        XCTAssertEqual(DiscImageFormat.detect(in: b), .nkitWii)
    }

    // MARK: - Unknown

    func testDetect_unknownOnEmpty() {
        XCTAssertEqual(DiscImageFormat.detect(in: zeroBuffer()), .unknown)
    }

    func testDetect_unknownOnShortInput() {
        let short = GoDData(byteOrder: .big)
        for _ in 0..<0x100 { short.append(UInt8(0)) }  // less than 0x400
        XCTAssertEqual(DiscImageFormat.detect(in: short), .unknown)
    }

    // MARK: - Metadata

    func testRequiresDecoding() {
        XCTAssertFalse(DiscImageFormat.gamecubeISO.requiresDecoding)
        XCTAssertFalse(DiscImageFormat.wiiISO.requiresDecoding)
        XCTAssertTrue(DiscImageFormat.ciso.requiresDecoding)
        XCTAssertTrue(DiscImageFormat.wbfs.requiresDecoding)
        XCTAssertTrue(DiscImageFormat.wiaOrRVZ.requiresDecoding)
        XCTAssertTrue(DiscImageFormat.nkitGC.requiresDecoding)
        XCTAssertTrue(DiscImageFormat.nkitWii.requiresDecoding)
    }

    // MARK: - Against a real ISO (if present)

    func testDetect_realColoISO() throws {
        let path = ProcessInfo.processInfo.environment["GODDESS_COLO_ISO"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US.iso"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("Colo US.iso not available")
        }
        // Only need the head of the file to detect.
        let head = [UInt8](raw.prefix(0x400))
        let data = GoDData(byteStream: head, byteOrder: .big)
        XCTAssertEqual(DiscImageFormat.detect(in: data), .gamecubeISO)
    }
}
