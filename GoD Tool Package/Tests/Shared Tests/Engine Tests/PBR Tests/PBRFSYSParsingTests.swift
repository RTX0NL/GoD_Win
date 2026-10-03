//
//  PBRFSYSParsingTests.swift
//  PBRTests
//
//  PBR is the third game to use the FSYS container, and its archives had never
//  been exercised through `FSYSArchive` (the `pbrDump` op was a stub). PBR
//  entries are the XD-sized 0x70 stride reached through a pointer table, so
//  this pins that the shared, struct-driven parser actually reads them: entry
//  count, per-entry file types, the "(null)" filename placeholder, and LZSS
//  decompression — all checked against the real PAL disc.
//
//  Skips cleanly without the unpacked project; point elsewhere with
//  GODDESS_PBR_FILES (a folder of extracted `.fsys` archives).
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority

final class PBRFSYSParsingTests: XCTestCase {

    private var filesFolder: String? {
        let path = ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func archive(_ name: String, in folder: String, engine: GeniusSonorityEngine) throws -> FSYSArchive? {
        let path = folder + "/" + name
        guard let bytes = FileManager.default.contents(atPath: path) else { return nil }
        return try FSYSArchive(data: GoDData(data: bytes, byteOrder: .big), engine: engine)
    }

    private func engine() -> GeniusSonorityEngine {
        GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
    }

    /// `common.fsys` is fully characterised from the PAL disc, so it's the
    /// tightest single-archive check: 93 entries with a known type histogram,
    /// every filename the "(null)" placeholder, and decompressible payloads.
    func testParsesCommonFsysAgainstGroundTruth() throws {
        guard let folder = filesFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let archive = try XCTUnwrap(try archive("common.fsys", in: folder, engine: engine()),
                                    "common.fsys not found in \(folder)")

        XCTAssertEqual(archive.entries.count, 93, "common.fsys entry count")

        // An entry whose stored type the enum doesn't name has a nil `fileType`;
        // bucket those under a sentinel so the histogram still accounts for them.
        let untyped = "(none)"
        var typeCounts = [String: Int]()
        for entry in archive.entries {
            typeCounts[entry.metadata.fileType ?? untyped, default: 0] += 1
            // Every PBR entry stores the literal placeholder rather than a name.
            XCTAssertEqual(entry.metadata.name, "(null)", "entry name is the scrubbed placeholder")
        }

        XCTAssertEqual(typeCounts["bin"], 33, "0x02 bin data tables")
        XCTAssertEqual(typeCounts["gtx"], 56, "0x0C textures")
        XCTAssertEqual(typeCounts["scd"], 1, "0x12 script")
        XCTAssertEqual(typeCounts["fnt"], 1, "0x16 font")
        // 0x00 is no named type at all, so it reads back as nil rather than a
        // synthesized `FileTypes_0`. These 2 sit beside the 33 `bin` above, and
        // both dump with a `.bin` suffix — the type is recovered from the
        // registry, never the filename, so sharing the suffix is safe while
        // sharing an enum case name would not be.
        XCTAssertEqual(typeCounts[untyped], 2, "0x00 reads back as no type")
        XCTAssertEqual(archive.entries.filter { $0.metadata.fileType == nil }
                        .allSatisfy { $0.metadata.fileExtension == "bin" }, true,
                       "an untyped entry falls back to the .bin extension")

        // Payloads decompress to non-empty data (LZSS through the shared path).
        for entry in archive.entries {
            XCTAssertGreaterThan(entry.data.length, 0, "entry \(entry.metadata.identifier) decompressed")
        }
    }

    /// The new `efsq` (0x14) case: real `wzx_btlintro.fsys` carries it, and
    /// before it was named (with allowUnknownCases:false) the parser threw.
    func testParsesEfsqArchive() throws {
        guard let folder = filesFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let archive = try XCTUnwrap(try archive("wzx_btlintro.fsys", in: folder, engine: engine()))
        let efsqCount = archive.entries.filter { $0.metadata.fileType == "efsq" }.count
        XCTAssertGreaterThan(efsqCount, 0, "wzx_btlintro.fsys contains efsq entries")
    }

    /// The whole-corpus de-risk: parse every archive on the disc and assert
    /// none throws (the point the stub could never prove). Also confirms the
    /// documented PBR type names actually appear.
    func testParsesEntireCorpusWithoutThrowing() throws {
        guard let folder = filesFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let engine = engine()
        let urls = (FileManager.default.enumerator(atPath: folder)?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".fsys") } ?? []).sorted()
        try XCTSkipIf(urls.isEmpty, "no .fsys archives under \(folder)")

        var typeNames = Set<String>()
        var parsed = 0
        for name in urls {
            let a = try XCTUnwrap(try archive(name, in: folder, engine: engine),
                                  "failed to read \(name)")
            a.entries.forEach { if let t = $0.metadata.fileType { typeNames.insert(t) } }
            parsed += 1
        }

        XCTAssertGreaterThan(parsed, 1000, "parsed the whole PBR corpus")
        for expected in ["sdr", "gtx", "scd", "efsq", "msg", "mnr", "dckp", "dckt"] {
            XCTAssertTrue(typeNames.contains(expected), "expected PBR type \(expected) to appear")
        }
    }
}
