import Foundation

/// Relocation info for an instruction that references a symbol via @ha/@h/@l
public struct PPCRelocation {
    /// The full 32-bit address being referenced
    public let targetAddress: UInt32
    /// The symbol name at that address (if known)
    public let symbolName: String?
    /// Whether this is the upper or lower half
    public let halfType: HalfType

    public enum HalfType {
        case ha  // lis paired with signed lo consumers — upper half carries the sign adjustment
        case h   // lis paired with an unsigned lo consumer (ori) — raw upper half, no adjustment
        case lo  // consumer instruction — lower half (signed or unsigned)
    }
}

/// Analyzes decoded instructions to find lis/consumer pairs that construct
/// 32-bit addresses, and resolves them to symbol references.
public struct PPCRelocAnalyzer {

    public init() {}

    /// Analyze instructions and return a map of instruction address → relocation info.
    /// Only produces relocations for addresses that resolve to known symbols.
    public func analyze(
        _ instructions: [PPCInstruction],
        symbols: [UInt32: String],
        sectionRanges: [(start: UInt32, end: UInt32)]
    ) -> [UInt32: PPCRelocation] {
        var relocations = [UInt32: PPCRelocation]()

        // Track pending lis instructions: register → (lis address, upper immediate value)
        var pendingLis = [UInt8: (address: UInt32, upperImm: Int32)]()

        for inst in instructions {
            guard let decoded = inst.decoded else { continue }

            // Check if this is a lis instruction
            if decoded.mnemonic == "lis", decoded.operands.count == 2,
               case .gpr(let rd) = decoded.operands[0],
               case .simm(let imm) = decoded.operands[1] {
                pendingLis[rd] = (address: inst.address, upperImm: imm)
                continue
            }

            // Check if this instruction consumes a pending lis register.
            // One lis can serve several consumers (a single high half shared
            // across globals in the same 64KB window is standard compiler
            // output), so consuming does NOT end the tracking — only
            // overwriting the register does.
            if let (lisReg, consumer) = findLisConsumer(decoded, pendingLis: pendingLis) {
                let lis = pendingLis[lisReg]!
                let fullAddress = computeAddress(
                    upper: lis.upperImm,
                    lower: consumer.lowerImm,
                    unsignedLower: consumer.isUnsigned
                )

                // Only create relocations for addresses within known sections
                // or that resolve to known symbols
                let symbolName = symbols[fullAddress]
                let inSection = sectionRanges.contains { fullAddress >= $0.start && fullAddress < $0.end }

                if symbolName != nil || inSection {
                    let name = symbolName ?? "lbl_\(String(format: "%08X", fullAddress))"
                    relocations[inst.address] = PPCRelocation(
                        targetAddress: fullAddress,
                        symbolName: name,
                        halfType: .lo
                    )
                    // The first symbolized consumer claims the lis. An
                    // unsigned (ori) pair needs the raw high half — the
                    // @ha carry adjustment would be off by 0x10000 for
                    // lower halves >= 0x8000.
                    if relocations[lis.address] == nil {
                        relocations[lis.address] = PPCRelocation(
                            targetAddress: fullAddress,
                            symbolName: name,
                            halfType: consumer.isUnsigned ? .h : .ha
                        )
                    }
                }
            }

            // Kill tracking for every GPR this instruction overwrites,
            // including update-form base writeback and lmw's rD..r31 range.
            for reg in writtenGPRs(decoded) {
                pendingLis.removeValue(forKey: reg)
            }

            // Clear pending state on function exits and indirect branches.
            // Conditional branches and local unconditional branches preserve lis state
            // since the register is still live on the fallthrough/target path.
            if isReturnOrIndirectBranch(decoded) {
                pendingLis.removeAll()
            }
        }

        return relocations
    }
}

// MARK: - Consumer detection

private extension PPCRelocAnalyzer {
    struct ConsumerInfo {
        let lowerImm: Int32
        /// True when the consumer combines with the high half unsigned (ori)
        let isUnsigned: Bool
    }

    /// Load/store mnemonics whose displacement forms a lower half when their
    /// base register holds a lis result. psq displacement is only 12 bits —
    /// the compiler only pairs it with lis when the offset fits.
    static let memoryConsumers: Set<String> = [
        "lwz", "lwzu", "lbz", "lbzu", "lhz", "lhzu", "lha", "lhau",
        "stw", "stwu", "stb", "stbu", "sth", "sthu",
        "lfs", "lfsu", "lfd", "lfdu", "stfs", "stfsu", "stfd", "stfdu",
        "lmw", "stmw",
        "psq_l", "psq_lu", "psq_st", "psq_stu",
    ]

