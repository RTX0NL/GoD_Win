import Foundation

/// PowerPC 750CL instruction encoder. Inverse of PPCDecoder.
/// Given a mnemonic and operands, produces the 4-byte big-endian instruction word.
public struct PPCEncoder {

    public init() {}

    /// For branch instructions, `currentAddress` is needed to compute PC-relative offsets.
    public func encode(
        mnemonic: String,
        operands: [PPCInstruction.Operand],
        currentAddress: UInt32 = 0
    ) -> UInt32? {
        // Strip trailing dot for Rc variants
        let hasDot = mnemonic.hasSuffix(".") && mnemonic != "addic."
            && mnemonic != "andi." && mnemonic != "andis."
            && mnemonic != "stwcx."
        let baseMnemonic = hasDot ? String(mnemonic.dropLast()) : mnemonic
        let rc: UInt32 = hasDot ? 1 : 0

        switch baseMnemonic {
        // MARK: - Simplified mnemonics
        case "li":
            // li rD, SIMM → addi rD, 0, SIMM
            guard let rd = gpr(operands, 0), let imm = simm(operands, 1) else { return nil }
            return dForm(14, rd, 0, imm)
        case "lis":
            // lis rD, SIMM → addis rD, 0, SIMM
            guard let rd = gpr(operands, 0), let imm = simm(operands, 1) else { return nil }
            return dForm(15, rd, 0, imm)
        case "mr":
            // mr rA, rS → or rA, rS, rS
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1) else { return nil }
            return xForm(31, rs, ra, rs, 444) | rc
        case "not":
            // not rA, rS → nor rA, rS, rS
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1) else { return nil }
            return xForm(31, rs, ra, rs, 124) | rc
        case "nop":
            // nop → ori 0, 0, 0
            return dFormU(24, 0, 0, 0)

        // MARK: - Trap immediate
        case "twi":
            guard let to = uimm(operands, 0), let ra = gpr(operands, 1) else { return nil }
            // The parser classifies twi immediates as unsigned; the trap
            // value is a signed field, so accept either representation.
            guard let imm = simm(operands, 2) ?? uimm(operands, 2).map({ Int32(bitPattern: $0) }) else { return nil }
            return dForm(3, to, ra, imm)

        // MARK: - Simplified branch mnemonics
        case "blr":  return xlForm(19, 20, 0, 0, 16, 0)
        case "blrl": return xlForm(19, 20, 0, 0, 16, 1)
        case "bctr":  return xlForm(19, 20, 0, 0, 528, 0)
        case "bctrl": return xlForm(19, 20, 0, 0, 528, 1)

