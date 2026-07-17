//
//  RELFixtures.swift
//
//  A REL that touches every body kind, fixup kind and chunk kind: empty /
//  text / data / bss sections; plain, @ha, @lo and ADDR32 relocations
//  against both DOL and self; binary and pointer data chunks; multiple
//  imported modules.
//

import Foundation
import GoDFoundation
import Dolphin

public enum RELFixtures {
    public static let name = "rel_sample"

    public static func model() -> RELFile {
        let own: UInt32 = 0x2A
        let dol: UInt32 = 0

        let text: [RELFile.TextInstruction] = [
            .init(raw: 0x4E800020),                                                                       // blr
            .init(raw: 0x60000000),                                                                       // nop
            .init(raw: 0x3C600000, ref: .init(moduleID: dol, section: 2, offset: 0x1234), fixup: .addr16_ha), // lis r3, sym@ha
            .init(raw: 0x38630000, ref: .init(moduleID: dol, section: 2, offset: 0x1234), fixup: .addr16_lo), // addi r3, r3, sym@l
            .init(raw: 0x90610008),                                                                       // stw r3, 8(r1)
            .init(raw: 0x38000001),                                                                       // li r0, 1
            .init(raw: 0x00000000, ref: .init(moduleID: own, section: 1, offset: 0x00), fixup: .addr32),  // self ADDR32 word
            .init(raw: 0x4E800020),                                                                       // blr
        ]

        let data: [RELFile.DataChunk] = [
            .binary(bytes: deterministicBytes(8, seed: 0x00C0_FFEE)),
            .pointer(ref: .init(moduleID: own, section: 1, offset: 0x08), restValue: 0),
            .binary(bytes: deterministicBytes(12, seed: 0x0BAD_F00D)),
        ]

        var rel = RELFile(
            moduleID: own,
            version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text(text)),
                .init(index: 2, body: .data(data)),
                .init(index: 3, body: .bss(size: 0x20)),
            ],
            importedModules: [own, dol]
        )
        rel.name = name
        rel.prologSection = 1
        rel.prologOffset = 0
        rel.sectionAlign = 4
        rel.bssAlign = 8
        return rel
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.dolphin)
    }
}
