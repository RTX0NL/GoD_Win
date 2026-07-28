import Foundation

/// Parsed line from a .s assembly file
public enum PPCParsedLine {
    case section(String)                                    // .section .text0
    case global(String)                                     // .global funcName
    case label(String)                                      // funcName:
    case instruction(String, [PPCParsedOperand])            // mnemonic, operands
    case data4(PPCDataValue)                                // .4byte value_or_label
    case dataByte(UInt8)                                    // .byte 0xFF
    case empty                                              // blank line or comment
}

/// A value in a .4byte directive
public enum PPCDataValue {
    case integer(UInt32)
    case symbol(String)
}

/// Parsed operand from assembly source
public enum PPCParsedOperand {
    case gpr(UInt8)
    case fpr(UInt8)
    case simm(Int32)
    case uimm(UInt32)
    case label(String)                                      // branch target label
    case memory(offset: Int32, base: UInt8)
    case haReloc(String)                                    // symbol@ha
    case hReloc(String)                                     // symbol@h (raw high, no carry)
    case loReloc(String)                                    // symbol@l
    case loRelocMemory(symbol: String, base: UInt8)         // symbol@l(rN)
    case crField(UInt8)
    case crBit(UInt8)
    case spr(UInt32)
    case shift(UInt8)
    case maskBegin(UInt8)
    case maskEnd(UInt8)
    case count(UInt8)
    case gqr(UInt8)
    case wBit(UInt8)
}

/// Parses GNU-as compatible PowerPC assembly files as produced by PPCFormatter
public struct PPCAssemblyParser {

    public init() {}

    /// Parse a complete .s file into parsed lines
    public func parse(_ text: String) -> [PPCParsedLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(parseLine)
    }

