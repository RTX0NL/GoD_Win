import XCTest
@testable import Dolphin
@testable import GoDFoundation

final class PPCAssemblyRoundTripTests: XCTestCase {

    let decoder = PPCDecoder()
    let encoder = PPCEncoder()
    let formatter = PPCFormatter()
    let parser = PPCAssemblyParser()
    let assembler = PPCSectionAssembler()

    // MARK: - Format → Parse → Encode round-trip

    /// Test that formatting an instruction and parsing it back produces the same encoding
    func formatRoundTrip(_ raw: UInt32, address: UInt32 = 0x80003100, file: StaticString = #file, line: UInt = #line) {
        let inst = decoder.decode(raw, at: address)
        guard let decoded = inst.decoded else {
            XCTFail("Decode failed for 0x\(String(raw, radix: 16))", file: file, line: line)
            return
        }

        // Format to assembly text
        let text = formatter.format(inst)

        // Parse back
        let parsed = parser.parseLine(text)
        guard case .instruction(let mnemonic, let operands) = parsed else {
            XCTFail("Parse failed for '\(text)' (from 0x\(String(raw, radix: 16)))", file: file, line: line)
            return
        }

        // Resolve operands (no labels in this test, just raw values)
        let resolvedOps = operands.map { op -> PPCInstruction.Operand in
            switch op {
            case .gpr(let r):    return .gpr(r)
            case .fpr(let r):    return .fpr(r)
            case .simm(let v):   return .simm(v)
            case .uimm(let v):   return .uimm(v)
            case .memory(let off, let base): return .memory(offset: Int16(clamping: off), base: base)
            case .crField(let f): return .crField(f)
            case .crBit(let b):  return .crBit(b)
            case .spr(let s):    return .spr(s)
            case .label(let l):
                if l.hasPrefix("0x"), let addr = UInt32(l.dropFirst(2), radix: 16) {
                    return .branchTarget(addr)
                }
                return .branchTarget(0)
            case .shift(let s):  return .shift(s)
            case .maskBegin(let m): return .maskBegin(m)
            case .maskEnd(let m): return .maskEnd(m)
            case .count(let c):  return .count(c)
            case .gqr(let g):    return .gqr(g)
            case .wBit(let w):   return .wBit(w)
            case .haReloc, .loReloc, .loRelocMemory:
                return .simm(0)
            }
        }

        guard let reencoded = encoder.encode(mnemonic: mnemonic, operands: resolvedOps, currentAddress: address) else {
            XCTFail("Re-encode failed for '\(text)' mnemonic=\(mnemonic)", file: file, line: line)
            return
        }

        XCTAssertEqual(reencoded, raw,
            "Format round-trip mismatch for '\(text)': original=0x\(String(raw, radix: 16)) reencoded=0x\(String(reencoded, radix: 16))",
            file: file, line: line)
    }

    func testArithmetic()  { formatRoundTrip(0x38641234) } // addi r3, r4, 0x1234
    func testLi()          { formatRoundTrip(0x38600000) } // li r3, 0
    func testLis()         { formatRoundTrip(0x3C608034) } // lis r3, 0x8034
    func testOri()         { formatRoundTrip(0x60000EEF) } // ori r0, r0, 0xEEF
    func testAndi()        { formatRoundTrip(0x70000EEF) } // andi. r0, r0, 0xEEF
    func testLwz()         { formatRoundTrip(0x8001000C) } // lwz r0, 0xc(r1)
    func testStw()         { formatRoundTrip(0x90010004) } // stw r0, 0x4(r1)
    func testStwu()        { formatRoundTrip(0x9421FFF8) } // stwu r1, -0x8(r1)
    func testBlr()         { formatRoundTrip(0x4E800020) } // blr
    func testMflr()        { formatRoundTrip(0x7C0802A6) } // mflr r0
    func testMtlr()        { formatRoundTrip(0x7C0803A6) } // mtlr r0
    func testNop()         { formatRoundTrip(0x60000000) } // nop

    func testBranch()      { formatRoundTrip(0x480ACB15, address: 0x8000312C) } // bl
    func testBne()         { formatRoundTrip(0x40820014, address: 0x8000311C) } // bne
    func testCmpwi()       { formatRoundTrip(0x2C000EEF) } // cmpwi

    // MARK: - Full assembler round-trip with .s file

