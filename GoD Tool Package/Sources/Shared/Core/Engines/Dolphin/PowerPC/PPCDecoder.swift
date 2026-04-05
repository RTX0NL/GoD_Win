import Foundation

/// Table-driven PowerPC 750CL (Gekko/Broadway) instruction decoder.
/// Decodes all standard PPC, FPU, and paired-singles instructions.
public struct PPCDecoder {

    public init() {}

    /// Decode a single 32-bit instruction word at the given RAM address
    public func decode(_ raw: UInt32, at address: UInt32) -> PPCInstruction {
        let decoded = decodeInstruction(raw, at: address)
        return PPCInstruction(address: address, raw: raw, decoded: decoded)
    }

    /// Decode all instructions in a data buffer starting at baseAddress
    public func decodeAll(_ data: [UInt8], baseAddress: UInt32) -> [PPCInstruction] {
        var instructions = [PPCInstruction]()
        instructions.reserveCapacity(data.count / 4)
        var offset = 0
        while offset + 3 < data.count {
            let raw = UInt32(data[offset]) << 24
                    | UInt32(data[offset + 1]) << 16
                    | UInt32(data[offset + 2]) << 8
                    | UInt32(data[offset + 3])
            let address = baseAddress + UInt32(offset)
            instructions.append(decode(raw, at: address))
            offset += 4
        }
        return instructions
    }
}

// MARK: - Bit extraction helpers

private extension UInt32 {
    /// Extract bits [hi..lo] (PPC big-endian bit numbering: bit 0 is MSB)
    func bits(_ hi: Int, _ lo: Int) -> UInt32 {
        let shift = 31 - lo
        let mask: UInt32 = (1 << (lo - hi + 1)) - 1
        return (self >> shift) & mask
    }

    func bit(_ n: Int) -> UInt32 {
        bits(n, n)
    }

    /// Sign-extend a value of the given bit width to Int32
    func signExtend(from width: Int) -> Int32 {
        let shift = 32 - width
        return Int32(bitPattern: self << shift) >> shift
    }
}

// MARK: - Field extraction

private extension PPCDecoder {
    typealias D = PPCInstruction.Decoded
    typealias Op = PPCInstruction.Operand

    // Common field positions
    static func rD(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(6, 10)) }
    static func rA(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(11, 15)) }
    static func rB(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(16, 20)) }
    static func rC(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(21, 25)) }
    static func simm(_ raw: UInt32) -> Int32 { raw.bits(16, 31).signExtend(from: 16) }
    static func uimm(_ raw: UInt32) -> UInt32 { raw.bits(16, 31) }
    static func sh(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(16, 20)) }
    static func mb(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(21, 25)) }
    static func me(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(26, 30)) }
    static func rc(_ raw: UInt32) -> Bool { raw.bit(31) != 0 }
    static func oe(_ raw: UInt32) -> Bool { raw.bit(21) != 0 }
    static func lk(_ raw: UInt32) -> Bool { raw.bit(31) != 0 }
    static func aa(_ raw: UInt32) -> Bool { raw.bit(30) != 0 }
    static func bo(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(6, 10)) }
    static func bi(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(11, 15)) }
    static func crfD(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(6, 8)) }
    static func crfS(_ raw: UInt32) -> UInt8 { UInt8(raw.bits(11, 13)) }

    static func spr(_ raw: UInt32) -> UInt32 {
        // SPR field is split and swapped: spr[5:9] || spr[0:4]
        let lo = raw.bits(16, 20)
        let hi = raw.bits(11, 15)
        return (lo << 5) | hi
    }
}

// MARK: - Primary dispatch

