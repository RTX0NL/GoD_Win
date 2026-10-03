import Foundation

/// A decoded PowerPC 750CL instruction
public struct PPCInstruction {
    /// RAM address of this instruction
    public let address: UInt32
    /// Raw 32-bit instruction word (big-endian decoded)
    public let raw: UInt32
    /// Decoded content, or nil if the word couldn't be decoded as a valid instruction
    public let decoded: Decoded?

    public struct Decoded {
        public let mnemonic: String
        public let operands: [Operand]
    }

    public var isValid: Bool { decoded != nil }

    /// Primary opcode (bits 0-5 in PPC big-endian notation)
    public var opcode: UInt32 { (raw >> 26) & 0x3F }
}

// MARK: - Operands

public extension PPCInstruction {
    enum Operand {
        /// General-purpose register r0-r31
        case gpr(UInt8)
        /// Floating-point register f0-f31
        case fpr(UInt8)
        /// Paired-singles register (same as FPR but context-specific)
        case ps(UInt8)
        case simm(Int32)
        case uimm(UInt32)
        /// Branch target (absolute RAM address, resolved from PC-relative or absolute)
        case branchTarget(UInt32)
        /// Memory access: offset(rBase)
        case memory(offset: Int16, base: UInt8)
        /// Condition register field (cr0-cr7)
        case crField(UInt8)
        case crBit(UInt8)
        /// Special-purpose register number
        case spr(UInt32)
        case shift(UInt8)
        case maskBegin(UInt8)
        case maskEnd(UInt8)
        /// Number of registers (for lmw/stmw)
        case count(UInt8)
        /// GQR register index (for paired-singles quantized load/store)
        case gqr(UInt8)
        /// Paired-singles W bit
        case wBit(UInt8)
    }
}

// MARK: - Register names

public extension PPCInstruction {
    /// Well-known SPR numbers
    enum SPR: UInt32 {
        case xer  = 1
        case lr   = 8
        case ctr  = 9
        case dsisr = 18
        case dar  = 19
        case dec  = 22
        case sdr1 = 25
        case srr0 = 26
        case srr1 = 27
        case sprg0 = 272
        case sprg1 = 273
        case sprg2 = 274
        case sprg3 = 275
        case ear  = 282
        case tbLo = 268
        case tbHi = 269
        case pvr  = 287
        case ibat0u = 528
        case ibat0l = 529
        case ibat1u = 530
        case ibat1l = 531
        case ibat2u = 532
        case ibat2l = 533
        case ibat3u = 534
        case ibat3l = 535
        case dbat0u = 536
        case dbat0l = 537
        case dbat1u = 538
        case dbat1l = 539
        case dbat2u = 540
        case dbat2l = 541
        case dbat3u = 542
        case dbat3l = 543
        case gqr0 = 912
        case gqr1 = 913
        case gqr2 = 914
        case gqr3 = 915
        case gqr4 = 916
        case gqr5 = 917
        case gqr6 = 918
        case gqr7 = 919
        case hid2 = 920
        case wpar = 921
        case dmau = 922
        case dmal = 923
        case ummcr0 = 936
        case upmc1 = 937
        case upmc2 = 938
        case usia  = 939
        case ummcr1 = 940
        case upmc3 = 941
        case upmc4 = 942
        case usda  = 943
        case mmcr0 = 952
        case pmc1 = 953
        case pmc2 = 954
        case sia  = 955
        case mmcr1 = 956
        case pmc3 = 957
        case pmc4 = 958
        case sda  = 959
        case hid0 = 1008
        case hid1 = 1009
        case iabr = 1010
        case dabr = 1013
        case l2cr = 1017
        case ictc = 1019
        case thrm1 = 1020
        case thrm2 = 1021
        case thrm3 = 1022
    }

    static func sprName(_ spr: UInt32) -> String? {
        SPR(rawValue: spr).map { String(describing: $0) }
    }
}
