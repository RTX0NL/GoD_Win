//
//  PPCSectionAssembler+Relocatable.swift
//  Dolphin
//
//  Assembly for code that does not know where it will be loaded — the REL
//  case. A DOL is linked at a fixed address, so `lis r3, sym@ha` resolves to
//  a number at assembly time. A REL is fixed up by the loader instead: the
//  field is left at rest (normally zero) and a relocation entry names the
//  symbol. This pass produces both halves — the at-rest bytes and the list
//  of (offset, kind, symbol) the caller turns into relocation entries.
//
//  Which operands relocate follows the REL format's own rules rather than
//  anything about the symbol:
//
//    - `sym@ha`, `sym@h`, `sym@l`, `sym@l(rN)` — always. A module has no
//      absolute addresses of its own, so every 32-bit address it builds is
//      patched, whether the target is the DOL, another module, or itself.
//    - `.4byte sym` — always, for the same reason, unless `sym` is an
//      `lbl_XXXXXXXX` auto-name that is not a known symbol. That form is how
//      the typed exporters spell a pointer slot they could not name (a null
//      pointer comes back as `lbl_00000000`), so it is a literal value.
//    - a branch to a label defined in the same section — never. It is
//      PC-relative, and the section moves as one piece.
//    - a branch to anything else that is a known symbol — a REL24 (`b`/`bl`)
//      or REL14 (conditional) relocation with a zero displacement.
//
//  `restWords` overrides the at-rest word at a relocation site. Almost every
//  site in the retail modules holds zero; the 87 that do not (all in
//  Colosseum's `common.rel`) keep their word here rather than in the source,
//  which has no syntax for it.
//

import Foundation
import GoDFoundation

public extension PPCSectionAssembler {

    /// What a relocation entry patches. Mirrors the REL fixup commands the
    /// syntax can express; the REL layer maps these onto its own enum.
    enum RelocationKind: String, Equatable {
        case addr16_ha, addr16_hi, addr16_lo, addr32, rel24, rel14
    }

    /// One relocation site: `offset` is the byte offset of the host word
    /// from the section start (not the patched half-word — the REL writer
    /// adds the +2 for 16-bit fixups itself).
    struct SymbolRelocation: Equatable {
        public let offset: UInt32
        public let kind: RelocationKind
        public let symbol: String

        public init(offset: UInt32, kind: RelocationKind, symbol: String) {
            self.offset = offset
            self.kind = kind
            self.symbol = symbol
        }
    }

    struct RelocatableResult {
        public let data: GoDData
        public let relocations: [SymbolRelocation]
    }

    /// Assemble `files` as one section starting at offset 0, leaving every
    /// relocated field at rest and reporting the sites.
    ///
    /// - Parameters:
    ///   - files: the section's source, in order
    ///   - isKnownSymbol: whether a name is defined somewhere the caller can
    ///     resolve — a label in any section of the module, or an entry in
    ///     the module's symbol table. Decides literal-vs-relocation for
    ///     `.4byte lbl_XXXXXXXX` and whether a non-local branch target is an
    ///     error or a relocation.
    ///   - restWords: at-rest word overrides keyed by section offset.
    func assembleRelocatable(
        files: [(name: String, content: String)],
        isKnownSymbol: (String) -> Bool,
        restWords: [UInt32: UInt32] = [:]
    ) throws -> RelocatableResult {
        let parsedFiles = files.map { (name: $0.name, lines: parser.parse($0.content)) }
        let localLabels = try collectLabels(parsedFiles: parsedFiles, baseAddress: 0)

        var bytes = [UInt8]()
        var relocations = [SymbolRelocation]()
        var address: UInt32 = 0

        func appendWord(_ word: UInt32) {
            bytes.append(UInt8((word >> 24) & 0xFF))
            bytes.append(UInt8((word >> 16) & 0xFF))
            bytes.append(UInt8((word >> 8) & 0xFF))
            bytes.append(UInt8(word & 0xFF))
        }

        for file in parsedFiles {
            for line in file.lines {
                switch line {
                case .instruction(let mnemonic, let parsedOperands):
                    var site: SymbolRelocation? = nil
                    let operands = try parsedOperands.map { op -> PPCInstruction.Operand in
                        try Self.relocatableOperand(
                            op,
                            mnemonic: mnemonic,
                            address: address,
                            localLabels: localLabels,
                            isKnownSymbol: isKnownSymbol,
                            file: file.name,
                            site: &site
                        )
                    }
                    guard let encoded = encoder.encode(mnemonic: mnemonic, operands: operands, currentAddress: address) else {
                        throw AssemblyError.encodingFailed(mnemonic: mnemonic, address: address, file: file.name)
                    }
                    if let site {
                        relocations.append(site)
                        appendWord(restWords[address] ?? encoded)
                    } else {
                        appendWord(encoded)
                    }
                    address += 4

                case .data4(let value):
                    switch value {
                    case .integer(let v):
                        appendWord(v)
                    case .symbol(let name):
                        if let literal = Self.autoLabelAddress(name), !isKnownSymbol(name) {
                            appendWord(literal)
                        } else {
                            relocations.append(SymbolRelocation(offset: address, kind: .addr32, symbol: name))
                            appendWord(restWords[address] ?? 0)
                        }
                    }
                    address += 4

                case .dataByte(let b):
                    bytes.append(b)
                    address += 1

                case .label, .global, .section, .empty:
                    break
                }
            }
        }

        return RelocatableResult(
            data: GoDData(byteStream: bytes, byteOrder: .big),
            relocations: relocations
        )
    }

