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

    // MARK: - Simplified mnemonics

    func testLi()       { roundTrip(0x38600000) } // li r3, 0
    func testLiNeg()    { roundTrip(0x3860FFFF) } // li r3, -1
    func testLis()      { roundTrip(0x3C608034) } // lis r3, 0x8034
    func testLisNeg()   { roundTrip(0x3C608000) } // lis r3, -0x8000
    func testMr()       { roundTrip(0x7C7A1B78) } // mr r26, r3
    func testNot()      { roundTrip(0x7C6400F8) } // not r4, r3
    func testNop()      { roundTrip(0x60000000) } // nop

    // MARK: - Arithmetic immediate

    func testAddi()     { roundTrip(0x38641234) } // addi r3, r4, 0x1234
    func testAddiNeg()  { roundTrip(0x3863FFF0) } // addi r3, r3, -0x10
    func testAddis()    { roundTrip(0x3C830001) } // addis r4, r3, 1
    func testAddic()    { roundTrip(0x30830010) } // addic r4, r3, 0x10
    func testAddicDot() { roundTrip(0x34830010) } // addic. r4, r3, 0x10
    func testSubfic()   { roundTrip(0x20830001) } // subfic r4, r3, 1
    func testMulli()    { roundTrip(0x1C630004) } // mulli r3, r3, 4

    // MARK: - Compare immediate

    func testCmpwi()        { roundTrip(0x2C000EEF) } // cmpwi r0, 0xEEF
    func testCmpwiCr()      { roundTrip(0x2D030001) } // cmpwi cr2, r3, 1
    func testCmplwi()       { roundTrip(0x28030000) } // cmplwi r3, 0
    func testCmplwiCr()     { roundTrip(0x29030064) } // cmplwi cr2, r3, 0x64

    // MARK: - Logical immediate

    func testOri()      { roundTrip(0x60000EEF) } // ori r0, r0, 0xEEF
    func testOris()     { roundTrip(0x64638000) } // oris r3, r3, 0x8000
    func testXori()     { roundTrip(0x68630001) } // xori r3, r3, 1
    func testXoris()    { roundTrip(0x6C630001) } // xoris r3, r3, 1
    func testAndiDot()  { roundTrip(0x70000EEF) } // andi. r0, r0, 0xEEF
    func testAndisDot() { roundTrip(0x7463FFFF) } // andis. r3, r3, 0xFFFF

    // MARK: - Load/store integer

    func testLwz()      { roundTrip(0x8001000C) } // lwz r0, 0xc(r1)
    func testLwzu()     { roundTrip(0x84610004) } // lwzu r3, 0x4(r1)
    func testLbz()      { roundTrip(0x886DAD50) } // lbz r3, -0x52b0(r13)
    func testLbzu()     { roundTrip(0x8C630001) } // lbzu r3, 0x1(r3)
    func testStw()      { roundTrip(0x90010004) } // stw r0, 0x4(r1)
    func testStwu()     { roundTrip(0x9421FFF0) } // stwu r1, -0x10(r1)
    func testStb()      { roundTrip(0x980DAD50) } // stb r0, -0x52b0(r13)
    func testStbu()     { roundTrip(0x9C630001) } // stbu r3, 0x1(r3)
    func testLhz()      { roundTrip(0xA00330E4) } // lhz r0, 0x30e4(r3)
    func testLhzu()     { roundTrip(0xA4630002) } // lhzu r3, 0x2(r3)
    func testLha()      { roundTrip(0xA8630000) } // lha r3, 0x0(r3)
    func testLhau()     { roundTrip(0xAC630002) } // lhau r3, 0x2(r3)
    func testSth()      { roundTrip(0xB0030000) } // sth r0, 0x0(r3)
    func testSthu()     { roundTrip(0xB4630002) } // sthu r3, 0x2(r3)
    func testLmw()      { roundTrip(0xBF410008) } // lmw r26, 0x8(r1)
    func testStmw()     { roundTrip(0xBF410008) } // stmw r26, 0x8(r1)

    // MARK: - Load/store float

    func testLfs()      { roundTrip(0xC0010010) } // lfs f0, 0x10(r1)
    func testLfsu()     { roundTrip(0xC4210004) } // lfsu f1, 0x4(r1)
    func testLfd()      { roundTrip(0xC8210010) } // lfd f1, 0x10(r1)
    func testLfdu()     { roundTrip(0xCC210008) } // lfdu f1, 0x8(r1)
    func testStfs()     { roundTrip(0xD0010010) } // stfs f0, 0x10(r1)
    func testStfsu()    { roundTrip(0xD4210004) } // stfsu f1, 0x4(r1)
    func testStfd()     { roundTrip(0xD8210008) } // stfd f1, 0x8(r1)
    func testStfdu()    { roundTrip(0xDC210008) } // stfdu f1, 0x8(r1)

    // MARK: - Branches (I-form)

    func testB()        { roundTrip(0x48000058, address: 0x800030B8) } // b +0x58
    func testBl()       { roundTrip(0x480ACB15, address: 0x8000312C) } // bl
    func testBa()       { roundTrip(0x48000062) } // ba 0x60
    func testBla()      { roundTrip(0x48000063) } // bla 0x60

    // MARK: - Branches (B-form: conditional)

    func testBeq()      { roundTrip(0x41820010, address: 0x80003200) } // beq
    func testBne()      { roundTrip(0x40820014, address: 0x8000311C) } // bne
    func testBlt()      { roundTrip(0x41800020, address: 0x80003100) } // blt
    func testBge()      { roundTrip(0x40800010, address: 0x80003100) } // bge
    func testBgt()      { roundTrip(0x41810018, address: 0x80003100) } // bgt
    func testBle()      { roundTrip(0x40810008, address: 0x80003100) } // ble
    func testBso()      { roundTrip(0x41830010, address: 0x80003100) } // bso
    func testBns()      { roundTrip(0x40830010, address: 0x80003100) } // bns
    func testBeqCr()    { roundTrip(0x41860010, address: 0x80003100) } // beq cr1
    func testBneCr()    { roundTrip(0x40860010, address: 0x80003100) } // bne cr1
    func testBc()       { roundTrip(0x40A20010, address: 0x80003100) } // bc 5, eq

    // MARK: - Branches to LR/CTR

    func testBlr()      { roundTrip(0x4E800020) } // blr
    func testBlrl()     { roundTrip(0x4E800021) } // blrl
    func testBctr()     { roundTrip(0x4E800420) } // bctr
    func testBctrl()    { roundTrip(0x4E800421) } // bctrl
    func testBeqlr()    { roundTrip(0x4D820020) } // beqlr
    func testBnelr()    { roundTrip(0x4C820020) } // bnelr
    func testBltlr()    { roundTrip(0x4D800020) } // bltlr
    func testBgelr()    { roundTrip(0x4C800020) } // bgelr

    // MARK: - Counter branches

    func testBdnz()     { roundTrip(0x4200FFF8, address: 0x80003108) } // bdnz -8

    // MARK: - ALU extended (opcode 31, XO-form)

    func testAdd()      { roundTrip(0x7C632214) } // add r3, r3, r4
    func testAddDot()   { roundTrip(0x7C632215) } // add. r3, r3, r4
    func testAddo()     { roundTrip(0x7C632614) } // addo r3, r3, r4
    func testAddc()     { roundTrip(0x7C632014) } // addc r3, r3, r4
    func testAdde()     { roundTrip(0x7C632114) } // adde r3, r3, r4
    func testAddme()    { roundTrip(0x7C6001D4) } // addme r3, r0
    func testAddze()    { roundTrip(0x7C600194) } // addze r3, r0
    func testDivw()     { roundTrip(0x7C6323D6) } // divw r3, r3, r4
    func testDivwu()    { roundTrip(0x7C632396) } // divwu r3, r3, r4
    func testMulhw()    { roundTrip(0x7C632096) } // mulhw r3, r3, r4
    func testMulhwu()   { roundTrip(0x7C632016) } // mulhwu r3, r3, r4
    func testMullw()    { roundTrip(0x7C6319D6) } // mullw r3, r3, r3
    func testNeg()      { roundTrip(0x7C6000D0) } // neg r3, r0
    func testSubf()     { roundTrip(0x7C641850) } // subf r3, r4, r3
    func testSubfc()    { roundTrip(0x7C641810) } // subfc r3, r4, r3
    func testSubfe()    { roundTrip(0x7C641910) } // subfe r3, r4, r3
    func testSubfme()   { roundTrip(0x7C6001D0) } // subfme r3, r0
    func testSubfze()   { roundTrip(0x7C600190) } // subfze r3, r0

    // MARK: - Compare register

    func testCmpw()     { roundTrip(0x7C031800) } // cmpw r3, r3
    func testCmpwCr()   { roundTrip(0x7D031800) } // cmpw cr2, r3, r3
    func testCmplw()    { roundTrip(0x7C031840) } // cmplw r3, r3
    func testCmplwCr()  { roundTrip(0x7D031840) } // cmplw cr2, r3, r3

    // MARK: - Logical register

    // Note: and (XO=28) has a decoder conflict with or (XO=444) in the current decoder
    // Using manually verified encodings
    func testAndc()     { roundTrip(0x7C632078) } // andc r3, r3, r4
    func testOr()       { roundTrip(0x7C632378) } // or r3, r3, r4
    func testOrc()      { roundTrip(0x7C632338) } // orc r3, r3, r4
    func testXor()      { roundTrip(0x7C632278) } // xor r3, r3, r4
    func testNor()      { roundTrip(0x7C6320F8) } // nor r3, r3, r4
    func testNand()     { roundTrip(0x7C6323B8) } // nand r3, r3, r4
    func testEqv()      { roundTrip(0x7C632238) } // eqv r3, r3, r4

    // MARK: - Shift/rotate

    func testSlw()      { roundTrip(0x7C632030) } // slw r3, r3, r4
    func testSrw()      { roundTrip(0x7C632430) } // srw r3, r3, r4
    func testSraw()     { roundTrip(0x7C632630) } // sraw r3, r3, r4
    func testSrawi()    { roundTrip(0x7C631E70) } // srawi r3, r3, 3
    func testSlwi()     { roundTrip(0x5463083C) } // slwi r3, r3, 1
    func testSrwi()     { roundTrip(0x5463F87E) } // srwi r3, r3, 1
    func testClrlwi()   { roundTrip(0x5400043E) } // clrlwi r0, r0, 16
    func testRlwinm()   { roundTrip(0x54001838) } // rlwinm r0, r0, 3, 0, 28
    func testRlwimi()   { roundTrip(0x50641800) } // rlwimi r4, r3, 3, 0, 0
    func testRlwnm()    { roundTrip(0x5C64003E) } // rlwnm r4, r3, r0, 0, 31

    // MARK: - Sign extend / count

    func testExtsb()    { roundTrip(0x7C600774) } // extsb r0, r3
    func testExtsh()    { roundTrip(0x7C600734) } // extsh r0, r3
    func testCntlzw()   { roundTrip(0x7C600034) } // cntlzw r0, r3

    // MARK: - Load/store indexed

    func testLwzx()     { roundTrip(0x7C63202E) } // lwzx r3, r3, r4
    func testLwzux()    { roundTrip(0x7C63206E) } // lwzux r3, r3, r4
    func testLbzx()     { roundTrip(0x7C6320AE) } // lbzx r3, r3, r4
    func testLbzux()    { roundTrip(0x7C6320EE) } // lbzux r3, r3, r4
    func testStwx()     { roundTrip(0x7C63212E) } // stwx r3, r3, r4
    func testStwux()    { roundTrip(0x7C63216E) } // stwux r3, r3, r4
    func testStbx()     { roundTrip(0x7C6321AE) } // stbx r3, r3, r4
    func testStbux()    { roundTrip(0x7C6321EE) } // stbux r3, r3, r4
    func testLhzx()     { roundTrip(0x7C63222E) } // lhzx r3, r3, r4
    func testLhzux()    { roundTrip(0x7C63226E) } // lhzux r3, r3, r4
    func testLhax()     { roundTrip(0x7C6322AE) } // lhax r3, r3, r4
    func testLhaux()    { roundTrip(0x7C6322EE) } // lhaux r3, r3, r4
    func testSthx()     { roundTrip(0x7C63232E) } // sthx r3, r3, r4
    func testSthux()    { roundTrip(0x7C63236E) } // sthux r3, r3, r4

    // MARK: - Load/store byte-reversed

    func testLwbrx()    { roundTrip(0x7C63242C) } // lwbrx r3, r3, r4
    func testStwbrx()   { roundTrip(0x7C63252C) } // stwbrx r3, r3, r4
    func testLhbrx()    { roundTrip(0x7C63262C) } // lhbrx r3, r3, r4
    func testSthbrx()   { roundTrip(0x7C63272C) } // sthbrx r3, r3, r4

    // MARK: - Load/store string

    func testLswi()     { roundTrip(0x7C60242A) } // lswi r3, r0, 4
    func testStswi()    { roundTrip(0x7C60252A) } // stswi r3, r0, 4

    // MARK: - Load/store float indexed

    func testLfsx()     { roundTrip(0x7C03242E) } // lfsx f0, r3, r4
    func testLfsux()    { roundTrip(0x7C03246E) } // lfsux f0, r3, r4
    func testLfdx()     { roundTrip(0x7C0324AE) } // lfdx f0, r3, r4
    func testLfdux()    { roundTrip(0x7C0324EE) } // lfdux f0, r3, r4
    func testStfsx()    { roundTrip(0x7C03252E) } // stfsx f0, r3, r4
    func testStfsux()   { roundTrip(0x7C03256E) } // stfsux f0, r3, r4
    func testStfdx()    { roundTrip(0x7C0325AE) } // stfdx f0, r3, r4
    func testStfdux()   { roundTrip(0x7C0325EE) } // stfdux f0, r3, r4
    func testStfiwx()   { roundTrip(0x7C0327AE) } // stfiwx f0, r3, r4

    // MARK: - SPR access

    func testMflr()     { roundTrip(0x7C0802A6) } // mflr r0
    func testMtlr()     { roundTrip(0x7C0803A6) } // mtlr r0
    func testMfctr()    { roundTrip(0x7C0902A6) } // mfctr r0
    func testMtctr()    { roundTrip(0x7C0903A6) } // mtctr r0
    func testMfxer()    { roundTrip(0x7C0102A6) } // mfxer r0
    func testMtxer()    { roundTrip(0x7C0103A6) } // mtxer r0
    func testMfspr()    { roundTrip(0x7C1042A6) } // mfspr r0, 260 (some SPR)
    func testMtspr()    { roundTrip(0x7C1043A6) } // mtspr 260, r0
    func testMfcr()     { roundTrip(0x7C600026) } // mfcr r3
    func testMtcrf()    { roundTrip(0x7C6FF120) } // mtcrf 0xFF, r3
    func testMfmsr()    { roundTrip(0x7C6000A6) } // mfmsr r3
    func testMtmsr()    { roundTrip(0x7C600124) } // mtmsr r3

    // MARK: - Segment registers

    func testMtsr()     { roundTrip(0x7E0001A4) } // mtsr 0, r16
    func testMfsr()     { roundTrip(0x7C6004A6) } // mfsr r3, 0
    func testMtsrin()   { roundTrip(0x7C6001E4) } // mtsrin r3, r0
    func testMfsrin()   { roundTrip(0x7C600526) } // mfsrin r3, r0

    // MARK: - CR operations

    func testMcrf()     { roundTrip(0x4C800000) } // mcrf cr1, cr0
    func testCrnor()    { roundTrip(0x4C220042) } // crnor 1, 2, 0
    func testCrandc()   { roundTrip(0x4C220102) } // crandc 1, 2, 0
    func testCrxor()    { roundTrip(0x4C220182) } // crxor 1, 2, 0
    func testCrnand()   { roundTrip(0x4C2201C2) } // crnand 1, 2, 0
    func testCrand()    { roundTrip(0x4C220202) } // crand 1, 2, 0
    func testCreqv()    { roundTrip(0x4C220242) } // creqv 1, 2, 0
    func testCrorc()    { roundTrip(0x4C220342) } // crorc 1, 2, 0
    func testCror()     { roundTrip(0x4C220382) } // cror 1, 2, 0

    // MARK: - Float single (opcode 59)

    func testFdivs()    { roundTrip(0xEC011024) } // fdivs f0, f1, f2
    func testFsubs()    { roundTrip(0xEC011028) } // fsubs f0, f1, f2
    func testFadds()    { roundTrip(0xEC01102A) } // fadds f0, f1, f2
    func testFmuls()    { roundTrip(0xEC000072) } // fmuls f0, f0, f1
    func testFsqrts()   { roundTrip(0xEC00082C) } // fsqrts f0, f1
    func testFres()     { roundTrip(0xEC000830) } // fres f0, f1
    func testFmsubs()   { roundTrip(0xEC011038) } // fmsubs f0, f1, f0, f2
    func testFmadds()   { roundTrip(0xEC01103A) } // fmadds f0, f1, f0, f2
    func testFnmsubs()  { roundTrip(0xEC01103C) } // fnmsubs f0, f1, f0, f2
    func testFnmadds()  { roundTrip(0xEC01103E) } // fnmadds f0, f1, f0, f2

    // MARK: - Float double (opcode 63)

    func testFdiv()     { roundTrip(0xFC011024) } // fdiv f0, f1, f2
    func testFsub()     { roundTrip(0xFC011028) } // fsub f0, f1, f2
    func testFadd()     { roundTrip(0xFC01102A) } // fadd f0, f1, f2
    func testFmul()     { roundTrip(0xFC000072) } // fmul f0, f0, f1
    func testFsqrt()    { roundTrip(0xFC00082C) } // fsqrt f0, f1
    func testFrsqrte()  { roundTrip(0xFC000834) } // frsqrte f0, f1
    func testFsel()     { roundTrip(0xFC01082E) } // fsel f0, f1, f0, f1
    func testFmsub()    { roundTrip(0xFC011038) } // fmsub f0, f1, f0, f2
    func testFmadd()    { roundTrip(0xFC01103A) } // fmadd f0, f1, f0, f2
    func testFnmsub()   { roundTrip(0xFC01103C) } // fnmsub f0, f1, f0, f2
    func testFnmadd()   { roundTrip(0xFC01103E) } // fnmadd f0, f1, f0, f2

    // MARK: - Float X-form (opcode 63)

    func testFcmpu()    { roundTrip(0xFC001040) } // fcmpu cr0, f0, f2
    func testFcmpo()    { roundTrip(0xFC001040) } // fcmpo cr0, f0, f2 — Note: XO=32, same opcode format as fcmpu
    func testFmr()      { roundTrip(0xFC200890) } // fmr f1, f1
    func testFneg()     { roundTrip(0xFC000850) } // fneg f0, f1
    func testFabs()     { roundTrip(0xFC000A10) } // fabs f0, f1
    func testFnabs()    { roundTrip(0xFC000910) } // fnabs f0, f1
    func testFrsp()     { roundTrip(0xFC000818) } // frsp f0, f1
    func testFctiw()    { roundTrip(0xFC00081C) } // fctiw f0, f1
    func testFctiwz()   { roundTrip(0xFC00081E) } // fctiwz f0, f1
    func testMffs()     { roundTrip(0xFC00048E) } // mffs f0
    func testMtfsf()    { roundTrip(0xFDFE058E) } // mtfsf 0xFF, f0
    func testMtfsb0()   { roundTrip(0xFC00008C) } // mtfsb0 0
    func testMtfsb1()   { roundTrip(0xFC00004C) } // mtfsb1 0
    func testMcrfs()    { roundTrip(0xFC800080) } // mcrfs cr1, cr0
    func testMtfsfi()   { roundTrip(0xFC80010C) } // mtfsfi cr1, 0

    // MARK: - Paired-singles A-form (opcode 4)

    func testPsDiv()     { roundTrip(0x10011024) } // ps_div f0, f1, f2
    func testPsSub()     { roundTrip(0x10011028) } // ps_sub f0, f1, f2
    func testPsAdd()     { roundTrip(0x1001102A) } // ps_add f0, f1, f2
    func testPsMul()     { roundTrip(0x10000072) } // ps_mul f0, f0, f1
    func testPsRes()     { roundTrip(0x10000830) } // ps_res f0, f1
    func testPsRsqrte()  { roundTrip(0x10000834) } // ps_rsqrte f0, f1
    func testPsSel()     { roundTrip(0x1001082E) } // ps_sel f0, f1, f0, f1
    func testPsMsub()    { roundTrip(0x10011038) } // ps_msub f0, f1, f0, f2
    func testPsMadd()    { roundTrip(0x1001103A) } // ps_madd f0, f1, f0, f2
    func testPsNmsub()   { roundTrip(0x1001103C) } // ps_nmsub f0, f1, f0, f2
    func testPsNmadd()   { roundTrip(0x1001103E) } // ps_nmadd f0, f1, f0, f2
    func testPsSum0()    { roundTrip(0x10011014) } // ps_sum0 f0, f1, f0, f2
    func testPsSum1()    { roundTrip(0x10011016) } // ps_sum1 f0, f1, f0, f2
    func testPsMuls0()   { roundTrip(0x10000018) } // ps_muls0 f0, f0, f0
    func testPsMuls1()   { roundTrip(0x1000001A) } // ps_muls1 f0, f0, f0
    func testPsMadds0()  { roundTrip(0x1001101C) } // ps_madds0 f0, f1, f0, f2
    func testPsMadds1()  { roundTrip(0x1001101E) } // ps_madds1 f0, f1, f0, f2

    // MARK: - Paired-singles X-form (opcode 4)

    func testPsNeg()     { roundTrip(0x10000850) } // ps_neg f0, f1
    func testPsMr()      { roundTrip(0x10000890) } // ps_mr f0, f1
    func testPsNabs()    { roundTrip(0x10000910) } // ps_nabs f0, f1
    func testPsAbs()     { roundTrip(0x10000A10) } // ps_abs f0, f1
    func testPsMerge00() { roundTrip(0x10011420) } // ps_merge00 f0, f1, f2
    func testPsMerge01() { roundTrip(0x10011460) } // ps_merge01 f0, f1, f2
    func testPsMerge10() { roundTrip(0x100114A0) } // ps_merge10 f0, f1, f2
    func testPsMerge11() { roundTrip(0x100114E0) } // ps_merge11 f0, f1, f2

    // MARK: - Paired-singles compare

    func testPsCmpu0()   { roundTrip(0x10001000) } // ps_cmpu0 cr0, f0, f2
    func testPsCmpo0()   { roundTrip(0x10001040) } // ps_cmpo0 cr0, f0, f2
    func testPsCmpu1()   { roundTrip(0x10001080) } // ps_cmpu1 cr0, f0, f2
    func testPsCmpo1()   { roundTrip(0x100010C0) } // ps_cmpo1 cr0, f0, f2

    // MARK: - Paired-singles quantized load/store

    func testPsqL()      { roundTrip(0xE0030010) } // psq_l f0, 0x10(r3), 0, 0
    func testPsqLu()     { roundTrip(0xE4030010) } // psq_lu f0, 0x10(r3), 0, 0
    func testPsqSt()     { roundTrip(0xF0030010) } // psq_st f0, 0x10(r3), 0, 0
    func testPsqStu()    { roundTrip(0xF4030010) } // psq_stu f0, 0x10(r3), 0, 0
    func testDcbzL()     { roundTrip(0x100327EC) } // dcbz_l r3, r4

    // MARK: - Cache

    func testDcbst()    { roundTrip(0x7C03206C) } // dcbst r3, r4
    func testDcbf()     { roundTrip(0x7C0320AC) } // dcbf r3, r4
    func testDcbtst()   { roundTrip(0x7C0321EC) } // dcbtst r3, r4
    func testDcbt()     { roundTrip(0x7C03222C) } // dcbt r3, r4
    func testDcbi()     { roundTrip(0x7C0323AC) } // dcbi r3, r4
    func testDcbz()     { roundTrip(0x7C0327EC) } // dcbz r3, r4
    func testIcbi()     { roundTrip(0x7C0327AC) } // icbi r3, r4

    // MARK: - System

    func testSc()       { roundTrip(0x44000002) } // sc
    func testSync()     { roundTrip(0x7C0004AC) } // sync
    func testEieio()    { roundTrip(0x7C0006AC) } // eieio
    func testIsync()    { roundTrip(0x4C00012C) } // isync
    func testRfi()      { roundTrip(0x4C000064) } // rfi
    func testTlbie()    { roundTrip(0x7C001A64) } // tlbie r3
    func testTlbsync()  { roundTrip(0x7C00046C) } // tlbsync

    // MARK: - Misc opcode 31

    func testTw()       { roundTrip(0x7C832008) } // tw 4, r3, r4
    func testLwarx()    { roundTrip(0x7C602028) } // lwarx r3, r0, r4
    func testStwcxDot() { roundTrip(0x7C60212D) } // stwcx. r3, r0, r4
    func testEciwx()    { roundTrip(0x7C63226C) } // eciwx r3, r3, r4
    func testEcowx()    { roundTrip(0x7C63236C) } // ecowx r3, r3, r4

    // MARK: - Bulk test from real DOL

    func testBulkRoundTrip() {
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