    func testAssemblerRoundTrip() throws {
        // Create a small synthetic assembly
        let asmText = """
        .section .text0

        .global testFunc
        testFunc:
            stwu r1, -0x10(r1)
            mflr r0
            stw r0, 0x14(r1)
            li r3, 0x42
            bl helperFunc
            lwz r0, 0x14(r1)
            mtlr r0
            addi r1, r1, 0x10
            blr

        .global helperFunc
        helperFunc:
            li r3, 0x1
            blr
        """

        let baseAddress: UInt32 = 0x80003100
        let result = try assembler.assemble(files: [("test.s", asmText)], baseAddress: baseAddress)
        let bytes = result.rawBytes

        // Verify each instruction
        func word(at offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset+1]) << 16 |
            UInt32(bytes[offset+2]) << 8 | UInt32(bytes[offset+3])
        }

        // stwu r1, -0x10(r1) = 0x9421FFF0
        XCTAssertEqual(word(at: 0), 0x9421FFF0, "stwu r1, -0x10(r1)")
        // mflr r0 = 0x7C0802A6
        XCTAssertEqual(word(at: 4), 0x7C0802A6, "mflr r0")
        // stw r0, 0x14(r1) = 0x90010014
        XCTAssertEqual(word(at: 8), 0x90010014, "stw r0, 0x14(r1)")
        // li r3, 0x42 = 0x38600042
        XCTAssertEqual(word(at: 12), 0x38600042, "li r3, 0x42")
        // bl helperFunc — target is 0x80003124 (9 instructions * 4 = 0x24 from base)
        // offset = 0x24 - 0x10 = 0x14
        let blWord = word(at: 16)
        XCTAssertEqual(blWord & 0xFC000003, 0x48000001, "bl opcode + LK bit")
        // helperFunc at offset 0x24, current instruction at offset 0x10
        // relative = 0x14
        XCTAssertEqual(blWord, 0x48000015, "bl helperFunc (relative offset 0x14)")
        // blr = 0x4E800020
        XCTAssertEqual(word(at: 32), 0x4E800020, "blr (end of testFunc)")
        // helperFunc: li r3, 1 = 0x38600001
        XCTAssertEqual(word(at: 36), 0x38600001, "li r3, 0x1 (helperFunc)")
        // blr = 0x4E800020
        XCTAssertEqual(word(at: 40), 0x4E800020, "blr (end of helperFunc)")

        // Total: 11 instructions = 44 bytes
        XCTAssertEqual(bytes.count, 44)
    }

    // MARK: - Shiftable round-trip with @ha/@l

    func testShiftableRoundTrip() throws {
        let asmText = """
        .section .text0

        .global main
        main:
            lis r3, myData@ha
            addi r3, r3, myData@l
            lwz r4, 0x0(r3)
            blr

        .section .data0

        .global myData
        myData:
            .4byte 0xDEADBEEF
        """

        let baseAddress: UInt32 = 0x80003100
        let result = try assembler.assemble(files: [("test.s", asmText)], baseAddress: baseAddress)
        let bytes = result.rawBytes

        func word(at offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset+1]) << 16 |
            UInt32(bytes[offset+2]) << 8 | UInt32(bytes[offset+3])
        }

        // myData is at offset 16 (4 instructions * 4) = address 0x80003110
        let myDataAddr: UInt32 = 0x80003110
        let ha = (myDataAddr >> 16) + ((myDataAddr & 0x8000) != 0 ? 1 : 0)
        let lo = myDataAddr & 0xFFFF

        // lis r3, myData@ha
        let lisWord = word(at: 0)
        let expectedLis = UInt32(0x3C600000) | (ha & 0xFFFF)
        XCTAssertEqual(lisWord, expectedLis, "lis r3, myData@ha")

        // addi r3, r3, myData@l
        let addiWord = word(at: 4)
        let expectedAddi = UInt32(0x38630000) | (lo & 0xFFFF)
        XCTAssertEqual(addiWord, expectedAddi, "addi r3, r3, myData@l")

        // .4byte 0xDEADBEEF
        XCTAssertEqual(word(at: 16), 0xDEADBEEF, ".4byte data")
    }

    // MARK: - Multi-file round-trip

    func testMultiFileAssembly() throws {
        let file1 = """
        .section .text0

        .global funcA
        funcA:
            li r3, 0x1
            bl funcB
            blr
        """

        let file2 = """
        .section .text0

        .global funcB
        funcB:
            li r3, 0x2
            blr
        """

        let baseAddress: UInt32 = 0x80003100
        let result = try assembler.assemble(
            files: [("funcA.s", file1), ("funcB.s", file2)],
            baseAddress: baseAddress
        )
        let bytes = result.rawBytes

        func word(at offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset+1]) << 16 |
            UInt32(bytes[offset+2]) << 8 | UInt32(bytes[offset+3])
        }

        // funcA: li r3, 1
        XCTAssertEqual(word(at: 0), 0x38600001)
        // funcA: bl funcB — funcB is at offset 0xC (3 instructions), current at 0x4
        // relative = 0x8
        XCTAssertEqual(word(at: 4), 0x48000009) // bl +0x8
        // funcA: blr
        XCTAssertEqual(word(at: 8), 0x4E800020)
        // funcB: li r3, 2
        XCTAssertEqual(word(at: 12), 0x38600002)
        // funcB: blr
        XCTAssertEqual(word(at: 16), 0x4E800020)

        XCTAssertEqual(bytes.count, 20)
    }
}