    /// Check if an instruction consumes a pending lis register.
    /// Returns (lis register, consumer info) if found.
    func findLisConsumer(
        _ decoded: PPCInstruction.Decoded,
        pendingLis: [UInt8: (address: UInt32, upperImm: Int32)]
    ) -> (UInt8, ConsumerInfo)? {
        let mnemonic = decoded.mnemonic
        let ops = decoded.operands

        // addi/addic/addic. rD, rA, SIMM — rA is the lis register
        if (mnemonic == "addi" || mnemonic == "addic" || mnemonic == "addic."),
           ops.count == 3,
           case .gpr(let ra) = ops[1],
           case .simm(let imm) = ops[2],
           pendingLis[ra] != nil {
            return (ra, ConsumerInfo(lowerImm: imm, isUnsigned: false))
        }

        // ori rA, rS, UIMM — rS is the lis register. The CPU zero-extends,
        // so the lower half is unsigned.
        if mnemonic == "ori", ops.count == 3,
           case .gpr(let rs) = ops[1],
           case .uimm(let imm) = ops[2],
           pendingLis[rs] != nil {
            return (rs, ConsumerInfo(lowerImm: Int32(imm & 0xFFFF), isUnsigned: true))
        }

        // Load/store with displacement: lwz rD, offset(rA) — rA is the lis
        // register. Scan operands for the memory form so 4-operand shapes
        // (psq_l fD, offset(rA), W, GQR) are covered too.
        if Self.memoryConsumers.contains(mnemonic) {
            for op in ops {
                if case .memory(let offset, let base) = op, pendingLis[base] != nil {
                    return (base, ConsumerInfo(lowerImm: Int32(offset), isUnsigned: false))
                }
            }
        }

        return nil
    }

    /// Compute full 32-bit address from lis upper and consumer lower values.
    /// lis loads `upper << 16`; a signed consumer (addi/displacement) adds a
    /// sign-extended lower, an unsigned consumer (ori) ORs a zero-extended one.
    func computeAddress(upper: Int32, lower: Int32, unsignedLower: Bool) -> UInt32 {
        let lo = unsignedLower ? Int(lower & 0xFFFF) : Int(lower)
        let full = (Int(upper) << 16) &+ lo
        return UInt32(truncatingIfNeeded: full)
    }

    /// Mnemonics whose first operand is a GPR they write to
    static let gprWriters: Set<String> = [
        "li", "addi", "addis", "addic", "subfic", "mulli",
        "add", "addc", "adde", "addme", "addze",
        "subf", "subfc", "subfe", "subfme", "subfze",
        "mullw", "mulhw", "mulhwu", "divw", "divwu", "neg",
        "and", "or", "xor", "nand", "nor", "eqv", "andc", "orc",
        "ori", "oris", "xori", "xoris", "andi", "andis",
        "slw", "srw", "sraw", "srawi",
        "rlwinm", "rlwimi", "rlwnm", "slwi", "srwi", "clrlwi",
        "extsb", "extsh", "cntlzw", "mr",
        "lwz", "lwzu", "lbz", "lbzu", "lhz", "lhzu", "lha", "lhau",
        "lwzx", "lwzux", "lbzx", "lbzux", "lhzx", "lhzux", "lhax", "lhaux",
        "lwbrx", "lhbrx", "lswi", "lswx",
        "mflr", "mfctr", "mfxer", "mfcr", "mfspr",
    ]

    /// Update-form loads/stores write the effective address back into the
    /// base register, ending its life as a tracked high half.
    static let updateForms: Set<String> = [
        "lwzu", "lbzu", "lhzu", "lhau", "lfsu", "lfdu",
        "stwu", "stbu", "sthu", "stfsu", "stfdu",
        "psq_lu", "psq_stu",
        "lwzux", "lbzux", "lhzux", "lhaux",
        "stwux", "stbux", "sthux", "stfsux", "stfdux",
        "psq_lux", "psq_stux",
    ]

    /// All GPRs this instruction writes, for lis-kill tracking.
    func writtenGPRs(_ decoded: PPCInstruction.Decoded) -> [UInt8] {
        let base = decoded.mnemonic.hasSuffix(".") ?
            String(decoded.mnemonic.dropLast()) : decoded.mnemonic

        // lmw loads rD through r31
        if base == "lmw", case .gpr(let rd) = decoded.operands.first {
            return Array(rd...31)
        }

        var written = [UInt8]()
        if Self.gprWriters.contains(base), case .gpr(let reg) = decoded.operands.first {
            written.append(reg)
        }

        if Self.updateForms.contains(base) {
            // D-form update: base lives in the memory operand
            for op in decoded.operands {
                if case .memory(_, let b) = op { written.append(b) }
            }
            // Indexed update (rD, rA, rB): base is the second operand
            if base.hasSuffix("ux"), decoded.operands.count >= 2,
               case .gpr(let b) = decoded.operands[1] {
                written.append(b)
            }
        }
        return written
    }

    func isReturnOrIndirectBranch(_ decoded: PPCInstruction.Decoded) -> Bool {
        let m = decoded.mnemonic
        // Only clear on function exits and indirect branches
        return m == "blr" || m == "bctr" || m == "bctrl" || m == "rfi"
    }
}
