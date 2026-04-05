import Foundation
import GoDFoundation

/// Assembles parsed .s files into section binary data.
/// Two-pass: first collects labels and addresses, then encodes instructions.
public struct PPCSectionAssembler {

    public enum AssemblyError: Error, CustomStringConvertible {
        case unresolvedLabel(String, file: String)
        case encodingFailed(mnemonic: String, address: UInt32, file: String)
        case noSectionAddress(String)

        public var description: String {
            switch self {
            case .unresolvedLabel(let label, let file):
                return "Unresolved label '\(label)' in \(file)"
            case .encodingFailed(let mnemonic, let address, let file):
                return "Failed to encode '\(mnemonic)' at 0x\(String(address, radix: 16)) in \(file)"
            case .noSectionAddress(let section):
                return "No base address found for section '\(section)'"
            }
        }
    }

    private let parser = PPCAssemblyParser()
    private let encoder = PPCEncoder()

    public init() {}

    /// Assemble a collection of .s files into section binary data.
    ///
    /// - Parameters:
    ///   - files: Array of (filename, content) pairs
    ///   - baseAddress: The RAM address where this section starts
    ///   - externalSymbols: Labels from other sections for cross-section references
    /// - Returns: The assembled binary bytes
    public func assemble(
        files: [(name: String, content: String)],
        baseAddress: UInt32,
        externalSymbols: [String: UInt32] = [:]
    ) throws -> GoDData {
        // Parse all files
        let parsedFiles = files.map { (name: $0.name, lines: parser.parse($0.content)) }

        // Pass 1: Collect labels and compute addresses
        var labels = try collectLabels(parsedFiles: parsedFiles, baseAddress: baseAddress)

        // Merge external symbols (local labels take precedence)
        for (name, addr) in externalSymbols where labels[name] == nil {
            labels[name] = addr
        }

        // Pass 2: Encode everything
        return try encode(parsedFiles: parsedFiles, baseAddress: baseAddress, labels: labels)
    }

    /// Collect labels from .s files without encoding — used to build global symbol table
    public func collectLabelsOnly(
        files: [(name: String, content: String)],
        baseAddress: UInt32
    ) -> [String: UInt32] {
        let parsedFiles = files.map { (name: $0.name, lines: parser.parse($0.content)) }
        return (try? collectLabels(parsedFiles: parsedFiles, baseAddress: baseAddress)) ?? [:]
    }

    // MARK: - Pass 1: Label collection

    private func collectLabels(
        parsedFiles: [(name: String, lines: [PPCParsedLine])],
        baseAddress: UInt32
    ) throws -> [String: UInt32] {
        var labels = [String: UInt32]()
        var currentAddress = baseAddress

        for file in parsedFiles {
            for line in file.lines {
                switch line {
                case .label(let name):
                    labels[name] = currentAddress
                case .instruction(_, _):
                    currentAddress += 4
                case .data4(_):
                    currentAddress += 4
                case .dataByte(_):
                    currentAddress += 1
                case .section, .global, .empty:
                    break
                }
            }
        }

        return labels
    }

    // MARK: - Pass 2: Encoding

