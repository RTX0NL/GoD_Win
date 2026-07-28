//
//  PPCHRelocTests.swift
//
//  @h (raw high half) relocations: emission for lis+ori pairs, assembly,
//  and shift behavior versus @ha.
//

import XCTest
@testable import Dolphin
@testable import GoDFoundation

final class PPCHRelocTests: XCTestCase {

    let decoder = PPCDecoder()
    let analyzer = PPCRelocAnalyzer()
    let formatter = PPCFormatter()
    let assembler = PPCSectionAssembler()

    func testHRelocAssemblesRawHigh() throws {
        // sym = 0x80409000: lower half 0x9000 >= 0x8000, so @ha would
        // carry to 0x8041 — @h must stay 0x8040 for the unsigned pair.
        let source = """
        .section .text0

        lis r5, sym@h
        ori r5, r5, sym@l
        """
        let bytes = try assembler.assemble(
            files: [("h.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["sym": 0x8040_9000]
        ).rawBytes
        XCTAssertEqual(bytes, [0x3C, 0xA0, 0x80, 0x40, 0x60, 0xA5, 0x90, 0x00])
    }

    func testHaRelocCarriesForComparison() throws {
        let source = """
        .section .text0

        lis r5, sym@ha
        addi r5, r5, sym@l
        """
        let bytes = try assembler.assemble(
            files: [("ha.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["sym": 0x8040_9000]
        ).rawBytes
        // ha = 0x8041 (carry), lo = -0x7000; reconstructs 0x80409000
        XCTAssertEqual(bytes, [0x3C, 0xA0, 0x80, 0x41, 0x38, 0xA5, 0x90, 0x00])
    }

    /// Full pipeline on a lis+ori pair: analyze → format (must use @h) →
    /// assemble with the symbol shifted — the rebuilt pair must track the
    /// new address exactly.
    func testLisOriPairShiftsThroughFullPipeline() throws {
        let words: [UInt32] = [0x3CA0_8040, 0x60A5_9000] // lis r5, 0x8040; ori r5, r5, 0x9000
        var bytes = [UInt8]()
        for word in words {
            bytes.append(contentsOf: [UInt8(word >> 24 & 0xFF), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)])
        }
        let instructions = decoder.decodeAll(bytes, baseAddress: 0x80003100)
        let relocations = analyzer.analyze(
            instructions,
            symbols: [0x8040_9000: "target"],
            sectionRanges: [(start: 0x80400000, end: 0x80410000)]
        )

        let lines = instructions.map { formatter.format($0, relocations: relocations) }
        XCTAssertEqual(lines[0], "lis r5, target@h")
        XCTAssertEqual(lines[1], "ori r5, r5, target@l")

        let source = ".section .text0\n\n" + lines.joined(separator: "\n")

        // Unshifted: byte-identical to the original pair
        let rebuilt = try assembler.assemble(
            files: [("t.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["target": 0x8040_9000]
        ).rawBytes
        XCTAssertEqual(rebuilt, bytes)

        // Shifted +4: the low half follows, the raw high stays put
        let shifted = try assembler.assemble(
            files: [("t.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["target": 0x8040_9004]
        ).rawBytes
        XCTAssertEqual(shifted, [0x3C, 0xA0, 0x80, 0x40, 0x60, 0xA5, 0x90, 0x04])
    }

    /// psq_l with an @l reloc must format and reassemble byte-exactly.
    func testPsqLoRelocFormatsAndAssembles() throws {
        let psq: UInt32 = (56 << 26) | (1 << 21) | (6 << 16) | 0x10 // psq_l f1, 0x10(r6), 0, 0
        let words: [UInt32] = [0x3CC0_8042, psq]
        var bytes = [UInt8]()
        for word in words {
            bytes.append(contentsOf: [UInt8(word >> 24 & 0xFF), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)])
        }
        let instructions = decoder.decodeAll(bytes, baseAddress: 0x80003100)
        let relocations = analyzer.analyze(
            instructions,
            symbols: [:],
            sectionRanges: [(start: 0x80420000, end: 0x80430000)]
        )
        let lines = instructions.map { formatter.format($0, relocations: relocations) }
        XCTAssertEqual(lines[1], "psq_l f1, lbl_80420010@l(r6), 0, 0")

        let source = ".section .text0\n\n" + lines.joined(separator: "\n")
        let rebuilt = try assembler.assemble(
            files: [("psq.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["lbl_80420010": 0x8042_0010]
        ).rawBytes
        XCTAssertEqual(rebuilt, bytes)
    }

    /// A shifted psq @l that overflows the 12-bit displacement must fail
    /// loudly, never truncate.
    func testPsqDisplacementOverflowThrows() {
        let source = """
        .section .text0

        psq_l f1, sym@l(r6), 0, 0
        """
        XCTAssertThrowsError(try assembler.assemble(
            files: [("psq.s", source)],
            baseAddress: 0x80003100,
            externalSymbols: ["sym": 0x8042_0900]  // lo = 0x900, outside ±0x800
        ))
    }
}
