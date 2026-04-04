import Foundation

/// Relocation info for an instruction that references a symbol via @ha/@l
public struct PPCRelocation {
    /// The full 32-bit address being referenced
    public let targetAddress: UInt32
    /// The symbol name at that address (if known)
    public let symbolName: String?
    /// Whether this is the @ha (upper) or @l (lower) half
    public let halfType: HalfType

    public enum HalfType {
        case ha  // lis instruction — upper half adjusted
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

        // Set of addresses that are branch targets (basic block boundaries)
        var branchTargets = Set<UInt32>()
        for inst in instructions {
            guard let decoded = inst.decoded else { continue }
            for op in decoded.operands {
                if case .branchTarget(let target) = op {
                    branchTargets.insert(target)
                }
            }
        }

        for inst in instructions {
            // Clear pending state at basic block boundaries
            if branchTargets.contains(inst.address) {
                pendingLis.removeAll()
            }

            guard let decoded = inst.decoded else { continue }

            // Check if this is a lis instruction
            if decoded.mnemonic == "lis", decoded.operands.count == 2,
               case .gpr(let rd) = decoded.operands[0],
               case .simm(let imm) = decoded.operands[1] {
                pendingLis[rd] = (address: inst.address, upperImm: imm)
                continue
            }

            // Check if this instruction consumes a pending lis register
            if let (lisReg, consumer) = findLisConsumer(decoded, pendingLis: pendingLis) {
                let lis = pendingLis[lisReg]!
                let fullAddress = computeAddress(upper: lis.upperImm, lower: consumer.lowerImm)

                // Only create relocations for addresses within known sections
                // or that resolve to known symbols
                let symbolName = symbols[fullAddress]
                let inSection = sectionRanges.contains { fullAddress >= $0.start && fullAddress < $0.end }

                if symbolName != nil || inSection {
                    let name = symbolName ?? "lbl_\(String(format: "%08X", fullAddress))"
                    relocations[lis.address] = PPCRelocation(
                        targetAddress: fullAddress,
                        symbolName: name,
                        halfType: .ha
                    )
                    relocations[inst.address] = PPCRelocation(
                        targetAddress: fullAddress,
                        symbolName: name,
                        halfType: .lo
                    )
                }

                pendingLis.removeValue(forKey: lisReg)
                continue
            }

            // Check if this instruction overwrites a tracked register (kills the lis)
            if let writtenReg = getWrittenGPR(decoded) {
                pendingLis.removeValue(forKey: writtenReg)
            }

            // Branches clear all pending state (conservative — could be more precise with CFG)
            if isBranch(decoded) {
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
    }

    /// Check if an instruction consumes a pending lis register.
    /// Returns (lis register, consumer info) if found.
    func findLisConsumer(
        _ decoded: PPCInstruction.Decoded,
        pendingLis: [UInt8: (address: UInt32, upperImm: Int32)]
    ) -> (UInt8, ConsumerInfo)? {
        let mnemonic = decoded.mnemonic
        let ops = decoded.operands

        // addi rD, rA, SIMM — rA is the lis register
        if mnemonic == "addi", ops.count == 3,
           case .gpr(let ra) = ops[1],
           case .simm(let imm) = ops[2],
           pendingLis[ra] != nil {
            return (ra, ConsumerInfo(lowerImm: imm))
        }

        // ori rA, rS, UIMM — rS is the lis register (unsigned lower)
        if mnemonic == "ori", ops.count == 3,
           case .gpr(let rs) = ops[1],
           case .uimm(let imm) = ops[2],
           pendingLis[rs] != nil {
            return (rs, ConsumerInfo(lowerImm: Int32(Int16(bitPattern: UInt16(imm & 0xFFFF)))))
        }

        // Load/store with displacement: lwz rD, offset(rA) — rA is the lis register
        let memoryConsumers = [
            "lwz", "lwzu", "lbz", "lbzu", "lhz", "lhzu", "lha", "lhau",
            "stw", "stwu", "stb", "stbu", "sth", "sthu",
            "lfs", "lfsu", "lfd", "lfdu", "stfs", "stfsu", "stfd", "stfdu",
        ]
        if memoryConsumers.contains(mnemonic), ops.count == 2,
           case .memory(let offset, let base) = ops[1],
           pendingLis[base] != nil {
            return (base, ConsumerInfo(lowerImm: Int32(offset)))
        }

        return nil
    }

    /// Compute full 32-bit address from lis upper and consumer lower values.
    /// lis loads `upper << 16`, consumer adds sign-extended lower.
    func computeAddress(upper: Int32, lower: Int32) -> UInt32 {
        let full = (Int(upper) << 16) &+ Int(lower)
        return UInt32(truncatingIfNeeded: full)
    }

    /// Get the GPR that this instruction writes to (if any), to detect lis kills
    func getWrittenGPR(_ decoded: PPCInstruction.Decoded) -> UInt8? {
        guard let firstOp = decoded.operands.first else { return nil }
        // Most ALU instructions write to the first operand
        let writers = [
            "li", "addi", "addis", "addic", "addic.", "subfic", "mulli",
            "add", "addc", "adde", "addme", "addze",
            "subf", "subfc", "subfe", "subfme", "subfze",
            "mullw", "mulhw", "mulhwu", "divw", "divwu", "neg",
            "and", "or", "xor", "nand", "nor", "eqv", "andc", "orc",
            "ori", "oris", "xori", "xoris", "andi.", "andis.",
            "slw", "srw", "sraw", "srawi",
            "rlwinm", "rlwimi", "rlwnm", "slwi", "srwi", "clrlwi",
            "extsb", "extsh", "cntlzw", "mr",
            "lwz", "lwzu", "lbz", "lbzu", "lhz", "lhzu", "lha", "lhau",
            "mflr", "mfctr", "mfxer", "mfcr", "mfspr",
        ]
        // Strip trailing . for Rc variants
        let base = decoded.mnemonic.hasSuffix(".") ?
            String(decoded.mnemonic.dropLast()) : decoded.mnemonic
        if writers.contains(base) || writers.contains(decoded.mnemonic) {
            if case .gpr(let reg) = firstOp {
                return reg
            }
        }
        return nil
    }

    func isBranch(_ decoded: PPCInstruction.Decoded) -> Bool {
        let m = decoded.mnemonic
        return m.hasPrefix("b") && m != "boolUpdate" // b, bl, bc, beq, bne, blr, bctr, etc.
    }
}
