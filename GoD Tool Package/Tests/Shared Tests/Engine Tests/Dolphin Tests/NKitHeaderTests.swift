import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// Roundtrip the NKit header struct through its on-disc byte layout
/// (magic + scalars at offsets 0x200-0x21B).
final class NKitHeaderTests: XCTestCase {

    private func zeroBlock(size: Int = 0x400) -> GoDData {
        let d = GoDData(byteOrder: .big)
        for _ in 0..<size { d.append(UInt8(0)) }
        return d
    }

    // MARK: - GameCube

    func testNKitHeader_gcRoundtrip() throws {
        let original = NKitHeader(
            platform: .gamecube,
            originalCRC: 0xDEAD_BEEF,
            crcForce: 0x1234_5678,
            originalImageSize: 1_459_978_240,
            junkOverrideID: "GC6E",
            updatePartitionCRC: nil
        )
        let buf = zeroBlock()
        original.write(into: buf)
        let parsed = try NKitHeader(binary: buf, platform: .gamecube)
        XCTAssertEqual(parsed, original)
    }

    func testNKitHeader_gcNoJunkOverride() throws {
        let original = NKitHeader(
            platform: .gamecube,
            originalCRC: 0x1111_1111,
            crcForce: 0x2222_2222,
            originalImageSize: 1_459_978_240,
            junkOverrideID: nil
        )
        let buf = zeroBlock()
        original.write(into: buf)
        let parsed = try NKitHeader(binary: buf, platform: .gamecube)
        XCTAssertEqual(parsed, original)
        XCTAssertNil(parsed.junkOverrideID)
    }

    // MARK: - Wii

    func testNKitHeader_wiiRoundtrip() throws {
        let original = NKitHeader(
            platform: .wii,
            originalCRC: 0xAAAA_AAAA,
            crcForce: 0xBBBB_BBBB,
            originalImageSize: 4_699_979_776,   // Wii single-layer
            junkOverrideID: nil,
            updatePartitionCRC: 0xCCCC_CCCC
        )
        let buf = zeroBlock()
        original.write(into: buf)
        let parsed = try NKitHeader(binary: buf, platform: .wii)
        XCTAssertEqual(parsed, original)
    }

    func testNKitHeader_wiiNoUpdateRemoval() throws {
        let original = NKitHeader(
            platform: .wii,
            originalCRC: 0,
            crcForce: 0,
            originalImageSize: 4_699_979_776,
            updatePartitionCRC: nil
        )
        let buf = zeroBlock()
        original.write(into: buf)
        let parsed = try NKitHeader(binary: buf, platform: .wii)
        XCTAssertEqual(parsed, original)
        XCTAssertNil(parsed.updatePartitionCRC)
    }

    /// For Wii, offset 0x210 stores originalImageSize/4 — confirm the
    /// on-disc bytes reflect that division, and parse un-divides.
    func testNKitHeader_wiiImageSizeIsDividedByFour() throws {
        let size: UInt64 = 4_699_979_776
        let original = NKitHeader(platform: .wii, originalImageSize: size)
        let buf = zeroBlock()
        original.write(into: buf)

        // Read raw UInt32 at 0x210 directly.
        buf.setByteOrder(.big)
        let stored: UInt32 = buf.readSafely(atAddress: 0x210)
        XCTAssertEqual(UInt64(stored), size / 4)

        let parsed = try NKitHeader(binary: buf, platform: .wii)
        XCTAssertEqual(parsed.originalImageSize, size)
    }

    // MARK: - Error handling

    func testNKitHeader_rejectsBadMagic() {
        let buf = zeroBlock()
        // Leave magic as zeros (bad).
        XCTAssertThrowsError(try NKitHeader(binary: buf, platform: .gamecube))
    }
}
