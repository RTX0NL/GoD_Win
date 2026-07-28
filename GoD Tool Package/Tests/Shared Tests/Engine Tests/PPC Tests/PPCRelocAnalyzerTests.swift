//
//  PPCRelocAnalyzerTests.swift
//
//  Covers the lis-tracking model: multi-consumer high halves, unsigned
//  (ori) pairs, psq/lmw consumers, and register-kill rules.
//

import XCTest
@testable import Dolphin
@testable import GoDFoundation

final class PPCRelocAnalyzerTests: XCTestCase {

    let decoder = PPCDecoder()
    let analyzer = PPCRelocAnalyzer()

    /// One data section wide enough for every target used below.
    let sectionRanges: [(start: UInt32, end: UInt32)] = [(start: 0x80400000, end: 0x80430000)]

    private func analyze(_ words: [UInt32], base: UInt32 = 0x80003100) -> [UInt32: PPCRelocation] {
        var bytes = [UInt8]()
        for word in words {
            bytes.append(contentsOf: [UInt8(word >> 24 & 0xFF), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)])
        }
        let instructions = decoder.decodeAll(bytes, baseAddress: base)
        return analyzer.analyze(instructions, symbols: [:], sectionRanges: sectionRanges)
    }

    func testSingleConsumerPair() {
        // lis r4, 0x8042; lwz r3, -0x1234(r4)
        let relocs = analyze([0x3C80_8042, 0x8064_EDCC])
        XCTAssertEqual(relocs[0x80003100]?.halfType, .ha)
        XCTAssertEqual(relocs[0x80003100]?.targetAddress, 0x8041_EDCC)
        XCTAssertEqual(relocs[0x80003104]?.halfType, .lo)
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8041_EDCC)
    }

    func testMultiConsumerLisRelocatesAllConsumers() {
        // lis r4, 0x8042
        // lwz r3, -0x1234(r4)   → 0x8041EDCC
        // lwz r5, 0x100(r4)     → 0x80420100  (previously left raw)
        let relocs = analyze([0x3C80_8042, 0x8064_EDCC, 0x80A4_0100])
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8041_EDCC)
        XCTAssertEqual(relocs[0x80003108]?.targetAddress, 0x8042_0100,
                       "second consumer of the same lis must get its own lo relocation")
        XCTAssertEqual(relocs[0x80003108]?.halfType, .lo)
        // The lis keeps the first consumer's target
        XCTAssertEqual(relocs[0x80003100]?.targetAddress, 0x8041_EDCC)
    }

    func testMaterializedPointerEndsTracking() {
        // lis r4, 0x8042; addi r4, r4, 0x100 (rd == ra → full pointer);
        // lwz r3, 0x8(r4) is a struct-field access, NOT a new lo half.
        let relocs = analyze([0x3C80_8042, 0x3884_0100, 0x8064_0008])
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8042_0100)
        XCTAssertNil(relocs[0x80003108], "displacement off a materialized pointer must not be relocated")
    }

    func testUpdateFormEndsTracking() {
        // lis r4, 0x8042; lwzu r3, 0x100(r4) (base writeback → full address);
        // lwz r5, 0x4(r4) is a field access off the updated base.
        let relocs = analyze([0x3C80_8042, 0x8464_0100, 0x80A4_0004])
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8042_0100)
        XCTAssertNil(relocs[0x80003108], "update-form writeback must end the lis tracking")
    }

    func testOriPairZeroExtendsAndEmitsRawHigh() {
        // lis r5, 0x8040; ori r5, r5, 0x9000 → 0x80409000 (unsigned lower).
        // The old sign-extending analyzer computed 0x803F9000.
        let relocs = analyze([0x3CA0_8040, 0x60A5_9000])
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8040_9000)
        XCTAssertEqual(relocs[0x80003100]?.halfType, .h,
                       "an unsigned (ori) pair needs the raw high half, not @ha")
    }

    func testPsqConsumer() {
        // lis r6, 0x8042; psq_l f1, 0x10(r6), 0, 0
        let psq: UInt32 = (56 << 26) | (1 << 21) | (6 << 16) | 0x10
        let relocs = analyze([0x3CC0_8042, psq])
        XCTAssertEqual(relocs[0x80003104]?.targetAddress, 0x8042_0010)
        XCTAssertEqual(relocs[0x80003104]?.halfType, .lo)
    }

    func testLmwConsumerAndKillRange() {
        // lis r4, 0x8042; lis r30, 0x8042; lmw r29, 0x100(r4)
        // lmw consumes r4 AND overwrites r29..r31, killing the r30 lis.
        // A following addi r3, r30, 0x200 must NOT be a reloc.
        let lmw: UInt32 = (46 << 26) | (29 << 21) | (4 << 16) | 0x0100
        let relocs = analyze([0x3C80_8042, 0x3FC0_8042, lmw, 0x387E_0200])
        XCTAssertEqual(relocs[0x80003108]?.targetAddress, 0x8042_0100)
        XCTAssertNil(relocs[0x8000310C], "lmw overwrites rD..r31 — the r30 lis must be dead")
    }

    func testIndirectBranchClearsTracking() {
        // lis r4, 0x8042; bctr; lwz r3, 0x100(r4)
        let relocs = analyze([0x3C80_8042, 0x4E80_0420, 0x8064_0100])
        XCTAssertNil(relocs[0x80003108])
    }

    func testOutOfRangeTargetNotRelocated() {
        // lis r4, 0x4330; stw r4, 0x8(r1) — float magic, no section match
        let relocs = analyze([0x3C80_4330, 0x9081_0008])
        XCTAssertTrue(relocs.isEmpty)
    }
}
