import XCTest
import Foundation
import GoDFoundation
import Dolphin

final class NKitChecksumTests: XCTestCase {

    // MARK: - CRC32 reference vectors

    func testCRC32_standardVector() {
        let bytes: [UInt8] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        XCTAssertEqual(CRC32.compute(bytes), 0xCBF43926)
    }

    func testCRC32_empty() {
        XCTAssertEqual(CRC32.compute([]), 0)
    }

    func testCRC32_incrementalMatchesOneShot() {
        let bytes: [UInt8] = Array(0..<200).map { UInt8(truncatingIfNeeded: $0) }
        let oneShot = CRC32.compute(bytes)
        var crc: UInt32 = 0xFFFF_FFFF
        crc = CRC32.update(crc, bytes: Array(bytes[0..<50]))
        crc = CRC32.update(crc, bytes: Array(bytes[50..<120]))
        crc = CRC32.update(crc, bytes: Array(bytes[120..<200]))
        XCTAssertEqual(crc ^ 0xFFFF_FFFF, oneShot)
    }

    // MARK: - CRC force
    //
    // Usage contract: caller zeroes the slot, computes the current CRC
    // of that buffer, then calls `calculate`. The returned value
    // written big-endian at the slot makes the whole-file CRC match
    // the target.

    private func applyForce(_ force: UInt32, to buffer: inout [UInt8], at slot: Int) {
        buffer[slot]     = UInt8(truncatingIfNeeded: force >> 24)
        buffer[slot + 1] = UInt8(truncatingIfNeeded: force >> 16)
        buffer[slot + 2] = UInt8(truncatingIfNeeded: force >> 8)
        buffer[slot + 3] = UInt8(truncatingIfNeeded: force)
    }

    func testCRCForce_hitsTargetMidBuffer() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        for i in 0..<buffer.count { buffer[i] = UInt8(truncatingIfNeeded: i &* 3) }
        let target: UInt32 = 0xDEAD_BEEF
        let slot = 256
        // Zero the slot first, then measure CRC.
        for i in 0..<4 { buffer[slot + i] = 0 }
        let current = CRC32.compute(buffer)
        let force = CRCForce.calculate(currentCRC: current, length: UInt64(buffer.count), newCRC: target, offset: UInt64(slot))
        applyForce(force, to: &buffer, at: slot)
        XCTAssertEqual(CRC32.compute(buffer), target)
    }

    func testCRCForce_hitsTargetNearStart() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        for i in 0..<buffer.count { buffer[i] = UInt8(truncatingIfNeeded: i &* 7) }
        let target: UInt32 = 0xCAFE_BABE
        let slot = 4
        for i in 0..<4 { buffer[slot + i] = 0 }
        let current = CRC32.compute(buffer)
        let force = CRCForce.calculate(currentCRC: current, length: UInt64(buffer.count), newCRC: target, offset: UInt64(slot))
        applyForce(force, to: &buffer, at: slot)
        XCTAssertEqual(CRC32.compute(buffer), target)
    }

    func testCRCForce_hitsTargetNearEnd() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        for i in 0..<buffer.count { buffer[i] = UInt8(truncatingIfNeeded: i &* 11) }
        let target: UInt32 = 0x1234_5678
        let slot = buffer.count - 4
        for i in 0..<4 { buffer[slot + i] = 0 }
        let current = CRC32.compute(buffer)
        let force = CRCForce.calculate(currentCRC: current, length: UInt64(buffer.count), newCRC: target, offset: UInt64(slot))
        applyForce(force, to: &buffer, at: slot)
        XCTAssertEqual(CRC32.compute(buffer), target)
    }

    func testCRCForce_preservesOriginalCRC() {
        // Trash then restore — original CRC should be recoverable.
        var buffer = Array(0..<1024).map { UInt8(truncatingIfNeeded: $0 * 17) }
        let originalCRC = CRC32.compute(buffer)
        let slot = 512
        for i in 0..<4 { buffer[slot + i] = 0 }
        let current = CRC32.compute(buffer)
        let force = CRCForce.calculate(currentCRC: current, length: UInt64(buffer.count), newCRC: originalCRC, offset: UInt64(slot))
        applyForce(force, to: &buffer, at: slot)
        XCTAssertEqual(CRC32.compute(buffer), originalCRC)
    }
}
