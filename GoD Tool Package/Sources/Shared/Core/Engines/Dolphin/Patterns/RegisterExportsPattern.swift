//
//  RegisterExportsPattern.swift
//
//  XD/Colo REL "register exports" prolog pattern.
//
//  Each REL's prolog runs at load time and writes pointers to its own
//  data symbols into DOL globals, so the DOL can reach this module's
//  state without relinking. The code generator produces a rigid
//  4-instruction triple per exported symbol:
//
//      lis  r9,  dol_addr@ha       ; r9 = dol_addr >> 16 (with carry)
//      lis  r11, rel_sym@ha        ; r11 = rel_sym >> 16 (with carry)
//      addi r0,  r11, rel_sym@l    ; r0 = rel_sym
//      stw  r0,  dol_addr@l(r9)    ; *(dol_addr) = rel_sym
//
//  All immediates are relocated (@ha/@l via R_PPC_ADDR16_HA/LO), so the
//  at-rest instruction words are fixed:
//
//      0x3D200000  0x3D600000  0x380B0000  0x90090000
//
//  The pattern is purely declarative: `(relSymbol, dolAddress)` pairs.
//  Recognizer and codegen are inverses on byte-identical inputs.
//

import Foundation

public enum RegisterExportsPattern {

    /// One exported symbol: the REL-internal target and the DOL global
    /// slot that receives its address.
    public struct Export: Codable, Equatable {
        /// Target of the lis/addi pair (always self-module).
        public var relSymbol: RELFile.SymbolRef
        /// Target of the stw's base+offset (always module 0 / DOL).
        public var dolSymbol: RELFile.SymbolRef

        public init(relSymbol: RELFile.SymbolRef, dolSymbol: RELFile.SymbolRef) {
            self.relSymbol = relSymbol
            self.dolSymbol = dolSymbol
        }
    }

    /// Fixed instruction words the codegen emits; recognizer requires
    /// the on-disc instructions to equal these (all relocated immediates
    /// are zero at rest).
    private enum Raw {
        static let lisR9:   UInt32 = 0x3D20_0000   // lis  r9,  0
        static let lisR11:  UInt32 = 0x3D60_0000   // lis  r11, 0
        static let addiR0:  UInt32 = 0x380B_0000   // addi r0,  r11, 0
        static let stwR0:   UInt32 = 0x9009_0000   // stw  r0,  0(r9)
    }

    // MARK: - Recognize

    /// Walk forward through `instructions` starting at `startIndex`,
    /// matching as many 4-instruction register-exports triples as
    /// possible. Stops at the first instruction that doesn't continue
    /// the pattern.
    ///
    /// - Parameters:
    ///   - selfModuleID: the REL's own moduleID, used to validate that
    ///     rel_sym references point back into this module.
    /// - Returns: The recognized exports and how many instructions they
    ///   consumed (always a multiple of 4). `nil` if nothing matches
    ///   at `startIndex`.
    public static func recognize(
        _ instructions: [RELFile.TextInstruction],
        startIndex: Int = 0,
        selfModuleID: UInt32
    ) -> (exports: [Export], consumed: Int)? {
        var exports: [Export] = []
        var i = startIndex
        while i + 4 <= instructions.count {
            let lisDol = instructions[i]
            let lisSym = instructions[i + 1]
            let addiSym = instructions[i + 2]
            let stwDol = instructions[i + 3]

            guard lisDol.raw == Raw.lisR9,
                  lisSym.raw == Raw.lisR11,
                  addiSym.raw == Raw.addiR0,
                  stwDol.raw == Raw.stwR0 else { break }

            guard let dolHa = lisDol.ref, lisDol.fixup == .addr16_ha,
                  let symHa = lisSym.ref, lisSym.fixup == .addr16_ha,
                  let symLo = addiSym.ref, addiSym.fixup == .addr16_lo,
                  let dolLo = stwDol.ref, stwDol.fixup == .addr16_lo else { break }

            // DOL references (module 0) must match on both halves.
            guard dolHa.moduleID == 0, dolLo.moduleID == 0,
                  dolHa.section == dolLo.section,
                  dolHa.offset == dolLo.offset else { break }

            // Self references must match on both halves and belong to
            // this module.
            guard symHa.moduleID == selfModuleID, symLo.moduleID == selfModuleID,
                  symHa.section == symLo.section,
                  symHa.offset == symLo.offset else { break }

            exports.append(Export(relSymbol: symHa, dolSymbol: dolHa))
            i += 4
        }
        return exports.isEmpty ? nil : (exports, i - startIndex)
    }

    // MARK: - Codegen

    /// Emit the instruction stream for a list of exports. Every triple
    /// produces the exact raw words the recognizer expects, so
    /// `codegen(recognize(x)) == x` on matching input.
    public static func codegen(_ exports: [Export]) -> [RELFile.TextInstruction] {
        var out: [RELFile.TextInstruction] = []
        out.reserveCapacity(exports.count * 4)
        for e in exports {
            out.append(.init(raw: Raw.lisR9,  ref: e.dolSymbol, fixup: .addr16_ha))
            out.append(.init(raw: Raw.lisR11, ref: e.relSymbol, fixup: .addr16_ha))
            out.append(.init(raw: Raw.addiR0, ref: e.relSymbol, fixup: .addr16_lo))
            out.append(.init(raw: Raw.stwR0,  ref: e.dolSymbol, fixup: .addr16_lo))
        }
        return out
    }
}
