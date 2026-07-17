import XCTest
@testable import XD
@testable import GoDFoundation

/// Tests for `XDSaveSlot.repacked` — the placement-order-preserving,
/// offset-recomputing rebuild step. Covers:
///   - the 16k+8 alignment formula in isolation
///   - no-edit round-trip (recomputed offsets equal load-time offsets)
///   - section override that shifts placement of later sections
///   - size table + offset table writes match the new layout
final class XDSaveSlotRepackTests: XCTestCase {

    // MARK: - Alignment formula

    /// Verify the placement rule against the offsets observed in
    /// `01-GXXE-PokemonXD.gci`. The chain of ends and next-starts
    /// from that real save is the strongest test we have without a
    /// second fixture.
    func testNextSectionStartMatchesObservedLayout() {
        let observed: [(prevEnd: Int, expectedNext: Int)] = [
            (0x00130, 0x00148),  // Config (0xA8 + 0x88)        → Section12
            (0x01148, 0x01158),  // Section12 (0x148 + 0x1000)  → Purifier
            (0x033F0, 0x03408),  // Purifier (0x1158 + 0x2298)  → Section9
            (0x03413, 0x03428),  // Section9 (0x3408 + 0xB)     → Section10
            (0x03828, 0x03838),  // Section10 (0x3428 + 0x400)  → Section6
            (0x03B9C, 0x03BB8),  // Section6 (0x3838 + 0x364)   → StrategyMemo
            (0x0532C, 0x05348),  // StrategyMemo                → PCBox
            (0x10F98, 0x10FA8),  // PCBox                       → Section8
            (0x1165C, 0x11678),  // Section8                    → Trainer1
            (0x11FF0, 0x12008),  // Trainer1                    → Section11
            (0x12808, 0x12818),  // Section11                   → ShadowInfo
            (0x14C18, 0x14C28),  // ShadowInfo                  → Section15
            (0x21428, 0x21438),  // Section15                   → Daycare
            (0x21504, 0x21518),  // Daycare                     → Section13
            (0x23518, 0x23528),  // Section13                   → Section3
        ]
        for (prevEnd, expected) in observed {
            let actual = XDSaveSlot.nextSectionStart(after: prevEnd)
            XCTAssertEqual(
                actual, expected,
                "nextSectionStart(after: \(String(format: "0x%X", prevEnd))) → \(String(format: "0x%X", actual)) expected \(String(format: "0x%X", expected))"
            )
        }
    }

    /// The formula should always produce a result that's
    /// (a) ≥ prevEnd + 16 (minimum separator), and
    /// (b) ≡ 8 (mod 16)   (the section start lattice).
    func testNextSectionStartInvariants() {
        for prevEnd in stride(from: 0xA8, to: 0x100A8, by: 1) {
            let next = XDSaveSlot.nextSectionStart(after: prevEnd)
            XCTAssertGreaterThanOrEqual(next, prevEnd + 16, "min separator violated at \(prevEnd)")
            XCTAssertEqual(next % 16, 8, "alignment violated at \(prevEnd)")
        }
    }

    // MARK: - Repack round-trip