        // MARK: - Arithmetic immediate
        case "addi":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(14, rd, ra, imm)
        case "addis":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(15, rd, ra, imm)
        case "addic":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(12, rd, ra, imm)
        case "addic.":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(13, rd, ra, imm)
        case "subfic":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(8, rd, ra, imm)
        case "mulli":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1), let imm = simm(operands, 2) else { return nil }
            return dForm(7, rd, ra, imm)

        // MARK: - Compare immediate
        case "cmpwi":
            return encodeCmpi(operands, signed: true)
        case "cmplwi":
            return encodeCmpi(operands, signed: false)

        // MARK: - Logical immediate
        case "ori":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(24, rs, ra, imm)
        case "oris":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(25, rs, ra, imm)
        case "xori":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(26, rs, ra, imm)
        case "xoris":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(27, rs, ra, imm)
        case "andi.":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(28, rs, ra, imm)
        case "andis.":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let imm = uimm(operands, 2) else { return nil }
            return dFormU(29, rs, ra, imm)

        // MARK: - Branches
        case "b", "bl", "ba", "bla":
            return encodeBranch(mnemonic, operands, currentAddress)
        case "beq", "bne", "blt", "bge", "bgt", "ble", "bso", "bns",
             "beql", "bnel", "bltl", "bgel", "bgtl", "blel",
             "beqlr", "bnelr", "bltlr", "bgelr", "bgtlr", "blelr":
            return encodeCondBranch(mnemonic, operands, currentAddress)
        case "bdnz", "bdnzl", "bdz", "bdzl":
            return encodeCtrBranch(mnemonic, operands, currentAddress)
        case "bc", "bcl", "bca", "bcla":
            return encodeBc(mnemonic, operands, currentAddress)
        case "bclr", "bclrl":
            guard let bo = uimm(operands, 0), let bi = crBit(operands, 1) else { return nil }
            let lk: UInt32 = mnemonic.hasSuffix("l") ? 1 : 0
            return xlForm(19, UInt32(bo), UInt32(bi), 0, 16, lk)
        case "bcctr", "bcctrl":
            guard let bo = uimm(operands, 0), let bi = crBit(operands, 1) else { return nil }
            let lk: UInt32 = mnemonic.hasSuffix("l") ? 1 : 0
            return xlForm(19, UInt32(bo), UInt32(bi), 0, 528, lk)

        // MARK: - Load/store integer
        case "lwz":  return encodeDFormMem(32, operands)
        case "lwzu": return encodeDFormMem(33, operands)
        case "lbz":  return encodeDFormMem(34, operands)
        case "lbzu": return encodeDFormMem(35, operands)
        case "stw":  return encodeDFormMem(36, operands)
        case "stwu": return encodeDFormMem(37, operands)
        case "stb":  return encodeDFormMem(38, operands)
        case "stbu": return encodeDFormMem(39, operands)
        case "lhz":  return encodeDFormMem(40, operands)
        case "lhzu": return encodeDFormMem(41, operands)
        case "lha":  return encodeDFormMem(42, operands)
        case "lhau": return encodeDFormMem(43, operands)
        case "sth":  return encodeDFormMem(44, operands)
        case "sthu": return encodeDFormMem(45, operands)
        case "lmw":  return encodeDFormMem(46, operands)
        case "stmw": return encodeDFormMem(47, operands)

        // MARK: - Load/store float
        case "lfs":  return encodeDFormMemFpr(48, operands)
        case "lfsu": return encodeDFormMemFpr(49, operands)
        case "lfd":  return encodeDFormMemFpr(50, operands)
        case "lfdu": return encodeDFormMemFpr(51, operands)
        case "stfs": return encodeDFormMemFpr(52, operands)
        case "stfsu": return encodeDFormMemFpr(53, operands)
        case "stfd": return encodeDFormMemFpr(54, operands)
        case "stfdu": return encodeDFormMemFpr(55, operands)

        // MARK: - Opcode 31: ALU extended
        case "add":     return encodeXOForm(operands, xo: 266, oe: false, rc: rc)
        case "addo":    return encodeXOForm(operands, xo: 266, oe: true, rc: rc)
        case "addc":    return encodeXOForm(operands, xo: 10, oe: false, rc: rc)
        case "addco":   return encodeXOForm(operands, xo: 10, oe: true, rc: rc)
        case "adde":    return encodeXOForm(operands, xo: 138, oe: false, rc: rc)
        case "addeo":   return encodeXOForm(operands, xo: 138, oe: true, rc: rc)
        case "addme":   return encodeXOForm2(operands, xo: 234, oe: false, rc: rc)
        case "addmeo":  return encodeXOForm2(operands, xo: 234, oe: true, rc: rc)
        case "addze":   return encodeXOForm2(operands, xo: 202, oe: false, rc: rc)
        case "addzeo":  return encodeXOForm2(operands, xo: 202, oe: true, rc: rc)
        case "divw":    return encodeXOForm(operands, xo: 491, oe: false, rc: rc)
        case "divwo":   return encodeXOForm(operands, xo: 491, oe: true, rc: rc)
        case "divwu":   return encodeXOForm(operands, xo: 459, oe: false, rc: rc)
        case "divwuo":  return encodeXOForm(operands, xo: 459, oe: true, rc: rc)
        case "mulhw":   return encodeXOForm(operands, xo: 75, oe: false, rc: rc)
        case "mulhwu":  return encodeXOForm(operands, xo: 11, oe: false, rc: rc)
        case "mullw":   return encodeXOForm(operands, xo: 235, oe: false, rc: rc)
        case "mullwo":  return encodeXOForm(operands, xo: 235, oe: true, rc: rc)
        case "neg":     return encodeXOForm2(operands, xo: 104, oe: false, rc: rc)
        case "nego":    return encodeXOForm2(operands, xo: 104, oe: true, rc: rc)
        case "subf":    return encodeXOForm(operands, xo: 40, oe: false, rc: rc)
        case "subfo":   return encodeXOForm(operands, xo: 40, oe: true, rc: rc)
        case "subfc":   return encodeXOForm(operands, xo: 8, oe: false, rc: rc)
        case "subfco":  return encodeXOForm(operands, xo: 8, oe: true, rc: rc)
        case "subfe":   return encodeXOForm(operands, xo: 136, oe: false, rc: rc)
        case "subfeo":  return encodeXOForm(operands, xo: 136, oe: true, rc: rc)
        case "subfme":  return encodeXOForm2(operands, xo: 232, oe: false, rc: rc)
        case "subfmeo": return encodeXOForm2(operands, xo: 232, oe: true, rc: rc)
        case "subfze":  return encodeXOForm2(operands, xo: 200, oe: false, rc: rc)
        case "subfzeo": return encodeXOForm2(operands, xo: 200, oe: true, rc: rc)

        // Compare register
        case "cmpw":  return encodeCmpReg(operands, signed: true)
        case "cmplw": return encodeCmpReg(operands, signed: false)

        // Logical register (X-form: opcode 31, rS=rD, rA, rB)
        case "and":   return encodeXFormLogical(operands, xo: 28, rc: rc)
        case "andc":  return encodeXFormLogical(operands, xo: 60, rc: rc)
        case "or":    return encodeXFormLogical(operands, xo: 444, rc: rc)
        case "orc":   return encodeXFormLogical(operands, xo: 412, rc: rc)
        case "xor":   return encodeXFormLogical(operands, xo: 316, rc: rc)
        case "nor":   return encodeXFormLogical(operands, xo: 124, rc: rc)
        case "nand":  return encodeXFormLogical(operands, xo: 476, rc: rc)
        case "eqv":   return encodeXFormLogical(operands, xo: 284, rc: rc)

        // Shift
        case "slw":   return encodeXFormLogical(operands, xo: 24, rc: rc)
        case "srw":   return encodeXFormLogical(operands, xo: 536, rc: rc)
        case "sraw":  return encodeXFormLogical(operands, xo: 792, rc: rc)
        case "srawi":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let sh = shift(operands, 2) else { return nil }
            return xForm(31, rs, ra, UInt32(sh), 824) | rc

        // Sign extend
        case "extsb": return encodeXForm2(operands, xo: 954, rc: rc)
        case "extsh": return encodeXForm2(operands, xo: 922, rc: rc)
        case "cntlzw": return encodeXForm2(operands, xo: 26, rc: rc)

        // Load/store indexed (X-form: opcode 31)
        case "lwzx":  return encodeXFormIdx(operands, xo: 23)
        case "lwzux": return encodeXFormIdx(operands, xo: 55)
        case "lbzx":  return encodeXFormIdx(operands, xo: 87)
        case "lbzux": return encodeXFormIdx(operands, xo: 119)
        case "stwx":  return encodeXFormIdx(operands, xo: 151)
        case "stwux": return encodeXFormIdx(operands, xo: 183)
        case "stbx":  return encodeXFormIdx(operands, xo: 215)
        case "stbux": return encodeXFormIdx(operands, xo: 247)
        case "lhzx":  return encodeXFormIdx(operands, xo: 279)
        case "lhzux": return encodeXFormIdx(operands, xo: 311)
        case "lhax":  return encodeXFormIdx(operands, xo: 343)
        case "lhaux": return encodeXFormIdx(operands, xo: 375)
        case "sthx":  return encodeXFormIdx(operands, xo: 407)
        case "sthux": return encodeXFormIdx(operands, xo: 439)
        case "lwbrx": return encodeXFormIdx(operands, xo: 534)
        case "stwbrx": return encodeXFormIdx(operands, xo: 662)
        case "lhbrx": return encodeXFormIdx(operands, xo: 790)
        case "sthbrx": return encodeXFormIdx(operands, xo: 918)

        // Float indexed
        case "lfsx":  return encodeXFormIdxFpr(operands, xo: 535)
        case "lfsux": return encodeXFormIdxFpr(operands, xo: 567)
        case "lfdx":  return encodeXFormIdxFpr(operands, xo: 599)
        case "lfdux": return encodeXFormIdxFpr(operands, xo: 631)
        case "stfsx": return encodeXFormIdxFpr(operands, xo: 663)
        case "stfsux": return encodeXFormIdxFpr(operands, xo: 695)
        case "stfdx": return encodeXFormIdxFpr(operands, xo: 727)
        case "stfdux": return encodeXFormIdxFpr(operands, xo: 759)
        case "stfiwx": return encodeXFormIdxFpr(operands, xo: 983)

        // SPR
        case "mflr":
            guard let rd = gpr(operands, 0) else { return nil }
            return mfspr(rd, 8)
        case "mtlr":
            guard let rd = gpr(operands, 0) else { return nil }
            return mtspr(rd, 8)
        case "mfctr":
            guard let rd = gpr(operands, 0) else { return nil }
            return mfspr(rd, 9)
        case "mtctr":
            guard let rd = gpr(operands, 0) else { return nil }
            return mtspr(rd, 9)
        case "mfxer":
            guard let rd = gpr(operands, 0) else { return nil }
            return mfspr(rd, 1)
        case "mtxer":
            guard let rd = gpr(operands, 0) else { return nil }
            return mtspr(rd, 1)
        case "mfspr":
            guard let rd = gpr(operands, 0), let spr = sprNum(operands, 1) else { return nil }
            return mfspr(rd, spr)
        case "mtspr":
            guard let spr = sprNum(operands, 0), let rd = gpr(operands, 1) else { return nil }
            return mtspr(rd, spr)
        case "mfcr":
            guard let rd = gpr(operands, 0) else { return nil }
            return xForm(31, rd, 0, 0, 19)
        case "mtcrf":
            guard let crm = uimm(operands, 0), let rs = gpr(operands, 1) else { return nil }
            return (31 << 26) | (UInt32(rs) << 21) | ((crm & 0xFF) << 12) | (144 << 1)
        case "mfmsr":
            guard let rd = gpr(operands, 0) else { return nil }
            return xForm(31, rd, 0, 0, 83)
        case "mtmsr":
            guard let rd = gpr(operands, 0) else { return nil }
            return xForm(31, rd, 0, 0, 146)

        // Rotate/mask
        case "rlwinm":
            return encodeRlwinm(operands, rc: rc)
        case "rlwimi":
            return encodeRlwimi(operands, rc: rc)
        case "rlwnm":
            return encodeRlwnm(operands, rc: rc)
        case "slwi":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let sh = shift(operands, 2) else { return nil }
            return mForm(21, rs, ra, UInt32(sh), 0, UInt32(31 - sh)) | rc
        case "srwi":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let sh = shift(operands, 2) else { return nil }
            return mForm(21, rs, ra, UInt32(32 - sh), UInt32(sh), 31) | rc
        case "clrlwi":
            guard let ra = gpr(operands, 0), let rs = gpr(operands, 1), let mb = shift(operands, 2) else { return nil }
            return mForm(21, rs, ra, 0, UInt32(mb), 31) | rc

        // Cache
        case "dcbst": return encodeCacheOp(operands, xo: 54)
        case "dcbf":  return encodeCacheOp(operands, xo: 86)
        case "dcbtst": return encodeCacheOp(operands, xo: 246)
        case "dcbt":  return encodeCacheOp(operands, xo: 278)
        case "dcbi":  return encodeCacheOp(operands, xo: 470)
        case "dcbz":  return encodeCacheOp(operands, xo: 1014)
        case "icbi":  return encodeCacheOp(operands, xo: 982)

        // System
        case "sc":   return (17 << 26) | (1 << 1)
        case "sync": return xForm(31, 0, 0, 0, 598)
        case "eieio": return xForm(31, 0, 0, 0, 854)
        case "isync": return xlForm(19, 0, 0, 0, 150, 0)
        case "rfi":   return xlForm(19, 0, 0, 0, 50, 0)

        // Load/store string
        case "lswi":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1) else { return nil }
            let nb: UInt32 = operands.count > 2 ? (count(operands, 2).map { UInt32($0) } ?? 0) : 0
            return xForm(31, rd, ra, nb, 533)
        case "lswx":  return encodeXFormIdx(operands, xo: 597)
        case "stswi":
            guard let rd = gpr(operands, 0), let ra = gpr(operands, 1) else { return nil }
            let nb: UInt32 = operands.count > 2 ? (count(operands, 2).map { UInt32($0) } ?? 0) : 0
            return xForm(31, rd, ra, nb, 661)
        case "stswx": return encodeXFormIdx(operands, xo: 725)

        // External control
        case "eciwx":  return encodeXFormIdx(operands, xo: 310)
        case "ecowx":  return encodeXFormIdx(operands, xo: 438)

        // Misc opcode 31
        case "lwarx":   return encodeXFormIdx(operands, xo: 20)
        case "stwcx.":
            guard let base = encodeXFormIdx(operands, xo: 150) else { return nil }
            return base | 1

        // CR operations (opcode 19)
        case "mcrf":
            guard let crfD = crField(operands, 0), let crfS = crField(operands, 1) else { return nil }
            return xlForm(19, UInt32(crfD) << 2, UInt32(crfS) << 2, 0, 0, 0)
        case "crnor":  return encodeCrOp(operands, xo: 33)
        case "crandc": return encodeCrOp(operands, xo: 129)
        case "crxor":  return encodeCrOp(operands, xo: 193)
        case "crnand": return encodeCrOp(operands, xo: 225)
        case "crand":  return encodeCrOp(operands, xo: 257)
        case "creqv":  return encodeCrOp(operands, xo: 289)
        case "crorc":  return encodeCrOp(operands, xo: 417)
        case "cror":   return encodeCrOp(operands, xo: 449)

        // MARK: - Float single (opcode 59)
        case "fdivs":  return encodeAForm3(59, operands, xo: 18, rc: rc)
        case "fsubs":  return encodeAForm3(59, operands, xo: 20, rc: rc)
        case "fadds":  return encodeAForm3(59, operands, xo: 21, rc: rc)
        case "fmuls":  return encodeAFormMul(59, operands, xo: 25, rc: rc)
        case "fsqrts": return encodeAForm2(59, operands, xo: 22, rc: rc)
        case "fres":   return encodeAForm2(59, operands, xo: 24, rc: rc)
        case "fmsubs": return encodeAForm4(59, operands, xo: 28, rc: rc)
        case "fmadds": return encodeAForm4(59, operands, xo: 29, rc: rc)
        case "fnmsubs": return encodeAForm4(59, operands, xo: 30, rc: rc)
        case "fnmadds": return encodeAForm4(59, operands, xo: 31, rc: rc)

        // MARK: - Float double (opcode 63)
        case "fdiv":   return encodeAForm3(63, operands, xo: 18, rc: rc)
        case "fsub":   return encodeAForm3(63, operands, xo: 20, rc: rc)
        case "fadd":   return encodeAForm3(63, operands, xo: 21, rc: rc)
        case "fmul":   return encodeAFormMul(63, operands, xo: 25, rc: rc)
        case "fsqrt":  return encodeAForm2(63, operands, xo: 22, rc: rc)
        case "frsqrte": return encodeAForm2(63, operands, xo: 26, rc: rc)
        case "fsel":   return encodeAForm4(63, operands, xo: 23, rc: rc)
        case "fmsub":  return encodeAForm4(63, operands, xo: 28, rc: rc)
        case "fmadd":  return encodeAForm4(63, operands, xo: 29, rc: rc)
        case "fnmsub": return encodeAForm4(63, operands, xo: 30, rc: rc)
        case "fnmadd": return encodeAForm4(63, operands, xo: 31, rc: rc)

        // Float X-form (opcode 63)
        case "fcmpu":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(63, UInt32(crf) << 2, fa, fb, 0)
        case "fcmpo":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(63, UInt32(crf) << 2, fa, fb, 32)
        case "fmr":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 72) | rc
        case "fneg":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 40) | rc
        case "fabs":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 264) | rc
        case "fnabs":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 136) | rc
        case "frsp":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 12) | rc
        case "fctiw":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 14) | rc
        case "fctiwz":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(63, fd, 0, fb, 15) | rc
        case "mtfsb0":
            guard let bt = crBit(operands, 0) else { return nil }
            return xForm(63, UInt32(bt), 0, 0, 70) | rc
        case "mtfsb1":
            guard let bt = crBit(operands, 0) else { return nil }
            return xForm(63, UInt32(bt), 0, 0, 38) | rc
        case "mcrfs":
            guard let crfD = crField(operands, 0), let crfS = crField(operands, 1) else { return nil }
            return xForm(63, UInt32(crfD) << 2, UInt32(crfS) << 2, 0, 64)
        case "mtfsfi":
            guard let crf = crField(operands, 0), let imm = uimm(operands, 1) else { return nil }
            return (63 << 26) | (UInt32(crf) << 23) | ((imm & 0xF) << 12) | (134 << 1) | rc
        case "mffs":
            guard let fd = fpr(operands, 0) else { return nil }
            return xForm(63, fd, 0, 0, 583) | rc
        case "mtfsf":
            guard let fm = uimm(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return (63 << 26) | ((fm & 0xFF) << 17) | (UInt32(fb) << 11) | (711 << 1) | rc

        // MARK: - Paired-singles (opcode 4)
        case "ps_div":  return encodeAForm3(4, operands, xo: 18, rc: rc)
        case "ps_sub":  return encodeAForm3(4, operands, xo: 20, rc: rc)
        case "ps_add":  return encodeAForm3(4, operands, xo: 21, rc: rc)
        case "ps_mul":  return encodeAFormMul(4, operands, xo: 25, rc: rc)
        case "ps_res":  return encodeAForm2(4, operands, xo: 24, rc: rc)
        case "ps_rsqrte": return encodeAForm2(4, operands, xo: 26, rc: rc)
        case "ps_sel":  return encodeAForm4(4, operands, xo: 23, rc: rc)
        case "ps_msub": return encodeAForm4(4, operands, xo: 28, rc: rc)
        case "ps_madd": return encodeAForm4(4, operands, xo: 29, rc: rc)
        case "ps_nmsub": return encodeAForm4(4, operands, xo: 30, rc: rc)
        case "ps_nmadd": return encodeAForm4(4, operands, xo: 31, rc: rc)
        case "ps_sum0": return encodeAForm4(4, operands, xo: 10, rc: rc)
        case "ps_sum1": return encodeAForm4(4, operands, xo: 11, rc: rc)
        case "ps_muls0": return encodeAFormMul(4, operands, xo: 12, rc: rc)
        case "ps_muls1": return encodeAFormMul(4, operands, xo: 13, rc: rc)
        case "ps_madds0": return encodeAForm4(4, operands, xo: 14, rc: rc)
        case "ps_madds1": return encodeAForm4(4, operands, xo: 15, rc: rc)

        case "ps_neg":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(4, fd, 0, fb, 40) | rc
        case "ps_mr":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(4, fd, 0, fb, 72) | rc
        case "ps_nabs":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(4, fd, 0, fb, 136) | rc
        case "ps_abs":
            guard let fd = fpr(operands, 0), let fb = fpr(operands, 1) else { return nil }
            return xForm(4, fd, 0, fb, 264) | rc
        case "ps_merge00":
            guard let fd = fpr(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, fd, fa, fb, 528) | rc
        case "ps_merge01":
            guard let fd = fpr(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, fd, fa, fb, 560) | rc
        case "ps_merge10":
            guard let fd = fpr(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, fd, fa, fb, 592) | rc
        case "ps_merge11":
            guard let fd = fpr(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, fd, fa, fb, 624) | rc

        // PS compare
        case "ps_cmpu0":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, UInt32(crf) << 2, fa, fb, 0)
        case "ps_cmpo0":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, UInt32(crf) << 2, fa, fb, 32)
        case "ps_cmpu1":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, UInt32(crf) << 2, fa, fb, 64)
        case "ps_cmpo1":
            guard let crf = crField(operands, 0), let fa = fpr(operands, 1), let fb = fpr(operands, 2) else { return nil }
            return xForm(4, UInt32(crf) << 2, fa, fb, 96)

        // PS quantized load/store
        case "psq_l":  return encodePsq(56, operands)
        case "psq_lu": return encodePsq(57, operands)
        case "psq_st": return encodePsq(60, operands)
        case "psq_stu": return encodePsq(61, operands)

        // PS indexed load/store (opcode 4, X-form with W and I fields)
        case "psq_lx", "psq_stx", "psq_lux", "psq_stux":
            return encodePsqIndexed(baseMnemonic, operands)

        case "dcbz_l":
            guard let ra = gpr(operands, 0), let rb = gpr(operands, 1) else { return nil }
            return xForm(4, 0, ra, rb, 1014)

        // Segment registers
        case "mfsr":
            guard let rd = gpr(operands, 0), let sr = uimm(operands, 1) else { return nil }
            return xForm(31, rd, sr & 0xF, 0, 595)
        case "mfsrin":
            guard let rd = gpr(operands, 0), let rb = gpr(operands, 1) else { return nil }
            return xForm(31, rd, 0, rb, 659)
        case "mtsr":
            guard let sr = uimm(operands, 0), let rs = gpr(operands, 1) else { return nil }
            return xForm(31, rs, sr & 0xF, 0, 210)
        case "mtsrin":
            guard let rs = gpr(operands, 0), let rb = gpr(operands, 1) else { return nil }
            return xForm(31, rs, 0, rb, 242)

        // Move to CR from XER
        case "mcrxr":
            guard let crf = crField(operands, 0) else { return nil }
            return xForm(31, UInt32(crf) << 2, 0, 0, 512)

        // Move from Time Base (same encoding as mfspr but XO=371)
        case "mftb":
            guard let rd = gpr(operands, 0), let tbr = sprNum(operands, 1) else { return nil }
            let tbrLo = tbr & 0x1F
            let tbrHi = (tbr >> 5) & 0x1F
            return (31 << 26) | (rd << 21) | (tbrLo << 16) | (tbrHi << 11) | (371 << 1)

        // TLB
        case "tlbie":
            guard let rb = gpr(operands, 0) else { return nil }
            return xForm(31, 0, 0, rb, 306)
        case "tlbsync": return xForm(31, 0, 0, 0, 566)

        // Trap
        case "tw":
            guard let to = uimm(operands, 0), let ra = gpr(operands, 1), let rb = gpr(operands, 2) else { return nil }
            return xForm(31, to, ra, rb, 4)

        default:
            return nil
        }
    }
}

