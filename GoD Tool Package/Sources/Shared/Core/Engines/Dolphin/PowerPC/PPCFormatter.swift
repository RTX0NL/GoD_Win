import Foundation

/// Formats decoded PowerPC instructions as GNU-as compatible assembly text
public struct PPCFormatter {

    public init() {}

    /// Format a single instruction as a clean assembly line (no address/hex prefix)
    public func format(
        _ instruction: PPCInstruction,
        labels: [UInt32: String] = [:],
        relocations: [UInt32: PPCRelocation] = [:]
    ) -> String {
        guard let decoded = instruction.decoded else {
            return ".4byte 0x\(hex(instruction.raw))"
        }

        // Check for relocation annotation
        if let reloc = relocations[instruction.address], let symbolName = reloc.symbolName {
            return formatRelocated(decoded, reloc: reloc, symbolName: symbolName, labels: labels)
        }

        let operandStrings = decoded.operands.map { op -> String in
            if case .branchTarget(let addr) = op, let label = labels[addr] {
                return label
            }
            return formatOperand(op)
        }

        if operandStrings.isEmpty {
            return decoded.mnemonic
        }
        return "\(decoded.mnemonic) \(operandStrings.joined(separator: ", "))"
    }

    // MARK: - Relocation formatting

    private func formatRelocated(
        _ decoded: PPCInstruction.Decoded,
        reloc: PPCRelocation,
        symbolName: String,
        labels: [UInt32: String]
    ) -> String {
        let ops = decoded.operands

        switch reloc.halfType {
        case .ha:
            // lis rD, symbol@ha
            if ops.count == 2, case .gpr(let rd) = ops[0] {
                return "\(decoded.mnemonic) r\(rd), \(symbolName)@ha"
            }
        case .h:
            // lis rD, symbol@h — raw high half for unsigned (ori) pairs
            if ops.count == 2, case .gpr(let rd) = ops[0] {
                return "\(decoded.mnemonic) r\(rd), \(symbolName)@h"
            }
        case .lo:
            // addi rD, rA, symbol@l
            if decoded.mnemonic == "addi", ops.count == 3,
               case .gpr(let rd) = ops[0], case .gpr(let ra) = ops[1] {
                return "addi r\(rd), r\(ra), \(symbolName)@l"
            }
            // ori rA, rS, symbol@l
            if decoded.mnemonic == "ori", ops.count == 3,
               case .gpr(let ra) = ops[0], case .gpr(let rs) = ops[1] {
                return "ori r\(ra), r\(rs), \(symbolName)@l"
            }
            // lwz rD, symbol@l(rA) (and other load/store with displacement)
            if ops.count == 2, case .memory(_, let base) = ops[1] {
                let regStr: String
                if case .gpr(let rd) = ops[0] { regStr = "r\(rd)" }
                else if case .fpr(let fd) = ops[0] { regStr = "f\(fd)" }
                else { regStr = formatOperand(ops[0]) }
                return "\(decoded.mnemonic) \(regStr), \(symbolName)@l(r\(base))"
            }
            // psq_l fD, symbol@l(rA), W, GQR
            if ops.count == 4, case .fpr(let fd) = ops[0],
               case .memory(_, let base) = ops[1],
               case .wBit(let w) = ops[2], case .gqr(let g) = ops[3] {
                return "\(decoded.mnemonic) f\(fd), \(symbolName)@l(r\(base)), \(w), \(g)"
            }
        }

        // Fallback — shouldn't normally reach here
        let operandStrings = decoded.operands.map { op -> String in
            if case .branchTarget(let addr) = op, let label = labels[addr] {
                return label
            }
            return formatOperand(op)
        }
        return "\(decoded.mnemonic) \(operandStrings.joined(separator: ", "))"
    }

    // MARK: - Branch target collection

    /// Collect all branch target addresses from a set of instructions
    public func collectBranchTargets(_ instructions: [PPCInstruction]) -> Set<UInt32> {
        var targets = Set<UInt32>()
        for inst in instructions {
            guard let decoded = inst.decoded else { continue }
            for op in decoded.operands {
                if case .branchTarget(let addr) = op {
                    targets.insert(addr)
                }
            }
        }
        return targets
    }

    // MARK: - Assembly output (clean, with auto-generated labels)