private extension PPCDecoder {
    func decodeInstruction(_ raw: UInt32, at pc: UInt32) -> D? {
        let opcode = raw.bits(0, 5)
        switch opcode {
        // Paired-singles (Gekko-specific)
        case 4:  return decodeOpcode4(raw, pc)

        // Integer arithmetic immediate
        case 7:  return D(mnemonic: "mulli", operands: [.gpr(Self.rD(raw)), .gpr(Self.rA(raw)), .simm(Self.simm(raw))])
        case 8:  return D(mnemonic: "subfic", operands: [.gpr(Self.rD(raw)), .gpr(Self.rA(raw)), .simm(Self.simm(raw))])

        // Compare immediate
        case 10: return decodeCmpi(raw, signed: false)  // cmpli
        case 11: return decodeCmpi(raw, signed: true)   // cmpi

        // Arithmetic immediate
        case 12: return D(mnemonic: "addic", operands: [.gpr(Self.rD(raw)), .gpr(Self.rA(raw)), .simm(Self.simm(raw))])
        case 13: return D(mnemonic: "addic.", operands: [.gpr(Self.rD(raw)), .gpr(Self.rA(raw)), .simm(Self.simm(raw))])
        case 14: return decodeAddi(raw)
        case 15: return decodeAddis(raw)

        // Branch
        case 16: return decodeBc(raw, pc)
        case 17: return raw.bit(30) != 0 ? D(mnemonic: "sc", operands: []) : nil
        case 18: return decodeB(raw, pc)

        // Condition register / branch to LR/CTR
        case 19: return decodeOpcode19(raw, pc)

        // Rotate/mask
        case 20: return decodeRlwimi(raw)
        case 21: return decodeRlwinm(raw)
        case 23: return decodeRlwnm(raw)

        // Logical immediate
        case 24: return D(mnemonic: "ori", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])
        case 25: return D(mnemonic: "oris", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])
        case 26: return D(mnemonic: "xori", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])
        case 27: return D(mnemonic: "xoris", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])
        case 28: return D(mnemonic: "andi.", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])
        case 29: return D(mnemonic: "andis.", operands: [.gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .uimm(Self.uimm(raw))])

        // Integer ALU extended
        case 31: return decodeOpcode31(raw, pc)

        // Load/store integer
        case 32: return D(mnemonic: "lwz", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 33: return D(mnemonic: "lwzu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 34: return D(mnemonic: "lbz", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 35: return D(mnemonic: "lbzu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 36: return D(mnemonic: "stw", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 37: return D(mnemonic: "stwu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 38: return D(mnemonic: "stb", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 39: return D(mnemonic: "stbu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 40: return D(mnemonic: "lhz", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 41: return D(mnemonic: "lhzu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 42: return D(mnemonic: "lha", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 43: return D(mnemonic: "lhau", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 44: return D(mnemonic: "sth", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 45: return D(mnemonic: "sthu", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 46: return D(mnemonic: "lmw", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 47: return D(mnemonic: "stmw", operands: [.gpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])

        // Load/store float
        case 48: return D(mnemonic: "lfs", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 49: return D(mnemonic: "lfsu", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 50: return D(mnemonic: "lfd", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 51: return D(mnemonic: "lfdu", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 52: return D(mnemonic: "stfs", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 53: return D(mnemonic: "stfsu", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 54: return D(mnemonic: "stfd", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])
        case 55: return D(mnemonic: "stfdu", operands: [.fpr(Self.rD(raw)), .memory(offset: Int16(Self.simm(raw)), base: Self.rA(raw))])

        // Paired-singles load/store (Gekko)
        case 56: return decodePsq(raw, "psq_l")
        case 57: return decodePsq(raw, "psq_lu")
        case 60: return decodePsq(raw, "psq_st")
        case 61: return decodePsq(raw, "psq_stu")

        // Float single-precision
        case 59: return decodeOpcode59(raw)

        // Float double-precision
        case 63: return decodeOpcode63(raw)

        default: return nil
        }
    }
}

// MARK: - Simplified mnemonics & special forms

private extension PPCDecoder {
    func decodeAddi(_ raw: UInt32) -> D {
        let rd = Self.rD(raw)
        let ra = Self.rA(raw)
        let imm = Self.simm(raw)
        if ra == 0 {
            // li rD, imm (simplified mnemonic for addi rD, 0, imm)
            return D(mnemonic: "li", operands: [.gpr(rd), .simm(imm)])
        }
        return D(mnemonic: "addi", operands: [.gpr(rd), .gpr(ra), .simm(imm)])
    }

    func decodeAddis(_ raw: UInt32) -> D {
        let rd = Self.rD(raw)
        let ra = Self.rA(raw)
        let imm = Self.simm(raw)
        if ra == 0 {
            // lis rD, imm (simplified mnemonic for addis rD, 0, imm)
            return D(mnemonic: "lis", operands: [.gpr(rd), .simm(imm)])
        }
        return D(mnemonic: "addis", operands: [.gpr(rd), .gpr(ra), .simm(imm)])
    }

    func decodeCmpi(_ raw: UInt32, signed: Bool) -> D {
        let crfD = Self.crfD(raw)
        let ra = Self.rA(raw)
        if signed {
            if crfD == 0 {
                return D(mnemonic: "cmpwi", operands: [.gpr(ra), .simm(Self.simm(raw))])
            }
            return D(mnemonic: "cmpwi", operands: [.crField(crfD), .gpr(ra), .simm(Self.simm(raw))])
        } else {
            if crfD == 0 {
                return D(mnemonic: "cmplwi", operands: [.gpr(ra), .uimm(Self.uimm(raw))])
            }
            return D(mnemonic: "cmplwi", operands: [.crField(crfD), .gpr(ra), .uimm(Self.uimm(raw))])
        }
    }
}

// MARK: - Branch instructions

private extension PPCDecoder {
    func decodeB(_ raw: UInt32, _ pc: UInt32) -> D {
        let li = raw.bits(6, 29).signExtend(from: 24) << 2
        let isLink = Self.lk(raw)
        let isAbsolute = Self.aa(raw)
        let target = isAbsolute ? UInt32(bitPattern: li) : UInt32(bitPattern: Int32(bitPattern: pc) &+ li)
        let mnemonic = isLink ? (isAbsolute ? "bla" : "bl") : (isAbsolute ? "ba" : "b")
        return D(mnemonic: mnemonic, operands: [.branchTarget(target)])
    }

    func decodeBc(_ raw: UInt32, _ pc: UInt32) -> D {
        let bo = Self.bo(raw)
        let bi = Self.bi(raw)
        let bd = raw.bits(16, 29).signExtend(from: 14) << 2
        let isLink = Self.lk(raw)
        let isAbsolute = Self.aa(raw)
        let target = isAbsolute ? UInt32(bitPattern: bd) : UInt32(bitPattern: Int32(bitPattern: pc) &+ bd)

        // Try simplified mnemonics
        if let simplified = simplifiedBranch(bo: bo, bi: bi, target: target, link: isLink) {
            return simplified
        }

        var mnemonic = "bc"
        if isLink { mnemonic += "l" }
        if isAbsolute { mnemonic += "a" }
        return D(mnemonic: mnemonic, operands: [.uimm(UInt32(bo)), .crBit(bi), .branchTarget(target)])
    }

    func simplifiedBranch(bo: UInt8, bi: UInt8, target: UInt32, link: Bool) -> D? {
        let crField = bi / 4
        let crBit = bi % 4
        let suffix = link ? "l" : ""
        let crOps: [Op] = crField != 0 ? [.crField(crField)] : []

        // Decrement CTR, branch if CTR != 0 (and no condition)
        if bo == 16 { return D(mnemonic: "bdnz" + suffix, operands: [.branchTarget(target)]) }
        if bo == 18 { return D(mnemonic: "bdnz" + suffix, operands: [.branchTarget(target)]) }
        // Branch if CTR == 0
        if bo == 18 { return D(mnemonic: "bdz" + suffix, operands: [.branchTarget(target)]) }

        // Branch on condition
        switch (bo, crBit) {
        case (12, 0): return D(mnemonic: "blt" + suffix, operands: crOps + [.branchTarget(target)])
        case (12, 1): return D(mnemonic: "bgt" + suffix, operands: crOps + [.branchTarget(target)])
        case (12, 2): return D(mnemonic: "beq" + suffix, operands: crOps + [.branchTarget(target)])
        case (12, 3): return D(mnemonic: "bso" + suffix, operands: crOps + [.branchTarget(target)])
        case (4, 0):  return D(mnemonic: "bge" + suffix, operands: crOps + [.branchTarget(target)])
        case (4, 1):  return D(mnemonic: "ble" + suffix, operands: crOps + [.branchTarget(target)])
        case (4, 2):  return D(mnemonic: "bne" + suffix, operands: crOps + [.branchTarget(target)])
        case (4, 3):  return D(mnemonic: "bns" + suffix, operands: crOps + [.branchTarget(target)])
        default: return nil
        }
    }
}

// MARK: - Opcode 19: Condition register & branch to LR/CTR

private extension PPCDecoder {
    func decodeOpcode19(_ raw: UInt32, _ pc: UInt32) -> D? {
        let xo = raw.bits(21, 30)
        switch xo {
        case 0:   return D(mnemonic: "mcrf", operands: [.crField(Self.crfD(raw)), .crField(Self.crfS(raw))])
        case 16:  return decodeBclr(raw)
        case 33:  return D(mnemonic: "crnor", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 50:  return D(mnemonic: "rfi", operands: [])
        case 150: return D(mnemonic: "isync", operands: [])
        case 129: return D(mnemonic: "crandc", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 193: return D(mnemonic: "crxor", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 225: return D(mnemonic: "crnand", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 257: return D(mnemonic: "crand", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 289: return D(mnemonic: "creqv", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 417: return D(mnemonic: "crorc", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 449: return D(mnemonic: "cror", operands: [.crBit(Self.rD(raw)), .crBit(Self.rA(raw)), .crBit(Self.rB(raw))])
        case 528: return decodeBcctr(raw)
        default:  return nil
        }
    }

    func decodeBclr(_ raw: UInt32) -> D {
        let bo = Self.bo(raw)
        let bi = Self.bi(raw)
        let lk = Self.lk(raw)
        // Simplified: blr
        if bo == 20, bi == 0, !lk { return D(mnemonic: "blr", operands: []) }
        if bo == 20, bi == 0, lk  { return D(mnemonic: "blrl", operands: []) }

        let suffix = lk ? "lr" + "l" : "lr"
        let crField = bi / 4
        let crBit = bi % 4
        let crOps: [Op] = crField != 0 ? [.crField(crField)] : []

        switch (bo, crBit) {
        case (12, 0): return D(mnemonic: "blt" + suffix, operands: crOps)
        case (12, 1): return D(mnemonic: "bgt" + suffix, operands: crOps)
        case (12, 2): return D(mnemonic: "beq" + suffix, operands: crOps)
        case (4, 0):  return D(mnemonic: "bge" + suffix, operands: crOps)
        case (4, 1):  return D(mnemonic: "ble" + suffix, operands: crOps)
        case (4, 2):  return D(mnemonic: "bne" + suffix, operands: crOps)
        default:
            let mnemonic = lk ? "bclrl" : "bclr"
            return D(mnemonic: mnemonic, operands: [.uimm(UInt32(bo)), .crBit(bi)])
        }
    }

    func decodeBcctr(_ raw: UInt32) -> D {
        let bo = Self.bo(raw)
        let bi = Self.bi(raw)
        let lk = Self.lk(raw)
        if bo == 20, bi == 0, !lk { return D(mnemonic: "bctr", operands: []) }
        if bo == 20, bi == 0, lk  { return D(mnemonic: "bctrl", operands: []) }
        let mnemonic = lk ? "bcctrl" : "bcctr"
        return D(mnemonic: mnemonic, operands: [.uimm(UInt32(bo)), .crBit(bi)])
    }
}

// MARK: - Opcode 31: Integer ALU extended

private extension PPCDecoder {
    func decodeOpcode31(_ raw: UInt32, _ pc: UInt32) -> D? {
        let xo9 = raw.bits(22, 30)   // 9-bit XO for OE-form instructions
        let xo10 = raw.bits(21, 30)  // 10-bit XO for X-form instructions
        let rc = Self.rc(raw)
        let dot = rc ? "." : ""

        let rd = Self.rD(raw)
        let ra = Self.rA(raw)
        let rb = Self.rB(raw)

        // First check 9-bit XO (XO-form: arithmetic with OE)
        switch xo9 {
        case 266:
            let oe = Self.oe(raw)
            return D(mnemonic: "add" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 10:
            let oe = Self.oe(raw)
            return D(mnemonic: "addc" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 138:
            let oe = Self.oe(raw)
            return D(mnemonic: "adde" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 234:
            let oe = Self.oe(raw)
            return D(mnemonic: "addme" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra)])
        case 202:
            let oe = Self.oe(raw)
            return D(mnemonic: "addze" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra)])
        case 491:
            let oe = Self.oe(raw)
            return D(mnemonic: "divw" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 459:
            let oe = Self.oe(raw)
            return D(mnemonic: "divwu" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 75:
            let oe = Self.oe(raw)
            return D(mnemonic: "mulhw" + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 11:
            let oe = Self.oe(raw)
            return D(mnemonic: "mulhwu" + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 235:
            let oe = Self.oe(raw)
            return D(mnemonic: "mullw" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 104:
            let oe = Self.oe(raw)
            return D(mnemonic: "neg" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra)])
        case 40:
            let oe = Self.oe(raw)
            // Simplified: sub rD, rB, rA (note operand swap)
            return D(mnemonic: "subf" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 8:
            let oe = Self.oe(raw)
            return D(mnemonic: "subfc" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 136:
            let oe = Self.oe(raw)
            return D(mnemonic: "subfe" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 232:
            let oe = Self.oe(raw)
            return D(mnemonic: "subfme" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra)])
        case 200:
            let oe = Self.oe(raw)
            return D(mnemonic: "subfze" + (oe ? "o" : "") + dot, operands: [.gpr(rd), .gpr(ra)])
        default: break
        }

        // 10-bit XO (X-form)
        switch xo10 {
        // Compare
        case 0:   return decodeCmp(raw, signed: true)
        case 32:  return decodeCmp(raw, signed: false)

        // Logical
        case 28:
            if rd == rb { return D(mnemonic: "mr" + dot, operands: [.gpr(ra), .gpr(rd)]) }
            return D(mnemonic: "or" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 444:  return D(mnemonic: "or" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 60:   return D(mnemonic: "andc" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 124:
            if rd == rb { return D(mnemonic: "not" + dot, operands: [.gpr(ra), .gpr(rd)]) }
            return D(mnemonic: "nor" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 284:  return D(mnemonic: "eqv" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 316:  return D(mnemonic: "xor" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 412:  return D(mnemonic: "orc" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 476:  return D(mnemonic: "nand" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 26:   return D(mnemonic: "cntlzw" + dot, operands: [.gpr(ra), .gpr(rd)])

        // And
        case 28 where xo10 == 28:
            return D(mnemonic: "and" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])

        // Shift
        case 24:   return D(mnemonic: "slw" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 536:  return D(mnemonic: "srw" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 792:  return D(mnemonic: "sraw" + dot, operands: [.gpr(ra), .gpr(rd), .gpr(rb)])
        case 824:  return D(mnemonic: "srawi" + dot, operands: [.gpr(ra), .gpr(rd), .shift(Self.sh(raw))])

        // Sign extend
        case 954:  return D(mnemonic: "extsb" + dot, operands: [.gpr(ra), .gpr(rd)])
        case 922:  return D(mnemonic: "extsh" + dot, operands: [.gpr(ra), .gpr(rd)])

        // Load/store indexed
        case 23:   return D(mnemonic: "lwzx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 55:   return D(mnemonic: "lwzux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 87:   return D(mnemonic: "lbzx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 119:  return D(mnemonic: "lbzux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 151:  return D(mnemonic: "stwx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 183:  return D(mnemonic: "stwux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 215:  return D(mnemonic: "stbx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 247:  return D(mnemonic: "stbux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 279:  return D(mnemonic: "lhzx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 311:  return D(mnemonic: "lhzux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 343:  return D(mnemonic: "lhax", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 375:  return D(mnemonic: "lhaux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 407:  return D(mnemonic: "sthx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 439:  return D(mnemonic: "sthux", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])

        // Load/store byte-reversed
        case 534:  return D(mnemonic: "lwbrx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 662:  return D(mnemonic: "stwbrx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 790:  return D(mnemonic: "lhbrx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 918:  return D(mnemonic: "sthbrx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])

        // Load/store string
        case 533:  return D(mnemonic: "lswi", operands: [.gpr(rd), .gpr(ra), .count(rb)])
        case 597:  return D(mnemonic: "lswx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 661:  return D(mnemonic: "stswi", operands: [.gpr(rd), .gpr(ra), .count(rb)])
        case 725:  return D(mnemonic: "stswx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])

        // Load/store float indexed
        case 535:  return D(mnemonic: "lfsx", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 567:  return D(mnemonic: "lfsux", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 599:  return D(mnemonic: "lfdx", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 631:  return D(mnemonic: "lfdux", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 663:  return D(mnemonic: "stfsx", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 695:  return D(mnemonic: "stfsux", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 727:  return D(mnemonic: "stfdx", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 759:  return D(mnemonic: "stfdux", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])
        case 983:  return D(mnemonic: "stfiwx", operands: [.fpr(rd), .gpr(ra), .gpr(rb)])

        // SPR access
        case 339:  return decodeMfspr(raw)
        case 467:  return decodeMtspr(raw)

        // Move to/from CR
        case 19:   return D(mnemonic: "mfcr", operands: [.gpr(rd)])
        case 144:  return D(mnemonic: "mtcrf", operands: [.uimm(UInt32(raw.bits(12, 19))), .gpr(rd)])

        // Move to/from MSR
        case 83:   return D(mnemonic: "mfmsr", operands: [.gpr(rd)])
        case 146:  return D(mnemonic: "mtmsr", operands: [.gpr(rd)])

        // Cache
        case 54:   return D(mnemonic: "dcbst", operands: [.gpr(ra), .gpr(rb)])
        case 86:   return D(mnemonic: "dcbf", operands: [.gpr(ra), .gpr(rb)])
        case 246:  return D(mnemonic: "dcbtst", operands: [.gpr(ra), .gpr(rb)])
        case 278:  return D(mnemonic: "dcbt", operands: [.gpr(ra), .gpr(rb)])
        case 470:  return D(mnemonic: "dcbi", operands: [.gpr(ra), .gpr(rb)])
        case 1014: return D(mnemonic: "dcbz", operands: [.gpr(ra), .gpr(rb)])
        case 982:  return D(mnemonic: "icbi", operands: [.gpr(ra), .gpr(rb)])

        // TLB
        case 306:  return D(mnemonic: "tlbie", operands: [.gpr(rb)])
        case 566:  return D(mnemonic: "tlbsync", operands: [])

        // Sync/eieio
        case 598:  return D(mnemonic: "sync", operands: [])
        case 854:  return D(mnemonic: "eieio", operands: [])

        // Segment register
        case 595:  return D(mnemonic: "mfsr", operands: [.gpr(rd), .uimm(UInt32(ra))])
        case 659:  return D(mnemonic: "mfsrin", operands: [.gpr(rd), .gpr(rb)])
        case 210:  return D(mnemonic: "mtsr", operands: [.uimm(UInt32(ra)), .gpr(rd)])
        case 242:  return D(mnemonic: "mtsrin", operands: [.gpr(rd), .gpr(rb)])

        // Misc
        case 4:    return D(mnemonic: "tw", operands: [.uimm(UInt32(rd)), .gpr(ra), .gpr(rb)])
        case 20:   return D(mnemonic: "lwarx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 150:  return D(mnemonic: "stwcx.", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 310:  return D(mnemonic: "eciwx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])
        case 438:  return D(mnemonic: "ecowx", operands: [.gpr(rd), .gpr(ra), .gpr(rb)])

        default: return nil
        }
    }

    func decodeCmp(_ raw: UInt32, signed: Bool) -> D {
        let crfD = Self.crfD(raw)
        let ra = Self.rA(raw)
        let rb = Self.rB(raw)
        let mnemonic = signed ? "cmpw" : "cmplw"
        if crfD == 0 {
            return D(mnemonic: mnemonic, operands: [.gpr(ra), .gpr(rb)])
        }
        return D(mnemonic: mnemonic, operands: [.crField(crfD), .gpr(ra), .gpr(rb)])
    }

    func decodeMfspr(_ raw: UInt32) -> D {
        let rd = Self.rD(raw)
        let sprNum = Self.spr(raw)
        switch sprNum {
        case 8:   return D(mnemonic: "mflr", operands: [.gpr(rd)])
        case 9:   return D(mnemonic: "mfctr", operands: [.gpr(rd)])
        case 1:   return D(mnemonic: "mfxer", operands: [.gpr(rd)])
        default:  return D(mnemonic: "mfspr", operands: [.gpr(rd), .spr(sprNum)])
        }
    }

    func decodeMtspr(_ raw: UInt32) -> D {
        let rd = Self.rD(raw)
        let sprNum = Self.spr(raw)
        switch sprNum {
        case 8:   return D(mnemonic: "mtlr", operands: [.gpr(rd)])
        case 9:   return D(mnemonic: "mtctr", operands: [.gpr(rd)])
        case 1:   return D(mnemonic: "mtxer", operands: [.gpr(rd)])
        default:  return D(mnemonic: "mtspr", operands: [.spr(sprNum), .gpr(rd)])
        }
    }
}

// MARK: - Rotate/mask instructions

private extension PPCDecoder {
    func decodeRlwinm(_ raw: UInt32) -> D {
        let ra = Self.rA(raw)
        let rs = Self.rD(raw)
        let sh = Self.sh(raw)
        let mbVal = Self.mb(raw)
        let meVal = Self.me(raw)
        let dot = Self.rc(raw) ? "." : ""
        // Simplified forms
        if mbVal == 0, meVal == 31 - sh {
            return D(mnemonic: "slwi" + dot, operands: [.gpr(ra), .gpr(rs), .shift(sh)])
        }
        if sh == 32 - UInt8(mbVal), meVal == 31 {
            return D(mnemonic: "srwi" + dot, operands: [.gpr(ra), .gpr(rs), .shift(UInt8(mbVal))])
        }
        if sh == 0, meVal == 31 {
            return D(mnemonic: "clrlwi" + dot, operands: [.gpr(ra), .gpr(rs), .shift(UInt8(mbVal))])
        }
        return D(mnemonic: "rlwinm" + dot, operands: [.gpr(ra), .gpr(rs), .shift(sh), .maskBegin(UInt8(mbVal)), .maskEnd(UInt8(meVal))])
    }

    func decodeRlwimi(_ raw: UInt32) -> D {
        let dot = Self.rc(raw) ? "." : ""
        return D(mnemonic: "rlwimi" + dot, operands: [
            .gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .shift(Self.sh(raw)),
            .maskBegin(Self.mb(raw)), .maskEnd(Self.me(raw))
        ])
    }

    func decodeRlwnm(_ raw: UInt32) -> D {
        let dot = Self.rc(raw) ? "." : ""
        return D(mnemonic: "rlwnm" + dot, operands: [
            .gpr(Self.rA(raw)), .gpr(Self.rD(raw)), .gpr(Self.rB(raw)),
            .maskBegin(Self.mb(raw)), .maskEnd(Self.me(raw))
        ])
    }
}

// MARK: - Opcode 59: Float single-precision

private extension PPCDecoder {
    func decodeOpcode59(_ raw: UInt32) -> D? {
        let xo = raw.bits(26, 30)
        let dot = Self.rc(raw) ? "." : ""
        let fd = Self.rD(raw)
        let fa = Self.rA(raw)
        let fb = Self.rB(raw)
        let fc = Self.rC(raw)

        switch xo {
        case 18: return D(mnemonic: "fdivs" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 20: return D(mnemonic: "fsubs" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 21: return D(mnemonic: "fadds" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 22: return D(mnemonic: "fsqrts" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 24: return D(mnemonic: "fres" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 25: return D(mnemonic: "fmuls" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc)])
        case 28: return D(mnemonic: "fmsubs" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 29: return D(mnemonic: "fmadds" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 30: return D(mnemonic: "fnmsubs" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 31: return D(mnemonic: "fnmadds" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        default: return nil
        }
    }
}

// MARK: - Opcode 63: Float double-precision

private extension PPCDecoder {
    func decodeOpcode63(_ raw: UInt32) -> D? {
        let dot = Self.rc(raw) ? "." : ""
        let fd = Self.rD(raw)
        let fa = Self.rA(raw)
        let fb = Self.rB(raw)
        let fc = Self.rC(raw)

        // Check 5-bit XO first (A-form: multiply-add)
        let xo5 = raw.bits(26, 30)
        switch xo5 {
        case 18: return D(mnemonic: "fdiv" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 20: return D(mnemonic: "fsub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 21: return D(mnemonic: "fadd" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 22: return D(mnemonic: "fsqrt" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 23: return D(mnemonic: "fsel" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 25: return D(mnemonic: "fmul" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc)])
        case 26: return D(mnemonic: "frsqrte" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 28: return D(mnemonic: "fmsub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 29: return D(mnemonic: "fmadd" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 30: return D(mnemonic: "fnmsub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 31: return D(mnemonic: "fnmadd" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        default: break
        }

        // 10-bit XO (X-form)
        let xo10 = raw.bits(21, 30)
        switch xo10 {
        case 0:   return D(mnemonic: "fcmpu", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 12:  return D(mnemonic: "frsp" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 14:  return D(mnemonic: "fctiw" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 15:  return D(mnemonic: "fctiwz" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 32:  return D(mnemonic: "fcmpo", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 38:  return D(mnemonic: "mtfsb1" + dot, operands: [.crBit(fd)])
        case 40:  return D(mnemonic: "fneg" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 64:  return D(mnemonic: "mcrfs", operands: [.crField(UInt8(raw.bits(6, 8))), .crField(UInt8(raw.bits(11, 13)))])
        case 70:  return D(mnemonic: "mtfsb0" + dot, operands: [.crBit(fd)])
        case 72:  return D(mnemonic: "fmr" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 134: return D(mnemonic: "mtfsfi" + dot, operands: [.crField(UInt8(raw.bits(6, 8))), .uimm(UInt32(raw.bits(16, 19)))])
        case 136: return D(mnemonic: "fnabs" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 264: return D(mnemonic: "fabs" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 583: return D(mnemonic: "mffs" + dot, operands: [.fpr(fd)])
        case 711:
            let fm = UInt8(raw.bits(7, 14))
            return D(mnemonic: "mtfsf" + dot, operands: [.uimm(UInt32(fm)), .fpr(fb)])
        default: return nil
        }
    }
}

// MARK: - Opcode 4: Paired-singles (Gekko-specific)

private extension PPCDecoder {
    func decodeOpcode4(_ raw: UInt32, _ pc: UInt32) -> D? {
        let dot = Self.rc(raw) ? "." : ""
        let fd = Self.rD(raw)
        let fa = Self.rA(raw)
        let fb = Self.rB(raw)
        let fc = Self.rC(raw)

        // Check 5-bit XO first (A-form)
        let xo5 = raw.bits(26, 30)
        switch xo5 {
        case 10: return D(mnemonic: "ps_sum0" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 11: return D(mnemonic: "ps_sum1" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 12: return D(mnemonic: "ps_muls0" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc)])
        case 13: return D(mnemonic: "ps_muls1" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc)])
        case 14: return D(mnemonic: "ps_madds0" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 15: return D(mnemonic: "ps_madds1" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 18: return D(mnemonic: "ps_div" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 20: return D(mnemonic: "ps_sub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 21: return D(mnemonic: "ps_add" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 23: return D(mnemonic: "ps_sel" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 24: return D(mnemonic: "ps_res" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 25: return D(mnemonic: "ps_mul" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc)])
        case 26: return D(mnemonic: "ps_rsqrte" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 28: return D(mnemonic: "ps_msub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 29: return D(mnemonic: "ps_madd" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 30: return D(mnemonic: "ps_nmsub" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        case 31: return D(mnemonic: "ps_nmadd" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fc), .fpr(fb)])
        default: break
        }

        // 10-bit XO (X-form)
        let xo10 = raw.bits(21, 30)
        switch xo10 {
        case 6:    return D(mnemonic: "psq_lx", operands: [.fpr(fd), .gpr(fa), .gpr(fb), .wBit(UInt8(raw.bit(21))), .gqr(UInt8(raw.bits(22, 24)))])
        case 7:    return D(mnemonic: "psq_stx", operands: [.fpr(fd), .gpr(fa), .gpr(fb), .wBit(UInt8(raw.bit(21))), .gqr(UInt8(raw.bits(22, 24)))])
        case 38:   return D(mnemonic: "psq_lux", operands: [.fpr(fd), .gpr(fa), .gpr(fb), .wBit(UInt8(raw.bit(21))), .gqr(UInt8(raw.bits(22, 24)))])
        case 39:   return D(mnemonic: "psq_stux", operands: [.fpr(fd), .gpr(fa), .gpr(fb), .wBit(UInt8(raw.bit(21))), .gqr(UInt8(raw.bits(22, 24)))])
        case 40:   return D(mnemonic: "ps_neg" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 72:   return D(mnemonic: "ps_mr" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 136:  return D(mnemonic: "ps_nabs" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 264:  return D(mnemonic: "ps_abs" + dot, operands: [.fpr(fd), .fpr(fb)])
        case 528:  return D(mnemonic: "ps_merge00" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 560:  return D(mnemonic: "ps_merge01" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 592:  return D(mnemonic: "ps_merge10" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 624:  return D(mnemonic: "ps_merge11" + dot, operands: [.fpr(fd), .fpr(fa), .fpr(fb)])
        case 0:    return D(mnemonic: "ps_cmpu0", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 32:   return D(mnemonic: "ps_cmpo0", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 64:   return D(mnemonic: "ps_cmpu1", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 96:   return D(mnemonic: "ps_cmpo1", operands: [.crField(UInt8(raw.bits(6, 8))), .fpr(fa), .fpr(fb)])
        case 1014: return D(mnemonic: "dcbz_l", operands: [.gpr(fa), .gpr(fb)])
        default:   return nil
        }
    }

    func decodePsq(_ raw: UInt32, _ mnemonic: String) -> D {
        let fd = Self.rD(raw)
        let ra = Self.rA(raw)
        let w = UInt8(raw.bit(16))
        let i = UInt8(raw.bits(17, 19))
        let d = raw.bits(20, 31).signExtend(from: 12)
        return D(mnemonic: mnemonic, operands: [.fpr(fd), .memory(offset: Int16(d), base: ra), .wBit(w), .gqr(i)])
    }
}
