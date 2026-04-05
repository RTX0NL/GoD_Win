import XCTest
@testable import Dolphin

final class PPCEncoderTests: XCTestCase {

    let decoder = PPCDecoder()
    let encoder = PPCEncoder()

    /// Decode a raw instruction word, then re-encode it and verify identical bits.
    func roundTrip(_ raw: UInt32, address: UInt32 = 0x80003100, file: StaticString = #file, line: UInt = #line) {
        let inst = decoder.decode(raw, at: address)
        guard let decoded = inst.decoded else {
            XCTFail("Failed to decode 0x\(String(raw, radix: 16, uppercase: true))", file: file, line: line)
            return
        }
        guard let encoded = encoder.encode(mnemonic: decoded.mnemonic, operands: decoded.operands, currentAddress: address) else {
            XCTFail("Failed to encode \(decoded.mnemonic) (decoded from 0x\(String(raw, radix: 16, uppercase: true)))", file: file, line: line)
            return
        }
        XCTAssertEqual(encoded, raw,
            "Round-trip mismatch for \(decoded.mnemonic): original=0x\(String(raw, radix: 16, uppercase: true)) encoded=0x\(String(encoded, radix: 16, uppercase: true))",
            file: file, line: line)
    }

    // MARK: - Arithmetic immediate

    func testAddi()   { roundTrip(0x38641234) } // addi r3, r4, 0x1234
    func testAddis()  { roundTrip(0x3C608000) } // lis r3, -0x8000 (addis r3, 0, -0x8000)
    func testLi()     { roundTrip(0x38600000) } // li r3, 0
    func testLis()    { roundTrip(0x3C608034) } // lis r3, 0x8034
    func testAddic()  { roundTrip(0x30830010) } // addic r4, r3, 0x10
    func testSubfic() { roundTrip(0x20830001) } // subfic r4, r3, 1
    func testMulli()  { roundTrip(0x1C630004) } // mulli r3, r3, 4

    // MARK: - Compare immediate

    func testCmpwi()  { roundTrip(0x2C000EEF) } // cmpwi r0, 0xEEF
    func testCmplwi() { roundTrip(0x28030000) } // cmplwi r3, 0

    // MARK: - Logical immediate

    func testOri()    { roundTrip(0x60000EEF) } // ori r0, r0, 0xEEF
    func testAndi()   { roundTrip(0x70000EEF) } // andi. r0, r0, 0xEEF
    func testXori()   { roundTrip(0x68630001) } // xori r3, r3, 1

    // MARK: - Load/store

    func testLwz()    { roundTrip(0x8001000C) } // lwz r0, 0xc(r1)
    func testStw()    { roundTrip(0x90010004) } // stw r0, 0x4(r1)
    func testStwu()   { roundTrip(0x9421FFF8) } // stwu r1, -0x8(r1)
    func testLhz()    { roundTrip(0xA00330E4) } // lhz r0, 0x30e4(r3)
    func testLbz()    { roundTrip(0x886DAD50) } // lbz r3, -0x52b0(r13)
    func testStb()    { roundTrip(0x980DAD50) } // stb r0, -0x52b0(r13)
    func testLfs()    { roundTrip(0xC0010010) } // lfs f0, 0x10(r1)
    func testStfd()   { roundTrip(0xD8210008) } // stfd f1, 0x8(r1)
    func testLmw()    { roundTrip(0xBF410008) } // lmw r26, 0x8(r1)
    func testStmw()   { roundTrip(0xBF410008) } // stmw equivalent

    // MARK: - Branches

    func testB()      { roundTrip(0x48000058, address: 0x800030B8) } // b 0x80003110
    func testBl()     { roundTrip(0x480ACB15, address: 0x8000312C) } // bl 0x800AFC40
    func testBlr()    { roundTrip(0x4E800020) } // blr
    func testBctr()   { roundTrip(0x4E800420) } // bctr
    func testBctrl()  { roundTrip(0x4E800421) } // bctrl
    func testBne()    { roundTrip(0x40820014, address: 0x8000311C) } // bne 0x80003130
    func testBeq()    { roundTrip(0x41820010, address: 0x80003200) } // beq 0x80003210

    // MARK: - ALU extended (opcode 31)

    func testAdd()    { roundTrip(0x7C632214) } // add r3, r3, r4
    func testSubf()   { roundTrip(0x7C641850) } // subf r3, r4, r3
    func testMullw()  { roundTrip(0x7C6319D6) } // mullw r3, r3, r3
    func testOr()     { roundTrip(0x7C7A1B78) } // or r26, r3, r3 (mr r26, r3)
    func testMr()     { roundTrip(0x7C7A1B78) } // mr r26, r3

    // MARK: - Shift/rotate

    func testSlwi()   { roundTrip(0x5463083C) } // slwi r3, r3, 1
    func testRlwinm() { roundTrip(0x5400043E) } // clrlwi r0, r0, 16 (rlwinm r0, r0, 0, 16, 31)

    // MARK: - SPR

    func testMflr()   { roundTrip(0x7C0802A6) } // mflr r0
    func testMtlr()   { roundTrip(0x7C0803A6) } // mtlr r0
    func testMfctr()  { roundTrip(0x7C0902A6) } // mfctr r0
    func testMtctr()  { roundTrip(0x7C0903A6) } // mtctr r0

    // MARK: - Float

    func testFmr()    { roundTrip(0xFC200890) } // fmr f1, f1
    func testFcmpu()  { roundTrip(0xFC001040) } // fcmpu cr0, f0, f2

    // MARK: - System

    func testSync()   { roundTrip(0x7C0004AC) } // sync
    func testIsync()  { roundTrip(0x4C00012C) } // isync
    func testRfi()    { roundTrip(0x4C000064) } // rfi

    // MARK: - Cache

    func testDcbf()   { roundTrip(0x7C0028AC) } // dcbf r0, r5
    func testIcbi()   { roundTrip(0x7C001FAC) } // icbi r0, r3

    // MARK: - Nop

    func testNop()    { roundTrip(0x60000000) } // nop (ori 0, 0, 0)

    // MARK: - Bulk test from real DOL

    func testBulkRoundTrip() {
        // First 100 instructions from XD US text section 0
        let rawInstructions: [UInt32] = [
            0x7C0802A6, 0x3C608000, 0x90010004, 0x9421FFF8,
            0xA00330E4, 0x70000EEF, 0x2C000EEF, 0x40820014,
            0x38600000, 0x38800000, 0x38A00000, 0x480ACB15,
            0x8001000C, 0x38210008, 0x7C0803A6, 0x4E800020,
            0x38000001, 0x980DAD50, 0x4E800020, 0x886DAD50,
        ]

        var passed = 0
        var failed = 0
        for (i, raw) in rawInstructions.enumerated() {
            let addr = UInt32(0x80003100 + i * 4)
            let inst = decoder.decode(raw, at: addr)
            guard let decoded = inst.decoded else {
                failed += 1
                continue
            }
            if let encoded = encoder.encode(mnemonic: decoded.mnemonic, operands: decoded.operands, currentAddress: addr) {
                if encoded == raw {
                    passed += 1
                } else {
                    XCTFail("Mismatch at \(String(addr, radix: 16)): \(decoded.mnemonic) original=0x\(String(raw, radix: 16)) encoded=0x\(String(encoded, radix: 16))")
                    failed += 1
                }
            } else {
                XCTFail("Encode failed for \(decoded.mnemonic) at 0x\(String(addr, radix: 16))")
                failed += 1
            }
        }
        XCTAssertEqual(failed, 0, "\(failed) instructions failed round-trip out of \(rawInstructions.count)")
    }
}
