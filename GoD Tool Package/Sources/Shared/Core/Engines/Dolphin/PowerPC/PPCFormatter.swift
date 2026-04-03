import Foundation

/// Formats decoded PowerPC instructions as GNU-as compatible assembly text
public struct PPCFormatter {

    public init() {}

    /// Format a single instruction as a clean assembly line (no address/hex prefix)
    public func format(_ instruction: PPCInstruction, labels: [UInt32: String] = [:]) -> String {
        guard let decoded = instruction.decoded else {
            return ".4byte 0x\(hex(instruction.raw))"
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
    public func formatAssembly(
        _ instructions: [PPCInstruction],
        symbols: [UInt32: String] = [:],
        sectionName: String
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

            let asm = format(inst, labels: labels)
            lines.append("    \(asm)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Per-function splitting

    /// Split instructions into per-function chunks based on symbols.
    /// Returns array of (functionName, assemblyText) pairs.
    public func splitByFunction(
        _ instructions: [PPCInstruction],
        symbols: [PPCSymbol],
        sectionName: String
    ) -> [(name: String, text: String)] {
        guard !symbols.isEmpty else { return [] }

        // Sort symbols by address
        let sortedSymbols = symbols.sorted(by: { $0.address < $1.address })
        let symbolLookup = Dictionary(uniqueKeysWithValues: symbols.map { ($0.address, $0.name) })

        // Build full label map (symbols + branch targets)
        let branchTargets = collectBranchTargets(instructions)
        let instructionAddresses = Set(instructions.map(\.address))
        var labels = symbolLookup
        for target in branchTargets {
            if labels[target] == nil, instructionAddresses.contains(target) {
                labels[target] = "lbl_\(hex(target, width: 8))"
            }
        }

        // Build instruction lookup by address
        let instructionsByAddress = Dictionary(uniqueKeysWithValues: instructions.map { ($0.address, $0) })

        var results = [(name: String, text: String)]()

        for (i, symbol) in sortedSymbols.enumerated() {
            let startAddr = symbol.address
            let endAddr: UInt32
            if symbol.size > 0 {
                endAddr = startAddr + symbol.size
            } else if i + 1 < sortedSymbols.count {
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
                // Insert local labels (but not the function's own label)
                if inst.address != startAddr, let label = labels[inst.address] {
                    if symbolLookup[inst.address] != nil {
                        lines.append(".global \(label)")
                    }
                    lines.append("\(label):")
                }
                let asm = format(inst, labels: labels)
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