// MARK: - Instruction format builders

private extension PPCEncoder {
    /// D-form: opcode(6) + rD(5) + rA(5) + d/SIMM/UIMM(16)
    func dForm(_ opcode: UInt32, _ rd: UInt32, _ ra: UInt32, _ imm: Int32) -> UInt32 {
        (opcode << 26) | (rd << 21) | (ra << 16) | UInt32(UInt16(bitPattern: Int16(imm)))
    }

    func dFormU(_ opcode: UInt32, _ rd: UInt32, _ ra: UInt32, _ imm: UInt32) -> UInt32 {
        (opcode << 26) | (rd << 21) | (ra << 16) | (imm & 0xFFFF)
    }

    /// X-form: opcode(6) + rS/rD(5) + rA(5) + rB(5) + XO(10) + Rc(1)
    func xForm(_ opcode: UInt32, _ rd: UInt32, _ ra: UInt32, _ rb: UInt32, _ xo: UInt32) -> UInt32 {
        (opcode << 26) | (rd << 21) | (ra << 16) | (rb << 11) | (xo << 1)
    }

    /// XL-form: opcode(6) + BO/BT(5) + BI/BA(5) + BB(5) + XO(10) + LK(1)
    func xlForm(_ opcode: UInt32, _ bo: UInt32, _ bi: UInt32, _ bb: UInt32, _ xo: UInt32, _ lk: UInt32) -> UInt32 {
        (opcode << 26) | (bo << 21) | (bi << 16) | (bb << 11) | (xo << 1) | lk
    }

