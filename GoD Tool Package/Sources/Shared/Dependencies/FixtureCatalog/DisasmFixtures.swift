//
//  DisasmFixtures.swift
//
//  Disassembler-pipeline fixtures. `sections.txt` is the layout format the
//  DOL disassembly op emits and the assembly op parses back; the golden
//  pins that text format.
//
//  The JSON formats in the same pipeline (manifest.json, the TypeMap, the
//  RelSymbolIndex) are hand-authored fixtures instead — they are
//  user-facing/user-authored documents, so independent ground truth files
//  live directly in the test target's Fixtures folder.
//

import Foundation
import Disassembler

public enum SectionLayoutFixtures {
    public static let symbolCount = 42

    /// Exercises: multiple text/data sections, a size-less section line,
    /// and non-trivial entry point / BSS values.
    public static func model() -> SectionLayout {
        SectionLayout(
            entryPoint: 0x8000_3154,
            bssAddress: 0x8042_05C0,
            bssSize: 849_860,
            textSections: [
                .init(name: "text0", address: 0x8000_3100, size: 9_472),
                .init(name: "text1", address: 0x8000_5600, size: 1_048_576),
            ],
            dataSections: [
                .init(name: "data0", address: 0x8045_6200, size: 4_096),
                .init(name: "data5", address: 0x8045_7200, size: nil),
            ]
        )
    }

    public static func files() -> [FixtureFile] {
        let text = SectionLayoutWriter().write(model(), symbolCount: symbolCount)
        return [FixtureFile(relativePath: "\(FixtureDir.disassembler)/sections_sample.txt",
                            bytes: Array(text.utf8))]
    }
}