    /// Parse a single line of assembly
    public func parseLine(_ line: some StringProtocol) -> PPCParsedLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty or comment
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return .empty }

        // Section directive
        if trimmed.hasPrefix(".section ") {
            return .section(String(trimmed.dropFirst(9)))
        }

        // Global directive
        if trimmed.hasPrefix(".global ") {
            return .global(String(trimmed.dropFirst(8)))
        }

        // Data directives
        if trimmed.hasPrefix(".4byte ") {
            let value = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("0x") || value.hasPrefix("0X") {
                if let v = UInt32(value.dropFirst(2), radix: 16) {
                    return .data4(.integer(v))
                }
            }
            // Must be a symbol reference
            return .data4(.symbol(value))
        }

        if trimmed.hasPrefix(".byte ") {
            let value = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("0x") || value.hasPrefix("0X") {
                if let v = UInt8(value.dropFirst(2), radix: 16) {
                    return .dataByte(v)
                }
            }
            return .empty
        }

        // Label
        if trimmed.hasSuffix(":") && !trimmed.contains(" ") {
            return .label(String(trimmed.dropLast()))
        }

        // Instruction
        return parseInstruction(trimmed)
    }

    // MARK: - Instruction parsing

    func parseInstruction(_ text: String) -> PPCParsedLine {
        // Split mnemonic from operands
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let mnemonic = parts.first else { return .empty }

        let mnemonicStr = String(mnemonic)

        if parts.count < 2 {
            // No operands (blr, bctr, nop, sync, etc.)
            return .instruction(mnemonicStr, [])
        }

        let operandStr = String(parts[1])
        let operands = parseOperands(operandStr, mnemonic: mnemonicStr)
        return .instruction(mnemonicStr, operands)
    }

    func parseOperands(_ text: String, mnemonic: String) -> [PPCParsedOperand] {
        let tokens = splitOperands(text)
        var result = [PPCParsedOperand]()
        for (i, token) in tokens.enumerated() {
            let s = String(token).trimmingCharacters(in: .whitespaces)
            // Context-dependent: rotate/mask instructions have positional operands
            if let contextOp = parseContextualOperand(s, mnemonic: mnemonic, index: i) {
                result.append(contextOp)
            } else if let op = parseOperand(s, mnemonic: mnemonic) {
                result.append(op)
            }
        }
        return result
    }

    /// Handle operands that depend on their position within specific instructions
    func parseContextualOperand(_ text: String, mnemonic: String, index: Int) -> PPCParsedOperand? {
        let base = mnemonic.hasSuffix(".") ? String(mnemonic.dropLast()) : mnemonic

        // mfspr: rD, SPR  /  mtspr: SPR, rS — numeric SPR values
        if (base == "mfspr" && index == 1) || (base == "mtspr" && index == 0) {
            // First try known name
            if let spr = parseSPR(text) { return .spr(spr) }
            // Then try numeric
            if let val = UInt32(text) { return .spr(val) }
            if text.hasPrefix("0x"), let val = UInt32(text.dropFirst(2), radix: 16) { return .spr(val) }
        }

        // rlwinm/rlwimi: rA, rS, SH, MB, ME
        // rlwnm: rA, rS, rB, MB, ME
        if (base == "rlwinm" || base == "rlwimi") && index >= 2 {
            if let val = parseUInt8(text) {
                switch index {
                case 2: return .shift(val)
                case 3: return .maskBegin(val)
                case 4: return .maskEnd(val)
                default: break
                }
            }
        }
        if base == "rlwnm" && index >= 3 {
            if let val = parseUInt8(text) {
                switch index {
                case 3: return .maskBegin(val)
                case 4: return .maskEnd(val)
                default: break
                }
            }
        }

        // slwi/srwi/clrlwi/srawi: rA, rS, SH
        if (base == "slwi" || base == "srwi" || base == "clrlwi" || base == "srawi") && index == 2 {
            if let val = parseUInt8(text) {
                return .shift(val)
            }
        }

        // lswi/stswi: rD, rA, NB (count)
        if (base == "lswi" || base == "stswi") && index == 2 {
            if let val = parseUInt8(text) {
                return .count(val)
            }
        }

        // psq_ instructions: ..., W, I (GQR)
        if base.hasPrefix("psq_") {
            if index == 2, let val = parseUInt8(text) { return .wBit(val) }
            if index == 3, let val = parseUInt8(text) { return .gqr(val) }
        }

        return nil
    }

    func parseUInt8(_ text: String) -> UInt8? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt8(text.dropFirst(2), radix: 16)
        }
        return UInt8(text)
    }

    /// Split operand string on commas, respecting parentheses
    func splitOperands(_ text: String) -> [String] {
        var result = [String]()
        var current = ""
        var depth = 0
        for ch in text {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == "," && depth == 0 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current.trimmingCharacters(in: .whitespaces))
        }
        return result
    }

    func parseOperand(_ text: String, mnemonic: String) -> PPCParsedOperand? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }

        // GPR: r0-r31
        if s.hasPrefix("r"), let num = UInt8(s.dropFirst()), num <= 31 {
            return .gpr(num)
        }

        // FPR: f0-f31
        if s.hasPrefix("f"), let num = UInt8(s.dropFirst()), num <= 31 {
            return .fpr(num)
        }

        // CR field: cr0-cr7
        if s.hasPrefix("cr") && s.count == 3, let num = UInt8(s.dropFirst(2)), num <= 7 {
            return .crField(num)
        }

        // CR bit: lt, gt, eq, so OR 4*crN+name
        if let crBit = parseCrBit(s) {
            return .crBit(crBit)
        }

        // SPR names
        if let spr = parseSPR(s) {
            return .spr(spr)
        }

        // @ha relocation: symbol@ha
        if s.hasSuffix("@ha") {
            return .haReloc(String(s.dropLast(3)))
        }

        // @h relocation: symbol@h — raw high half, no carry adjustment
        if s.hasSuffix("@h") {
            return .hReloc(String(s.dropLast(2)))
        }

        // @l relocation with memory: symbol@l(rN)
        if s.contains("@l(") && s.hasSuffix(")") {
            let atIdx = s.range(of: "@l(")!
            let symbol = String(s[s.startIndex..<atIdx.lowerBound])
            let regStr = String(s[atIdx.upperBound..<s.index(before: s.endIndex)])
            if regStr.hasPrefix("r"), let base = UInt8(regStr.dropFirst()), base <= 31 {
                return .loRelocMemory(symbol: symbol, base: base)
            }
        }

        // @l relocation: symbol@l
        if s.hasSuffix("@l") {
            return .loReloc(String(s.dropLast(2)))
        }

        // Memory operand: offset(rN) or -offset(rN)
        if s.contains("(") && s.hasSuffix(")") {
            if let result = parseMemoryOperand(s) {
                return result
            }
        }

        // Hex immediate: 0xNNNN or -0xNNNN
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            if let val = UInt32(s.dropFirst(2), radix: 16) {
                // Context-dependent: use simm for branch-like contexts, uimm otherwise
                return immediateFromContext(val, mnemonic: mnemonic)
            }
        }
        if s.hasPrefix("-0x") || s.hasPrefix("-0X") {
            if let val = UInt32(s.dropFirst(3), radix: 16) {
                return .simm(-Int32(val))
            }
        }

        // Decimal immediate
        if let val = Int32(s) {
            return .simm(val)
        }
        if let val = UInt32(s) {
            return .uimm(val)
        }

        // Must be a label reference (branch target)
        return .label(s)
    }

    // MARK: - Helpers

    func parseMemoryOperand(_ s: String) -> PPCParsedOperand? {
        guard let parenIdx = s.firstIndex(of: "(") else { return nil }
        let offsetStr = String(s[s.startIndex..<parenIdx])
        let regStr = String(s[s.index(after: parenIdx)..<s.index(before: s.endIndex)])

        guard regStr.hasPrefix("r"), let base = UInt8(regStr.dropFirst()), base <= 31 else {
            return nil
        }

        let offset: Int32
        if offsetStr.hasPrefix("-0x") || offsetStr.hasPrefix("-0X") {
            guard let val = UInt32(offsetStr.dropFirst(3), radix: 16) else { return nil }
            offset = -Int32(val)
        } else if offsetStr.hasPrefix("0x") || offsetStr.hasPrefix("0X") {
            guard let val = UInt32(offsetStr.dropFirst(2), radix: 16) else { return nil }
            offset = Int32(bitPattern: val)
        } else {
            guard let val = Int32(offsetStr) else { return nil }
            offset = val
        }

        return .memory(offset: offset, base: base)
    }

    func parseCrBit(_ s: String) -> UInt8? {
        // Simple: lt=0, gt=1, eq=2, so=3
        switch s {
        case "lt": return 0
        case "gt": return 1
        case "eq": return 2
        case "so": return 3
        default: break
        }

        // Compound: 4*crN+name
        if s.hasPrefix("4*cr") && s.contains("+") {
            let parts = s.split(separator: "+")
            guard parts.count == 2 else { return nil }
            let crStr = parts[0].dropFirst(4) // after "4*cr"
            guard let crNum = UInt8(crStr), crNum <= 7 else { return nil }
            let bitName = String(parts[1])
            let bitOffset: UInt8
            switch bitName {
            case "lt": bitOffset = 0
            case "gt": bitOffset = 1
            case "eq": bitOffset = 2
            case "so": bitOffset = 3
            default: return nil
            }
            return crNum * 4 + bitOffset
        }
        return nil
    }

    func parseSPR(_ s: String) -> UInt32? {
        // Must match all SPR names from PPCInstruction.SPR enum
        let sprMap: [String: UInt32] = [
            "xer": 1, "lr": 8, "ctr": 9,
            "dsisr": 18, "dar": 19, "dec": 22,
            "sdr1": 25, "srr0": 26, "srr1": 27,
            "sprg0": 272, "sprg1": 273, "sprg2": 274, "sprg3": 275,
            "ear": 282,
            "tbLo": 268, "tbHi": 269,
            "pvr": 287,
            "ibat0u": 528, "ibat0l": 529, "ibat1u": 530, "ibat1l": 531,
            "ibat2u": 532, "ibat2l": 533, "ibat3u": 534, "ibat3l": 535,
            "dbat0u": 536, "dbat0l": 537, "dbat1u": 538, "dbat1l": 539,
            "dbat2u": 540, "dbat2l": 541, "dbat3u": 542, "dbat3l": 543,
            "gqr0": 912, "gqr1": 913, "gqr2": 914, "gqr3": 915,
            "gqr4": 916, "gqr5": 917, "gqr6": 918, "gqr7": 919,
            "hid2": 920, "wpar": 921, "dmau": 922, "dmal": 923,
            "ummcr0": 936, "upmc1": 937, "upmc2": 938, "usia": 939,
            "ummcr1": 940, "upmc3": 941, "upmc4": 942, "usda": 943,
            "mmcr0": 952, "pmc1": 953, "pmc2": 954, "sia": 955,
            "mmcr1": 956, "pmc3": 957, "pmc4": 958, "sda": 959,
            "hid0": 1008, "hid1": 1009,
            "iabr": 1010, "dabr": 1013,
            "l2cr": 1017, "ictc": 1019,
            "thrm1": 1020, "thrm2": 1021, "thrm3": 1022,
        ]
        return sprMap[s]
    }

    /// Determine whether a hex immediate should be signed or unsigned based on mnemonic context
    func immediateFromContext(_ val: UInt32, mnemonic: String) -> PPCParsedOperand {
        // Unsigned context: ori, oris, xori, xoris, andi., andis., cmplwi, mtcrf, bc/bca/bcl/bcla (BO field), tw
        let unsignedMnemonics = ["ori", "oris", "xori", "xoris", "andi.", "andis.", "cmplwi", "mtcrf", "mtfsf",
                                  "bc", "bcl", "bca", "bcla", "bclr", "bclrl", "bcctr", "bcctrl", "tw", "twi",
                                  "mtsr", "mfsr", "mtfsfi", "mtfsfi.", "mtfsb0", "mtfsb0.", "mtfsb1", "mtfsb1."]
        if unsignedMnemonics.contains(mnemonic) {
            return .uimm(val)
        }
        // For branch mnemonics, treat hex values as branch targets
        let branchMnemonics = ["b", "bl", "ba", "bla", "beq", "bne", "blt", "bge", "bgt", "ble", "bso", "bns",
                                "beql", "bnel", "bltl", "bgel", "bgtl", "blel", "bdnz", "bdnzl", "bdz", "bdzl"]
        if branchMnemonics.contains(mnemonic) {
            return .label("0x\(String(val, radix: 16, uppercase: true))")
        }
        // Default: signed
        return .simm(Int32(bitPattern: val))
    }
}