    private func encode(
        parsedFiles: [(name: String, lines: [PPCParsedLine])],
        baseAddress: UInt32,
        labels: [String: UInt32]
    ) throws -> GoDData {
        var bytes = [UInt8]()
        var currentAddress = baseAddress

        for file in parsedFiles {
            for line in file.lines {
                switch line {
                case .instruction(let mnemonic, let parsedOperands):
                    let operands = try resolveOperands(parsedOperands, labels: labels, currentAddress: currentAddress, file: file.name, mnemonic: mnemonic)
                    guard let encoded = encoder.encode(mnemonic: mnemonic, operands: operands, currentAddress: currentAddress) else {
                        throw AssemblyError.encodingFailed(mnemonic: mnemonic, address: currentAddress, file: file.name)
                    }
                    bytes.append(UInt8((encoded >> 24) & 0xFF))
                    bytes.append(UInt8((encoded >> 16) & 0xFF))
                    bytes.append(UInt8((encoded >> 8) & 0xFF))
                    bytes.append(UInt8(encoded & 0xFF))
                    currentAddress += 4

                case .data4(let value):
                    let word: UInt32
                    switch value {
                    case .integer(let v):
                        word = v
                    case .symbol(let name):
                        guard let addr = labels[name] else {
                            throw AssemblyError.unresolvedLabel(name, file: file.name)
                        }
                        word = addr
                    }
                    bytes.append(UInt8((word >> 24) & 0xFF))
                    bytes.append(UInt8((word >> 16) & 0xFF))
                    bytes.append(UInt8((word >> 8) & 0xFF))
                    bytes.append(UInt8(word & 0xFF))
                    currentAddress += 4

                case .dataByte(let b):
                    bytes.append(b)
                    currentAddress += 1

                case .label, .global, .section, .empty:
                    break
                }
            }
        }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    // MARK: - Operand resolution

    /// Convert parsed operands to PPCInstruction.Operand, resolving labels and relocations
    private func resolveOperands(
        _ parsed: [PPCParsedOperand],
        labels: [String: UInt32],
        currentAddress: UInt32,
        file: String,
        mnemonic: String = ""
    ) throws -> [PPCInstruction.Operand] {
        let unsignedLoMnemonics = ["ori", "oris", "xori", "xoris"]
        return try parsed.map { op -> PPCInstruction.Operand in
            switch op {
            case .gpr(let r):    return .gpr(r)
            case .fpr(let r):    return .fpr(r)
            case .simm(let v):   return .simm(v)
            case .uimm(let v):   return .uimm(v)
            case .crField(let f): return .crField(f)
            case .crBit(let b):  return .crBit(b)
            case .spr(let s):    return .spr(s)
            case .shift(let s):  return .shift(s)
            case .maskBegin(let m): return .maskBegin(m)
            case .maskEnd(let m): return .maskEnd(m)
            case .count(let c):  return .count(c)
            case .gqr(let g):    return .gqr(g)
            case .wBit(let w):   return .wBit(w)

            case .memory(let offset, let base):
                return .memory(offset: Int16(clamping: offset), base: base)

            case .label(let name):
                if let addr = labels[name] {
                    return .branchTarget(addr)
                }
                // Try parsing as hex address (e.g. "0x80003100")
                if name.hasPrefix("0x") || name.hasPrefix("0X"),
                   let addr = UInt32(name.dropFirst(2), radix: 16) {
                    return .branchTarget(addr)
                }
                // Try resolving lbl_XXXXXXXX from the hex address in the name
                if name.hasPrefix("lbl_"), name.count == 12,
                   let addr = UInt32(name.dropFirst(4), radix: 16) {
                    return .branchTarget(addr)
                }
                throw AssemblyError.unresolvedLabel(name, file: file)

            case .haReloc(let symbol):
                guard let addr = resolveSymbol(symbol, labels: labels) else {
                    throw AssemblyError.unresolvedLabel(symbol, file: file)
                }
                return .simm(computeHa(addr))

            case .loReloc(let symbol):
                guard let addr = resolveSymbol(symbol, labels: labels) else {
                    throw AssemblyError.unresolvedLabel(symbol, file: file)
                }
                if unsignedLoMnemonics.contains(mnemonic) {
                    return .uimm(UInt32(addr & 0xFFFF))
                }
                return .simm(computeLo(addr))

            case .loRelocMemory(let symbol, let base):
                guard let addr = resolveSymbol(symbol, labels: labels) else {
                    throw AssemblyError.unresolvedLabel(symbol, file: file)
                }
                return .memory(offset: Int16(bitPattern: UInt16(addr & 0xFFFF)), base: base)
            }
        }
    }

    /// Resolve a symbol name to an address: check labels first, then try lbl_XXXXXXXX pattern
    private func resolveSymbol(_ name: String, labels: [String: UInt32]) -> UInt32? {
        if let addr = labels[name] { return addr }
        if name.hasPrefix("lbl_"), name.count == 12,
           let addr = UInt32(name.dropFirst(4), radix: 16) {
            return addr
        }
        return nil
    }

    /// Compute @ha value: upper 16 bits adjusted for sign extension of lower half.
    /// Returns a signed 16-bit value as Int32 (suitable for lis immediate field).
    private func computeHa(_ addr: UInt32) -> Int32 {
        let hi = addr >> 16
        let lo = addr & 0xFFFF
        let adjusted = lo >= 0x8000 ? hi &+ 1 : hi
        // Return as signed 16-bit value
        return Int32(Int16(bitPattern: UInt16(adjusted & 0xFFFF)))
    }

    /// Compute @l value: lower 16 bits as signed (suitable for addi/memory offset)
    private func computeLo(_ addr: UInt32) -> Int32 {
        Int32(Int16(bitPattern: UInt16(addr & 0xFFFF)))
    }
}
