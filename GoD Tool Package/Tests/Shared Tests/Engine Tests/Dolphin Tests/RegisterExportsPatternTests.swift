import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// Verifies the XD/Colo "register exports" prolog pattern is a clean
/// inverse: `codegen(recognize(instructions)) == instructions` for every
/// matching prolog in the corpus.
final class RegisterExportsPatternTests: XCTestCase {

    /// The two project dumps, plus whatever `GODDESS_REL_CORPUS` names (a
    /// colon-separated list) — the same knob `RELFileTests` uses.
    private static let corpusSearchPaths: [String] = {
        var paths = [
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Data/Relocatable Modules",
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Build/Unpacked/Data/Relocatable Modules",
        ]
        if let extra = ProcessInfo.processInfo.environment["GODDESS_REL_CORPUS"] {
            paths += extra.split(separator: ":").map(String.init)
        }
        return paths
    }()

    // MARK: - Hand-built micro fixture

    /// Three hand-built TextInstructions covering one export triple plus
    /// one non-matching instruction. Recognizer should consume the 4
    /// triple instructions and stop before the trailing blr.
    func testRegisterExports_recognizesOneTriple() {
        let dol = RELFile.SymbolRef(moduleID: 0, section: 9, offset: 0x8047_9FC8)
        let sym = RELFile.SymbolRef(moduleID: 42, section: 3, offset: 0x0040)
        let instructions: [RELFile.TextInstruction] = [
            .init(raw: 0x3D20_0000, ref: dol, fixup: .addr16_ha),
            .init(raw: 0x3D60_0000, ref: sym, fixup: .addr16_ha),
            .init(raw: 0x380B_0000, ref: sym, fixup: .addr16_lo),
            .init(raw: 0x9009_0000, ref: dol, fixup: .addr16_lo),
            .init(raw: 0x4E80_0020),           // blr — breaks the pattern
        ]

        let match = RegisterExportsPattern.recognize(instructions, selfModuleID: 42)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.consumed, 4)
        XCTAssertEqual(match?.exports.count, 1)
        XCTAssertEqual(match?.exports.first?.relSymbol, sym)
        XCTAssertEqual(match?.exports.first?.dolSymbol, dol)
    }

    /// Codegen reproduces the exact instruction stream the recognizer
    /// accepts.
    func testRegisterExports_codegenIsInverseOfRecognize() {
        let dol = RELFile.SymbolRef(moduleID: 0, section: 9, offset: 0x8047_9FC8)
        let sym = RELFile.SymbolRef(moduleID: 42, section: 3, offset: 0x0040)
        let export = RegisterExportsPattern.Export(relSymbol: sym, dolSymbol: dol)
        let emitted = RegisterExportsPattern.codegen([export])

        let recognized = RegisterExportsPattern.recognize(emitted, selfModuleID: 42)
        XCTAssertEqual(recognized?.exports, [export])
        XCTAssertEqual(recognized?.consumed, emitted.count)
    }

    /// Recognizer rejects non-matching input (e.g. wrong register
    /// allocation).
    func testRegisterExports_rejectsForeignPrologShape() {
        let dol = RELFile.SymbolRef(moduleID: 0, section: 9, offset: 0)
        let instructions: [RELFile.TextInstruction] = [
            // lis r3 instead of r9 — different register.
            .init(raw: 0x3C60_0000, ref: dol, fixup: .addr16_ha),
            .init(raw: 0x3D60_0000, ref: dol, fixup: .addr16_ha),
            .init(raw: 0x380B_0000, ref: dol, fixup: .addr16_lo),
            .init(raw: 0x9009_0000, ref: dol, fixup: .addr16_lo),
        ]
        XCTAssertNil(RegisterExportsPattern.recognize(instructions, selfModuleID: 42))
    }

    // MARK: - Corpus test

    /// For every REL in the corpus, if the prolog section contains an
    /// instruction stream starting with the register-exports pattern,
    /// recognizer → codegen must reproduce that prefix byte-identically.
    func testRegisterExports_corpusPrologRoundtrips() throws {
        var covered = 0
        var exportsSeen = 0
        var mismatches: [String] = []
        for dir in Self.corpusSearchPaths {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".rel") {
                let path = "\(dir)/\(name)"
                guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let rel = try? RELFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
                                             name: name) else { continue }
                // Locate the prolog instructions inside its section.
                guard rel.prologOffset % 4 == 0,
                      Int(rel.prologSection) < rel.sections.count,
                      case .text(let instructions) = rel.sections[Int(rel.prologSection)].body else {
                    continue
                }
                // XD/Colo prolog/epilog wrap the register-exports body
                // in a 3-instruction stack-frame preamble (stwu / stw /
                // mr). Skip past that to find the first triple.
                let funcStart = Int(rel.prologOffset) / 4
                let start = funcStart + 3
                guard start < instructions.count else { continue }
                let tail = Array(instructions[start...])
                guard let match = RegisterExportsPattern.recognize(tail, selfModuleID: rel.moduleID) else {
                    continue
                }
                let regenerated = RegisterExportsPattern.codegen(match.exports)
                let originalSlice = Array(tail.prefix(match.consumed))
                if regenerated != originalSlice {
                    mismatches.append(name)
                    continue
                }
                covered += 1
                exportsSeen += match.exports.count
            }
        }
        XCTAssertTrue(covered > 0, "corpus had no matching prologs — check search paths")
        XCTAssertTrue(mismatches.isEmpty, "codegen didn't round-trip on: \(mismatches.prefix(5))")
        // Informational: how many RELs had a register-exports prolog and
        // how many total exports the pattern collapsed.
        print("[pattern] \(covered) REL prologs matched, \(exportsSeen) exports total")
    }
}