    // MARK: - Operand resolution

    /// The address an `lbl_XXXXXXXX` auto-name spells, or nil for any other
    /// name.
    static func autoLabelAddress(_ name: String) -> UInt32? {
        guard name.hasPrefix("lbl_"), name.count == 12 else { return nil }
        return UInt32(name.dropFirst(4), radix: 16)
    }

    private static func relocatableOperand(
        _ op: PPCParsedOperand,
        mnemonic: String,
        address: UInt32,
        localLabels: [String: UInt32],
        isKnownSymbol: (String) -> Bool,
        file: String,
        site: inout SymbolRelocation?
    ) throws -> PPCInstruction.Operand {
        let unsignedLoMnemonics = ["ori", "oris", "xori", "xoris"]
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

        case .haReloc(let symbol):
            site = SymbolRelocation(offset: address, kind: .addr16_ha, symbol: symbol)
            return .simm(0)
        case .hReloc(let symbol):
            site = SymbolRelocation(offset: address, kind: .addr16_hi, symbol: symbol)
            return .simm(0)
        case .loReloc(let symbol):
            site = SymbolRelocation(offset: address, kind: .addr16_lo, symbol: symbol)
            return unsignedLoMnemonics.contains(mnemonic) ? .uimm(0) : .simm(0)
        case .loRelocMemory(let symbol, let base):
            site = SymbolRelocation(offset: address, kind: .addr16_lo, symbol: symbol)
            return .memory(offset: 0, base: base)

        case .label(let name):
            // A label in this section: PC-relative, no relocation.
            if let local = localLabels[name] {
                return .branchTarget(local)
            }
            // A literal address, as the formatter writes targets that have
            // no label.
            if name.hasPrefix("0x") || name.hasPrefix("0X"),
               let literal = UInt32(name.dropFirst(2), radix: 16) {
                return .branchTarget(literal)
            }
            if isKnownSymbol(name) {
                site = SymbolRelocation(offset: address, kind: Self.branchRelocationKind(mnemonic), symbol: name)
                return .branchTarget(address)
            }
            if let literal = autoLabelAddress(name) {
                return .branchTarget(literal)
            }
            throw AssemblyError.unresolvedLabel(name, file: file)
        }
    }

    /// `b`/`bl` (and their absolute forms) patch a 24-bit displacement;
    /// every other branch is a conditional form with a 14-bit one.
    private static func branchRelocationKind(_ mnemonic: String) -> RelocationKind {
        switch mnemonic {
        case "b", "bl", "ba", "bla": return .rel24
        default: return .rel14
        }
    }
}
