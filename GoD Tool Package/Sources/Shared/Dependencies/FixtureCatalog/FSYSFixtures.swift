//
//  FSYSFixtures.swift
//
//  FSYS archive + FsysTOC fixtures. Both are engine-bound; they use the
//  fully in-memory `GeniusSonorityEngine.defaultEngine(for:)` — no disk.
//

import Foundation
import GoDFoundation
import GeniusSonority

// MARK: - FSYS archive

public enum FSYSFixtures {
    public static let name = "fsys_sample"
    /// Must exist in the Colo FsysGroupIDs enum (allowUnknownCases: false).
    /// 0x69 = "D1_garage_1F.fsys".
    public static let groupID = 0x69

    public static func engine() -> GeniusSonorityEngine {
        GeniusSonorityEngine.defaultEngine(for: .colosseum)
    }

    /// Four entries: mixed file types, mixed compression, deterministic
    /// payloads. Entry A's length (0x44) is deliberately not 0x20-aligned
    /// to exercise data-block padding.
    public static func entries() -> [FSYSArchive.Entry] {
        // A: uncompressed msg, unaligned length.
        let a = FSYSArchive.Entry(
            metadata: .init(name: "town_talk", fileType: "msg", identifier: 1,
                            compress: false, includesFullFilename: nil),
            filename: "town_talk.msg",
            data: GoDData(byteStream: deterministicBytes(0x44, seed: 0xF515_000A),
                          byteOrder: .big)
        )
        // B: compressed scd, highly compressible repeating pattern.
        var pattern: [UInt8] = []
        for i in 0..<0x180 { pattern.append(UInt8(i % 5)) }
        let b = FSYSArchive.Entry(
            metadata: .init(name: "battle_script", fileType: "scd", identifier: 2,
                            compress: true, includesFullFilename: nil),
            filename: "battle_script.scd",
            data: GoDData(byteStream: pattern, byteOrder: .big)
        )
        // C: compressed dat, incompressible noise (LZSS still wraps it).
        let c = FSYSArchive.Entry(
            metadata: .init(name: "model_data", fileType: "dat", identifier: 3,
                            compress: true, includesFullFilename: nil),
            filename: "model_data.dat",
            data: GoDData(byteStream: deterministicBytes(0x100, seed: 0xF515_000C),
                          byteOrder: .big)
        )
        // D: uncompressed gtx, zero run.
        let d = FSYSArchive.Entry(
            metadata: .init(name: "menu_texture", fileType: "gtx", identifier: 4,
                            compress: false, includesFullFilename: nil),
            filename: "menu_texture.gtx",
            data: GoDData(byteStream: [UInt8](repeating: 0, count: 0x40),
                          byteOrder: .big)
        )
        return [a, b, c, d]
    }

    public static func model() -> FSYSArchive {
        FSYSArchive(
            groupID: groupID,
            metadata: FSYSArchive.MetaData(
                unknownFlag1: false, unknownFlag2: false, debugFlag: false,
                unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0
            ),
            entries: entries()
        )
    }

    public static func files() throws -> [FixtureFile] {
        let blob = try model().data(groupID: groupID, engine: engine())
        return [FixtureFile(relativePath: "\(FixtureDir.colosseum)/\(name).fsys",
                            bytes: blob.rawBytes)]
    }
}

// MARK: - FsysTOC

public enum FsysTOCFixtures {
    /// Filename → groupID map used for both goldens. Values chosen to
    /// exercise ordering (writer sorts by groupID) and multi-byte IDs.
    public static let idsByFilename: [String: Int] = [
        "common.fsys": 0x01,
        "D1_garage_1F.fsys": 0x69,
        "pkx_lugia.fsys": 0x3E8,
    ]

    public static func model(engine: GeniusSonorityEngine) -> FsysTOC {
        FsysTOC(fsysIDsByFilename: idsByFilename, unknown: engine.data.toc.unknown)
    }

    /// Two goldens cover both on-disc entry layouts: Colosseum's small
    /// 8-byte TOC entry and XD's full 16-byte entry.
    public static func files() throws -> [FixtureFile] {
        let colo = GeniusSonorityEngine.defaultEngine(for: .colosseum)
        let xd = GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness)
        return [
            FixtureFile(relativePath: "\(FixtureDir.colosseum)/gsfsys_colo.toc",
                        bytes: try model(engine: colo).tocData(with: colo).rawBytes),
            FixtureFile(relativePath: "\(FixtureDir.colosseum)/gsfsys_xd.toc",
                        bytes: try model(engine: xd).tocData(with: xd).rawBytes),
        ]
    }
}