    /// Build a synthetic 0x28000-byte slot whose layout we know
    /// section-by-section: one Config, one PCBox, one ShadowInfo at
    /// 16k+8 offsets, with non-zero gap bytes between them.
    private func makeSlotWithKnownLayout() -> GoDData {
        var bytes = [UInt8](repeating: 0, count: XDSaveSlot.slotSize)

        // Plaintext header: magic + counter + key seed.
        bytes[0x00] = 0x01; bytes[0x01] = 0x01; bytes[0x02] = 0x01
        bytes[0x03] = 0x00
        bytes[0x04] = 0x00; bytes[0x05] = 0x00; bytes[0x06] = 0x12; bytes[0x07] = 0x34

        // Three sections at indices 0, 2, 7. We pick offsets +0xA8,
        // +0x148, +0x1158 to match the in-game alignment lattice and
        // exercise the alignment formula on round-trip.
        let layout: [(idx: Int, off: Int, len: Int, fill: UInt8)] = [
            (0, 0x00A8, 0x0088, 0xAA),  // Config-sized
            (2, 0x0148, 0x1000, 0xBB),  // Section12-sized
            (7, 0x1158, 0x2298, 0xCC),  // Purifier-sized
        ]

        // Write size table at 0x20..0x40 and offset table at 0x40..0x80.
        for entry in layout {
            let so = 0x20 + entry.idx * 2
            bytes[so]     = UInt8((entry.len >> 8) & 0xFF)
            bytes[so + 1] = UInt8(entry.len & 0xFF)

            let rel = entry.off - 0xA8
            let lo = UInt16(rel & 0xFFFF)
            let hi = UInt16((rel >> 16) & 0xFFFF)
            let oo = 0x40 + entry.idx * 4
            bytes[oo]     = UInt8((lo >> 8) & 0xFF)
            bytes[oo + 1] = UInt8(lo & 0xFF)
            bytes[oo + 2] = UInt8((hi >> 8) & 0xFF)
            bytes[oo + 3] = UInt8(hi & 0xFF)

            // Fill the section payload.
            for i in 0..<entry.len { bytes[entry.off + i] = entry.fill }
        }

        // Sprinkle non-zero gap bytes between sections so the test
        // catches anyone tightly-packing without preserving them.
        // Gap between Config end (0x130) and Section12 start (0x148):
        for i in 0x130..<0x148 { bytes[i] = 0x77 }
        // Gap between Section12 end (0x1148) and Section7 start (0x1158):
        for i in 0x1148..<0x1158 { bytes[i] = 0x88 }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testRepackNoEditsIsByteIdentical() throws {
        let slot = try XDSaveSlot(raw: makeSlotWithKnownLayout())
        let rebuilt = try slot.repacked()
        XCTAssertEqual(
            rebuilt.rawBytes, slot.raw.rawBytes,
            "repacked() with no overrides should be byte-identical to input"
        )
    }

    func testRepackPreservesPlacementOrderAfterShrink() throws {
        let slot = try XDSaveSlot(raw: makeSlotWithKnownLayout())

        // Shrink Section12 (idx 2) from 0x1000 to 0x800.
        let shrunken = GoDData(byteStream: [UInt8](repeating: 0xBB, count: 0x800), byteOrder: .big)
        let rebuilt = try slot.repacked(sectionOverrides: [2: shrunken])

        let after = try XDSaveSlot(raw: rebuilt)

        // Config (idx 0) should still be at +0xA8 (unchanged).
        XCTAssertEqual(after.subBlockOffset(at: 0), 0xA8)
        XCTAssertEqual(after.subBlockSize(at: 0), 0x88)

        // Section12 (idx 2) at the same position with new size.
        XCTAssertEqual(after.subBlockOffset(at: 2), 0x148)
        XCTAssertEqual(after.subBlockSize(at: 2), 0x800)

        // Section7 should have shifted left by (0x1000 - 0x800) = 0x800.
        // Old offset 0x1158 → new offset 0x1158 - 0x800 = 0x958.
        XCTAssertEqual(after.subBlockOffset(at: 7), 0x958)
        XCTAssertEqual(after.subBlockSize(at: 7), 0x2298)
    }

    func testRepackPreservesPlacementOrderAfterGrowth() throws {
        let slot = try XDSaveSlot(raw: makeSlotWithKnownLayout())

        // Grow Section12 from 0x1000 to 0x1200.
        let grown = GoDData(byteStream: [UInt8](repeating: 0xBB, count: 0x1200), byteOrder: .big)
        let rebuilt = try slot.repacked(sectionOverrides: [2: grown])

        let after = try XDSaveSlot(raw: rebuilt)

        // Section7 should have shifted right by 0x200 (the size delta).
        // Old 0x1158 → new 0x1358.
        XCTAssertEqual(after.subBlockOffset(at: 7), 0x1358)
        XCTAssertEqual(after.subBlockSize(at: 7), 0x2298)
    }

    func testRepackEnforcesAlignmentLattice() throws {
        let slot = try XDSaveSlot(raw: makeSlotWithKnownLayout())

        // Pick a size that isn't 16-aligned to force the formula
        // through its non-trivial branch.
        let oddSize = 0xFE5  // ends at 0x148 + 0xFE5 = 0x112D, mod 16 = 13
        let oddBytes = GoDData(byteStream: [UInt8](repeating: 0xBB, count: oddSize), byteOrder: .big)
        let rebuilt = try slot.repacked(sectionOverrides: [2: oddBytes])

        let after = try XDSaveSlot(raw: rebuilt)
        let nextStart = after.subBlockOffset(at: 7)
        XCTAssertEqual(
            nextStart % 16, 8,
            "after odd-sized override, next section must still land at 16k+8"
        )
        XCTAssertGreaterThanOrEqual(
            nextStart, 0x148 + oddSize + 16,
            "after odd-sized override, next section must respect 16-byte minimum gap"
        )
    }
}
