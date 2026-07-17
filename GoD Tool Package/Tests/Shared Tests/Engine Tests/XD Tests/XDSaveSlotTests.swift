import XCTest
@testable import XD
@testable import GoDFoundation

final class XDSaveSlotTests: XCTestCase {

    /// Build a synthetic 0x28000-byte plaintext slot. Header bytes are
    /// laid down by hand so positional asserts are unambiguous; the
    /// rest is filled with a deterministic PRNG.
    private func makeSlotBytes() -> GoDData {
        var bytes = [UInt8](repeating: 0, count: XDSaveSlot.slotSize)

        // +0x00..0x07: plaintext header (magic + reserved + counter)
        bytes[0x00] = 0x01; bytes[0x01] = 0x01; bytes[0x02] = 0x01
        bytes[0x03] = 0x00
        bytes[0x04] = 0x12; bytes[0x05] = 0x34; bytes[0x06] = 0x56; bytes[0x07] = 0x78

        // Section size at +0x20 (size table, index 1 = Trainer1) — set Trainer1 to 0x4F8.
        // Sizes are u16 BE.
        // index 0 (Config) → leave 0
        // index 1 (Trainer1) → 0x04F8
        bytes[0x20 + 1*2]     = 0x04
        bytes[0x20 + 1*2 + 1] = 0xF8
        // index 2 (PCBox) → 0x83D8
        bytes[0x20 + 2*2]     = 0x83
        bytes[0x20 + 2*2 + 1] = 0xD8

        // Offset table at +0x40, 4 bytes per entry encoded as
        //   [low_halfword, high_halfword] big-endian u16s,
        //   resulting absolute = (lo | (hi << 16)) + 0xA8.
        // Place Trainer1 at slot+0xA8 (offset 0).
        bytes[0x40 + 1*4]     = 0x00; bytes[0x40 + 1*4 + 1] = 0x00  // lo = 0
        bytes[0x40 + 1*4 + 2] = 0x00; bytes[0x40 + 1*4 + 3] = 0x00  // hi = 0
        // Place PCBox at slot+0xA8 + 0x4F8 = 0x5A0.
        bytes[0x40 + 2*4]     = 0x04; bytes[0x40 + 2*4 + 1] = 0xF8  // lo = 0x04F8
        bytes[0x40 + 2*4 + 2] = 0x00; bytes[0x40 + 2*4 + 3] = 0x00

        // Pseudo-random fill from 0x100 onward — leaves the size+offset
        // tables we just laid down intact.
        var rng: UInt32 = 0xFEEDF00D
        for i in 0x100..<XDSaveSlot.slotSize {
            rng = rng &* 1664525 &+ 1013904223
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testParseHeader() throws {
        let slot = try XDSaveSlot(raw: makeSlotBytes())
        XCTAssertEqual(slot.header.magic, XDSaveSlot.magic)
        XCTAssertEqual(slot.header.reserved, 0)
        XCTAssertEqual(slot.header.counter, 0x12345678)
    }

    func testRoundTripBytes() throws {
        let raw = makeSlotBytes()
        let slot = try XDSaveSlot(raw: raw)
        XCTAssertEqual(slot.assemble().rawBytes, raw.rawBytes)
    }

    func testTOCResolution() throws {
        let slot = try XDSaveSlot(raw: makeSlotBytes())
        XCTAssertEqual(slot.subBlockOffset(at: 1), 0xA8)
        XCTAssertEqual(slot.subBlockOffset(at: 2), 0xA8 + 0x4F8)
        XCTAssertEqual(slot.subBlockSize(at: 1), 0x04F8)
        XCTAssertEqual(slot.subBlockSize(at: 2), 0x83D8)

        let trainer = slot.subBlockBytes(.trainer1)
        XCTAssertNotNil(trainer)
        XCTAssertEqual(trainer?.length, 0x4F8)

        let pcbox = slot.subBlockBytes(.pcBox)
        XCTAssertNotNil(pcbox)
        XCTAssertEqual(pcbox?.length, 0x83D8)
    }

    func testZeroSizedSubBlockReturnsNil() throws {
        let slot = try XDSaveSlot(raw: makeSlotBytes())
        // Index 0 (Config) has size 0 in our fixture — the dump op
        // skips zero-size entries.
        XCTAssertNil(slot.subBlockBytes(at: 0))
    }

    func testRejectsWrongSize() {
        let tooShort = GoDData(length: XDSaveSlot.slotSize - 1, byteOrder: .big)
        XCTAssertThrowsError(try XDSaveSlot(raw: tooShort))
    }

    func testRejectsBadMagic() {
        var bytes = makeSlotBytes().rawBytes
        bytes[0x00] = 0xFF
        XCTAssertThrowsError(try XDSaveSlot(raw: GoDData(byteStream: bytes, byteOrder: .big)))
    }
}