    /// M-form: opcode(6) + rS(5) + rA(5) + SH(5) + MB(5) + ME(5) + Rc(1)
    func mForm(_ opcode: UInt32, _ rs: UInt32, _ ra: UInt32, _ sh: UInt32, _ mb: UInt32, _ me: UInt32) -> UInt32 {
        (opcode << 26) | (rs << 21) | (ra << 16) | (sh << 11) | (mb << 6) | (me << 1)
    }

    func mfspr(_ rd: UInt32, _ spr: UInt32) -> UInt32 {
        let sprLo = spr & 0x1F
        let sprHi = (spr >> 5) & 0x1F
        return (31 << 26) | (rd << 21) | (sprLo << 16) | (sprHi << 11) | (339 << 1)
    }

    func mtspr(_ rs: UInt32, _ spr: UInt32) -> UInt32 {
        let sprLo = spr & 0x1F
        let sprHi = (spr >> 5) & 0x1F
        return (31 << 26) | (rs << 21) | (sprLo << 16) | (sprHi << 11) | (467 << 1)
    }
}

// MARK: - Operand extractors

private extension PPCEncoder {
    func gpr(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt32? {
        guard idx < ops.count, case .gpr(let r) = ops[idx] else { return nil }
        return UInt32(r)
    }

    func fpr(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt32? {
        guard idx < ops.count else { return nil }
        switch ops[idx] {
        case .fpr(let r): return UInt32(r)
        case .ps(let r): return UInt32(r)
        default: return nil
        }
    }

    func simm(_ ops: [PPCInstruction.Operand], _ idx: Int) -> Int32? {
        guard idx < ops.count, case .simm(let v) = ops[idx] else { return nil }
        return v
    }

    func uimm(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt32? {
        guard idx < ops.count, case .uimm(let v) = ops[idx] else { return nil }
        return v
    }

    func shift(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .shift(let v) = ops[idx] else { return nil }
        return v
    }

    func maskBegin(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .maskBegin(let v) = ops[idx] else { return nil }
        return v
    }

    func maskEnd(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .maskEnd(let v) = ops[idx] else { return nil }
        return v
    }

    func crField(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .crField(let v) = ops[idx] else { return nil }
        return v
    }

    func crBit(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .crBit(let v) = ops[idx] else { return nil }
        return v
    }

    func branchTarget(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt32? {
        guard idx < ops.count, case .branchTarget(let v) = ops[idx] else { return nil }
        return v
    }

    func mem(_ ops: [PPCInstruction.Operand], _ idx: Int) -> (Int16, UInt8)? {
        guard idx < ops.count, case .memory(let off, let base) = ops[idx] else { return nil }
        return (off, base)
    }

    func sprNum(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt32? {
        guard idx < ops.count, case .spr(let v) = ops[idx] else { return nil }
        return v
    }
}

// MARK: - Compound encoding helpers

private extension PPCEncoder {
    func encodeDFormMem(_ opcode: UInt32, _ ops: [PPCInstruction.Operand]) -> UInt32? {
        guard let rd = gpr(ops, 0), let (offset, base) = mem(ops, 1) else { return nil }
        return dForm(opcode, rd, UInt32(base), Int32(offset))
    }

    func encodeDFormMemFpr(_ opcode: UInt32, _ ops: [PPCInstruction.Operand]) -> UInt32? {
        guard let fd = fpr(ops, 0), let (offset, base) = mem(ops, 1) else { return nil }
        return dForm(opcode, fd, UInt32(base), Int32(offset))
    }

    // XO-form: rD, rA, rB
    func encodeXOForm(_ ops: [PPCInstruction.Operand], xo: UInt32, oe: Bool, rc: UInt32) -> UInt32? {
        guard let rd = gpr(ops, 0), let ra = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
        let oeBit: UInt32 = oe ? (1 << 10) : 0
        return (31 << 26) | (rd << 21) | (ra << 16) | (rb << 11) | oeBit | (xo << 1) | rc
    }

    // XO-form 2-register: rD, rA (no rB)
    func encodeXOForm2(_ ops: [PPCInstruction.Operand], xo: UInt32, oe: Bool, rc: UInt32) -> UInt32? {
        guard let rd = gpr(ops, 0), let ra = gpr(ops, 1) else { return nil }
        let oeBit: UInt32 = oe ? (1 << 10) : 0
        return (31 << 26) | (rd << 21) | (ra << 16) | oeBit | (xo << 1) | rc
    }

    // X-form logical: rA, rS, rB (note: rS is encoded in rD position)
    func encodeXFormLogical(_ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rs = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
        return xForm(31, rs, ra, rb, xo) | rc
    }

    // X-form 2-register: rA, rS
    func encodeXForm2(_ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rs = gpr(ops, 1) else { return nil }
        return xForm(31, rs, ra, 0, xo) | rc
    }

    // X-form indexed: rD, rA, rB
    func encodeXFormIdx(_ ops: [PPCInstruction.Operand], xo: UInt32) -> UInt32? {
        guard let rd = gpr(ops, 0), let ra = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
        return xForm(31, rd, ra, rb, xo)
    }

    func encodeXFormIdxFpr(_ ops: [PPCInstruction.Operand], xo: UInt32) -> UInt32? {
        guard let fd = fpr(ops, 0), let ra = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
        return xForm(31, fd, ra, rb, xo)
    }

    // A-form: frD, frA, frB (3 operand, frC=0)
    func encodeAForm3(_ opcode: UInt32, _ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let fd = fpr(ops, 0), let fa = fpr(ops, 1), let fb = fpr(ops, 2) else { return nil }
        return (opcode << 26) | (fd << 21) | (fa << 16) | (fb << 11) | (xo << 1) | rc
    }

    // A-form: frD, frB (2 operand, frA=0, frC=0)
    func encodeAForm2(_ opcode: UInt32, _ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let fd = fpr(ops, 0), let fb = fpr(ops, 1) else { return nil }
        return (opcode << 26) | (fd << 21) | (fb << 11) | (xo << 1) | rc
    }

    // A-form multiply: frD, frA, frC (frB=0)
    func encodeAFormMul(_ opcode: UInt32, _ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let fd = fpr(ops, 0), let fa = fpr(ops, 1), let fc = fpr(ops, 2) else { return nil }
        return (opcode << 26) | (fd << 21) | (fa << 16) | (fc << 6) | (xo << 1) | rc
    }

    // A-form 4 operand: frD, frA, frC, frB
    func encodeAForm4(_ opcode: UInt32, _ ops: [PPCInstruction.Operand], xo: UInt32, rc: UInt32) -> UInt32? {
        guard let fd = fpr(ops, 0), let fa = fpr(ops, 1), let fc = fpr(ops, 2), let fb = fpr(ops, 3) else { return nil }
        return (opcode << 26) | (fd << 21) | (fa << 16) | (fb << 11) | (fc << 6) | (xo << 1) | rc
    }

    func encodeCacheOp(_ ops: [PPCInstruction.Operand], xo: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rb = gpr(ops, 1) else { return nil }
        return xForm(31, 0, ra, rb, xo)
    }

    func encodeCrOp(_ ops: [PPCInstruction.Operand], xo: UInt32) -> UInt32? {
        guard let bt = crBit(ops, 0), let ba = crBit(ops, 1), let bb = crBit(ops, 2) else { return nil }
        return xlForm(19, UInt32(bt), UInt32(ba), UInt32(bb), xo, 0)
    }

    func encodeRlwinm(_ ops: [PPCInstruction.Operand], rc: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rs = gpr(ops, 1), let sh = shift(ops, 2),
              let mb = maskBegin(ops, 3), let me = maskEnd(ops, 4) else { return nil }
        return mForm(21, rs, ra, UInt32(sh), UInt32(mb), UInt32(me)) | rc
    }

    func encodeRlwimi(_ ops: [PPCInstruction.Operand], rc: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rs = gpr(ops, 1), let sh = shift(ops, 2),
              let mb = maskBegin(ops, 3), let me = maskEnd(ops, 4) else { return nil }
        return mForm(20, rs, ra, UInt32(sh), UInt32(mb), UInt32(me)) | rc
    }

    func encodeRlwnm(_ ops: [PPCInstruction.Operand], rc: UInt32) -> UInt32? {
        guard let ra = gpr(ops, 0), let rs = gpr(ops, 1), let rb = gpr(ops, 2),
              let mb = maskBegin(ops, 3), let me = maskEnd(ops, 4) else { return nil }
        return mForm(23, rs, ra, rb, UInt32(mb), UInt32(me)) | rc
    }

    func encodeCmpi(_ ops: [PPCInstruction.Operand], signed: Bool) -> UInt32? {
        let opcode: UInt32 = signed ? 11 : 10
        // cmpwi [crN,] rA, SIMM  or  cmplwi [crN,] rA, UIMM
        if ops.count == 2 {
            guard let ra = gpr(ops, 0) else { return nil }
            if signed {
                guard let imm = simm(ops, 1) else { return nil }
                return dForm(opcode, 0, ra, imm)
            } else {
                guard let imm = uimm(ops, 1) else { return nil }
                return dFormU(opcode, 0, ra, imm)
            }
        } else if ops.count == 3 {
            guard let crf = crField(ops, 0), let ra = gpr(ops, 1) else { return nil }
            if signed {
                guard let imm = simm(ops, 2) else { return nil }
                return dForm(opcode, UInt32(crf) << 2, ra, imm)
            } else {
                guard let imm = uimm(ops, 2) else { return nil }
                return dFormU(opcode, UInt32(crf) << 2, ra, imm)
            }
        }
        return nil
    }

    func encodeCmpReg(_ ops: [PPCInstruction.Operand], signed: Bool) -> UInt32? {
        let xo: UInt32 = signed ? 0 : 32
        if ops.count == 2 {
            guard let ra = gpr(ops, 0), let rb = gpr(ops, 1) else { return nil }
            return xForm(31, 0, ra, rb, xo)
        } else if ops.count == 3 {
            guard let crf = crField(ops, 0), let ra = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
            return xForm(31, UInt32(crf) << 2, ra, rb, xo)
        }
        return nil
    }

    func encodeBranch(_ mnemonic: String, _ ops: [PPCInstruction.Operand], _ pc: UInt32) -> UInt32? {
        guard let target = branchTarget(ops, 0) else { return nil }
        let lk: UInt32 = (mnemonic == "bl" || mnemonic == "bla") ? 1 : 0
        let aa: UInt32 = (mnemonic == "ba" || mnemonic == "bla") ? 1 : 0
        let offset: Int32
        if aa != 0 {
            offset = Int32(bitPattern: target)
        } else {
            offset = Int32(bitPattern: target) &- Int32(bitPattern: pc)
        }
        let li = UInt32(bitPattern: offset >> 2) & 0x00FFFFFF
        return (18 << 26) | (li << 2) | (aa << 1) | lk
    }

    func encodeCondBranch(_ mnemonic: String, _ ops: [PPCInstruction.Operand], _ pc: UInt32) -> UInt32? {
        // Parse mnemonic: b{cond}[lr][l]
        // Must extract condition name, LR flag, and link flag carefully
        var m = mnemonic
        let isLR = m.hasSuffix("lr") || m.hasSuffix("lrl")
        if m.hasSuffix("lrl") { m = String(m.dropLast(3)) }
        else if m.hasSuffix("lr") { m = String(m.dropLast(2)) }
        let isLink = m.hasSuffix("l") && m != "bl"
        if isLink && m.count > 2 { m = String(m.dropLast()) }
        let base = m

        let bo: UInt32
        let crBitOffset: UInt32
        switch base {
        case "blt": bo = 12; crBitOffset = 0
        case "bgt": bo = 12; crBitOffset = 1
        case "beq": bo = 12; crBitOffset = 2
        case "bso": bo = 12; crBitOffset = 3
        case "bge": bo = 4; crBitOffset = 0
        case "ble": bo = 4; crBitOffset = 1
        case "bne": bo = 4; crBitOffset = 2
        case "bns": bo = 4; crBitOffset = 3
        default: return nil
        }

        var crField: UInt32 = 0
        var targetIdx = 0
        if let crf = self.crField(ops, 0) {
            crField = UInt32(crf)
            targetIdx = 1
        }
        let bi = crField * 4 + crBitOffset

        if isLR {
            let lk: UInt32 = isLink ? 1 : 0
            return xlForm(19, bo, bi, 0, 16, lk)
        } else {
            guard let target = branchTarget(ops, targetIdx) else { return nil }
            let offset = Int32(bitPattern: target) &- Int32(bitPattern: pc)
            let bd = UInt32(bitPattern: offset >> 2) & 0x3FFF
            let lk: UInt32 = isLink ? 1 : 0
            return (16 << 26) | (bo << 21) | (bi << 16) | (bd << 2) | lk
        }
    }

    func encodeCtrBranch(_ mnemonic: String, _ ops: [PPCInstruction.Operand], _ pc: UInt32) -> UInt32? {
        // BO encodings (no condition test, no hint):
        //   `bdnz` decrements CTR + branches if CTR != 0 → BO = 16
        //   `bdz`  decrements CTR + branches if CTR == 0 → BO = 24
        // Hinted forms (BO=18 / BO=26) come through `encodeBc` as
        // explicit `bc BO,BI,target` so we don't need to handle them
        // here.
        let bo: UInt32 = mnemonic.hasPrefix("bdnz") ? 16 : 24
        let lk: UInt32 = mnemonic.hasSuffix("l") ? 1 : 0
        guard let target = branchTarget(ops, 0) else { return nil }
        let offset = Int32(bitPattern: target) &- Int32(bitPattern: pc)
        let bd = UInt32(bitPattern: offset >> 2) & 0x3FFF
        return (16 << 26) | (bo << 21) | (bd << 2) | lk
    }

    func encodeBc(_ mnemonic: String, _ ops: [PPCInstruction.Operand], _ pc: UInt32) -> UInt32? {
        guard let bo = uimm(ops, 0), let bi = crBit(ops, 1), let target = branchTarget(ops, 2) else { return nil }
        let lk: UInt32 = mnemonic.contains("l") ? 1 : 0
        let aa: UInt32 = mnemonic.contains("a") ? 1 : 0
        let offset: Int32
        if aa != 0 {
            offset = Int32(bitPattern: target)
        } else {
            offset = Int32(bitPattern: target) &- Int32(bitPattern: pc)
        }
        let bd = UInt32(bitPattern: offset >> 2) & 0x3FFF
        return (16 << 26) | (bo << 21) | (UInt32(bi) << 16) | (bd << 2) | (aa << 1) | lk
    }

    func count(_ ops: [PPCInstruction.Operand], _ idx: Int) -> UInt8? {
        guard idx < ops.count, case .count(let v) = ops[idx] else { return nil }
        return v
    }

    func encodePsqIndexed(_ mnemonic: String, _ ops: [PPCInstruction.Operand]) -> UInt32? {
        guard let fd = fpr(ops, 0), let ra = gpr(ops, 1), let rb = gpr(ops, 2) else { return nil }
        var w: UInt32 = 0
        var i: UInt32 = 0
        if ops.count > 3, case .wBit(let wVal) = ops[3] { w = UInt32(wVal) }
        if ops.count > 4, case .gqr(let iVal) = ops[4] { i = UInt32(iVal) }
        let xo: UInt32
        switch mnemonic {
        case "psq_lx":  xo = 6
        case "psq_stx": xo = 7
        case "psq_lux": xo = 38
        case "psq_stux": xo = 39
        default: return nil
        }
        return (4 << 26) | (fd << 21) | (ra << 16) | (rb << 11) | (w << 10) | (i << 7) | (xo << 1)
    }

    func encodePsq(_ opcode: UInt32, _ ops: [PPCInstruction.Operand]) -> UInt32? {
        guard let fd = fpr(ops, 0), let (offset, base) = mem(ops, 1) else { return nil }
        // The displacement field is only 12 bits — refuse offsets that
        // don't fit rather than silently truncating (a shifted @l reloc
        // that overflows must surface as an encoding error).
        guard offset >= -0x800 && offset <= 0x7FF else { return nil }
        var w: UInt32 = 0
        var i: UInt32 = 0
        if ops.count > 2, case .wBit(let wVal) = ops[2] { w = UInt32(wVal) }
        if ops.count > 3, case .gqr(let iVal) = ops[3] { i = UInt32(iVal) }
        let d12 = UInt32(UInt16(bitPattern: Int16(offset))) & 0xFFF
        return (opcode << 26) | (fd << 21) | (UInt32(base) << 16) | (w << 15) | (i << 12) | d12
    }
}