    /// Format a text section as clean assembly with auto-generated labels for branch targets.
    /// Symbols from a symbol map take precedence over auto-generated labels.
    /// `extraLabels` carries names for addresses outside this section (e.g.
    /// cross-section branch targets) so they render symbolically, and for
    /// addresses inside it so externally-referenced spots get definitions.
    public func formatAssembly(
        _ instructions: [PPCInstruction],
        symbols: [UInt32: String] = [:],
        relocations: [UInt32: PPCRelocation] = [:],
        sectionName: String,
        extraLabels: [UInt32: String] = [:]
    ) -> String {
        // Build combined label map: symbols + auto-generated branch target labels
        let branchTargets = collectBranchTargets(instructions)
        let instructionAddresses = Set(instructions.map(\.address))
        var labels = symbols

        for target in branchTargets {
            if labels[target] == nil, instructionAddresses.contains(target) {
                labels[target] = "lbl_\(hex(target, width: 8))"
            }
        }

        // Also add labels for relocation targets
        for (_, reloc) in relocations {
            if labels[reloc.targetAddress] == nil, let name = reloc.symbolName {
                labels[reloc.targetAddress] = name
            }
        }

        for (addr, name) in extraLabels where labels[addr] == nil {
            labels[addr] = name
        }

        var lines = [String]()
        lines.reserveCapacity(instructions.count + instructions.count / 10)

        lines.append(".section \(sectionName)")
        lines.append("")

        for inst in instructions {
            if let label = labels[inst.address] {
                if symbols[inst.address] != nil {
                    lines.append("")
                    lines.append(".global \(label)")
                }
                lines.append("\(label):")
            }

            let asm = format(inst, labels: labels, relocations: relocations)
            lines.append("    \(asm)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Per-function splitting

    /// Split instructions into per-function chunks based on symbols.
    /// Returns array of (functionName, assemblyText) pairs.
    /// `extraLabels` — see `formatAssembly`.
    public func splitByFunction(
        _ instructions: [PPCInstruction],
        symbols: [PPCSymbol],
        relocations: [UInt32: PPCRelocation] = [:],
        sectionName: String,
        extraLabels: [UInt32: String] = [:]
    ) -> [(name: String, text: String)] {
        guard !symbols.isEmpty else { return [] }

        // Sort symbols by address, keeping one per address — duplicate
        // addresses would emit the same range twice.
        var seenAddresses = Set<UInt32>()
        let sortedSymbols = symbols
            .sorted(by: { $0.address < $1.address })
            .filter { seenAddresses.insert($0.address).inserted }
        let symbolLookup = Dictionary(sortedSymbols.map { ($0.address, $0.name) }, uniquingKeysWith: { first, _ in first })

        // Build full label map (symbols + branch targets + relocation targets)
        let branchTargets = collectBranchTargets(instructions)
        let instructionAddresses = Set(instructions.map(\.address))
        var labels = symbolLookup
        for target in branchTargets {
            if labels[target] == nil, instructionAddresses.contains(target) {
                labels[target] = "lbl_\(hex(target, width: 8))"
            }
        }
        for (_, reloc) in relocations {
            if labels[reloc.targetAddress] == nil, let name = reloc.symbolName {
                labels[reloc.targetAddress] = name
            }
        }
        for (addr, name) in extraLabels where labels[addr] == nil {
            labels[addr] = name
        }

        // Build instruction lookup by address
        let instructionsByAddress = Dictionary(uniqueKeysWithValues: instructions.map { ($0.address, $0) })

        var results = [(name: String, text: String)]()

        // Instructions before the first symbol still need a home, or the
        // reassembled section comes out short.
        if let firstInst = instructions.first, firstInst.address < sortedSymbols[0].address {
            let preName = "lbl_\(hex(firstInst.address, width: 8))"
            var lines = [String]()
            lines.append(".section \(sectionName)")
            lines.append("")
            lines.append(".global \(preName)")
            lines.append("\(preName):")
            for inst in instructions where inst.address < sortedSymbols[0].address {
                if inst.address != firstInst.address, let label = labels[inst.address] {
                    lines.append("\(label):")
                }
                lines.append("    \(format(inst, labels: labels, relocations: relocations))")
            }
            results.append((name: preName, text: lines.joined(separator: "\n")))
        }

        for (i, symbol) in sortedSymbols.enumerated() {
            let startAddr = symbol.address
            // Map sizes are unreliable: auto-generated maps nest labels
            // inside functions, so trusting `size` duplicates the overlap
            // into both files (and gaps drop bytes). The next symbol's
            // start is the only end that tiles the section exactly.
            let endAddr: UInt32
            if i + 1 < sortedSymbols.count {
                endAddr = sortedSymbols[i + 1].address
            } else {
                endAddr = instructions.last.map { $0.address + 4 } ?? startAddr
            }

            // Collect instructions in this function's range
            var funcInstructions = [PPCInstruction]()
            var addr = startAddr
            while addr < endAddr {
                if let inst = instructionsByAddress[addr] {
                    funcInstructions.append(inst)
                }
                addr += 4
            }

            guard !funcInstructions.isEmpty else { continue }

            var lines = [String]()
            lines.append(".section \(sectionName)")
            lines.append("")
            lines.append(".global \(symbol.name)")
            lines.append("\(symbol.name):")

            for inst in funcInstructions {
                if inst.address != startAddr, let label = labels[inst.address] {
                    if symbolLookup[inst.address] != nil {
                        lines.append(".global \(label)")
                    }
                    lines.append("\(label):")
                }
                let asm = format(inst, labels: labels, relocations: relocations)
                lines.append("    \(asm)")
            }

            results.append((name: symbol.name, text: lines.joined(separator: "\n")))
        }

        return results
    }

    // MARK: - Data section formatting

    /// Format data section as .4byte directives with optional labels
    public func formatDataSection(
        _ data: [UInt8],
        baseAddress: UInt32,
        symbols: [UInt32: String],
        sectionName: String
    ) -> String {
        var lines = [String]()
        lines.append(".section \(sectionName)")
        lines.append("")

        var offset = 0
        while offset + 3 < data.count {
            let address = baseAddress + UInt32(offset)

            if let label = symbols[address] {
                lines.append("")
                lines.append(".global \(label)")
                lines.append("\(label):")
            }

            let value = UInt32(data[offset]) << 24
                      | UInt32(data[offset + 1]) << 16
                      | UInt32(data[offset + 2]) << 8
                      | UInt32(data[offset + 3])

            if let targetLabel = symbols[value] {
                lines.append("    .4byte \(targetLabel)")
            } else {
                lines.append("    .4byte 0x\(hex(value))")
            }
            offset += 4
        }

        while offset < data.count {
            lines.append("    .byte 0x\(hex(UInt32(data[offset]), width: 2))")
            offset += 1
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Operand formatting

private extension PPCFormatter {
    func formatOperand(_ operand: PPCInstruction.Operand) -> String {
        switch operand {
        case .gpr(let reg):
            return "r\(reg)"
        case .fpr(let reg):
            return "f\(reg)"
        case .ps(let reg):
            return "f\(reg)"
        case .simm(let val):
            if val < 0 {
                return "-0x\(hex(UInt32(bitPattern: -val)))"
            }
            return "0x\(hex(UInt32(bitPattern: val)))"
        case .uimm(let val):
            return "0x\(hex(val))"
        case .branchTarget(let addr):
            return "0x\(hex(addr, width: 8))"
        case .memory(let offset, let base):
            let offsetStr: String
            if offset < 0 {
                offsetStr = "-0x\(String(Int(-Int32(offset)), radix: 16))"
            } else {
                offsetStr = "0x\(String(Int(offset), radix: 16))"
            }
            return "\(offsetStr)(r\(base))"
        case .crField(let cr):
            return "cr\(cr)"
        case .crBit(let bit):
            let field = bit / 4
            let subBit = bit % 4
            let subNames = ["lt", "gt", "eq", "so"]
            if field == 0 { return subNames[Int(subBit)] }
            return "4*cr\(field)+\(subNames[Int(subBit)])"
        case .spr(let spr):
            if let name = PPCInstruction.sprName(spr) {
                return name
            }
            return "\(spr)"
        case .shift(let sh):
            return "\(sh)"
        case .maskBegin(let mb):
            return "\(mb)"
        case .maskEnd(let me):
            return "\(me)"
        case .count(let n):
            return "\(n)"
        case .gqr(let i):
            return "\(i)"
        case .wBit(let w):
            return "\(w)"
        }
    }

    func hex(_ value: UInt32, width: Int = 0) -> String {
        let str = String(value, radix: 16, uppercase: true)
        if str.count < width {
            return String(repeating: "0", count: width - str.count) + str
        }
        return str
    }
}
