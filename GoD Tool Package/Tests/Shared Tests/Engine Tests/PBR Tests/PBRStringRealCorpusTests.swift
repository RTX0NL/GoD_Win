//
//  PBRStringRealCorpusTests.swift
//  PBRTests
//
//  Reads the real string tables and their directory off the disc, and
//  checks that what the tool writes back is what was there.
//
//  The disc's own files are the only honest test of this format: the
//  control-word vocabulary is large (110 distinct codes on the PAL disc),
//  most of it is unidentified, and a wrong parameter length desynchronises
//  the walk rather than failing — which the offsets would hide, since each
//  string is found by offset rather than by reading the one before it. A
//  byte-identical repack of every string in every language is what rules
//  that out.
//
//  Points at `DATA/files` — the archives, not an unpacked project — so it
//  works against a plain disc dump. GODDESS_PBR_FILES overrides.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
@testable import PBR

final class PBRStringRealCorpusTests: XCTestCase {

    /// One `MESG` member, with where it came from.
    struct Source {
        let archive: String
        let index: Int
        let data: GoDData
    }

    /// Archives holding string tables. Named rather than discovered because
    /// finding them means LZSS-decompressing every entry of all 1100+
    /// archives, which is minutes in a debug build for no extra coverage.
    /// The list spans the regions: PAL keeps every copy under `mes_*` and
    /// `menu_btutorial*`, US ships four more English copies in `menu_bpass2`,
    /// `menu_name2` and `menu_fight_s`, and JP has no `mes_*` archives at all
    /// — its main table is a member of `common.fsys`.
    private static let messageArchivePrefixes = [
        "mes_", "menu_btutorial", "menu_bpass", "menu_name", "menu_fight", "common",
    ]

    private static func filesFolder() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"],
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files",
            NSHomeDirectory() + "/Documents/GoD Tool/PBR dumped PBR Tool/Game Files/Dump/DATA/files",
            NSHomeDirectory() + "/Downloads/GODDESS-JP-dump/PBR PAL project/Build/Contents/DATA/files",
        ].compactMap { $0 }
        return candidates.first { path in
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            return exists && isFolder.boolValue
        }
    }

    /// Every `MESG` member of the message archives, in archive-name order.
    private func stringTableSources() throws -> [Source] {
        guard let folder = Self.filesFolder() else {
            throw XCTSkip("No PBR disc files — set GODDESS_PBR_FILES to a DATA/files folder.")
        }
        let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder)
            .filter { name in
                name.hasSuffix(".fsys")
                    && Self.messageArchivePrefixes.contains { name.hasPrefix($0) }
            }
            .sorted()

        var sources = [Source]()
        for name in names {
            guard let bytes = FileManager.default.contents(atPath: folder + "/" + name),
                  let archive = try? FSYSArchive(
                      data: GoDData(data: bytes, byteOrder: .big), engine: engine
                  )
            else { continue }
            for (index, entry) in archive.entries.enumerated()
            where PBRStringTable.isStringTable(entry.data) {
                sources.append(Source(archive: name, index: index, data: entry.data))
            }
        }
        guard !sources.isEmpty else {
            throw XCTSkip("No MESG members found under \(folder).")
        }
        return sources
    }

    /// The string directory, read out of `common.fsys`.
    private func directoryMember() throws -> GoDData {
        guard let folder = Self.filesFolder() else {
            throw XCTSkip("No PBR disc files — set GODDESS_PBR_FILES to a DATA/files folder.")
        }
        guard let bytes = FileManager.default.contents(atPath: folder + "/common.fsys") else {
            throw XCTSkip("No common.fsys under \(folder).")
        }
        let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let archive = try FSYSArchive(data: GoDData(data: bytes, byteOrder: .big), engine: engine)
        let data = PBREngine.Data()
        // US/PAL and JP order common.fsys differently; whichever member is
        // there has to satisfy the directory's own size invariant, so try
        // both and let the parse decide.
        for index in [data.stringDirectoryIndex, data.japaneseStringDirectoryIndex] {
            guard index < archive.entries.count else { continue }
            let member = archive.entries[index].data
            if (try? PBRStringDirectory(binary: member)) != nil { return member }
        }
        throw XCTSkip("No string directory in common.fsys (checked members "
                      + "\(data.stringDirectoryIndex) and \(data.japaneseStringDirectoryIndex)).")
    }

    /// Every string of every table, re-encoded, is the bytes it came from.
    func testEveryStringTableRepacksByteIdentically() throws {
        let sources = try stringTableSources()
        var strings = 0
        for source in sources {
            let context = "\(source.archive)[\(source.index)]"
            let table = try PBRStringTable(binary: source.data)
            XCTAssertEqual(try table.rawData().rawBytes, source.data.rawBytes,
                           "\(context) (table \(table.tableID), \(table.languageCode))")
            strings += table.strings.count
        }
        XCTAssertGreaterThan(strings, 0)
        print("PBR strings: \(sources.count) tables, \(strings) strings repacked")
    }

    /// The directory is a dense array over the ids, and repacks exactly.
    func testDirectoryRepacksByteIdentically() throws {
        let member = try directoryMember()
        let directory = try PBRStringDirectory(binary: member)
        XCTAssertEqual(directory.rawData().rawBytes, member.rawBytes)
        XCTAssertEqual(directory.tableCount, 4, "retail discs ship four string tables")
        XCTAssertGreaterThan(directory.records.count, 0)

        // Every record points at a table the disc actually has, and no two
        // ids share a slot — the mapping the catalogue relies on.
        var seen = Set<String>()
        for (position, record) in directory.records.enumerated() {
            let key = "\(record.tableID):\(record.index)"
            XCTAssertTrue(record.tableID >= 1 && record.tableID <= directory.tableCount,
                          "id \(position + 1) names table \(record.tableID)")
            XCTAssertGreaterThanOrEqual(record.index, 1, "id \(position + 1) has index 0")
            XCTAssertTrue(seen.insert(key).inserted, "two ids share \(key)")
        }
    }

    /// The whole round trip: disc → catalogue → disc.
    ///
    /// This is the one that matters for the operations, because it exercises
    /// the parts the individual repacks don't — the directory driving which
    /// string becomes which row, the ids being re-derived from row order,
    /// and the text surviving as tokens rather than as bytes.
    func testCatalogueRoundTripsEveryTableAndTheDirectory() throws {
        let sources = try stringTableSources()
        let directoryMember = try directoryMember()
        let directory = try PBRStringDirectory(binary: directoryMember)

        // Group the disc's copies the way the dump operation does: by table
        // id, then by language, with one path list per language.
        var parsed = [(source: Source, table: PBRStringTable)]()
        for source in sources {
            parsed.append((source, try PBRStringTable(binary: source.data)))
        }
        let byTable = Dictionary(grouping: parsed) { $0.table.tableID }
        var tableSources = [PBRStringCatalog.TableSource]()
        for tableID in byTable.keys.sorted() {
            let copies = byTable[tableID] ?? []
            let byLanguage = Dictionary(grouping: copies) { $0.table.languageCode }
            let languages = byLanguage.keys.sorted().map { code -> PBRStringCatalog.LanguageSource in
                let forLanguage = (byLanguage[code] ?? []).sorted { $0.source.archive < $1.source.archive }
                return PBRStringCatalog.LanguageSource(
                    code: code,
                    paths: forLanguage.map { "\($0.source.archive)[\($0.source.index)]" },
                    table: forLanguage[0].table
                )
            }
            tableSources.append(.init(tableID: tableID, languages: languages))
        }

        let catalogue = try PBRStringCatalog.make(
            directory: directory,
            directoryPath: "Data/Common/common_091.bin",
            tables: tableSources
        )

        // Through JSON, so the document's own encoding is part of the test.
        let encoded = try XCTUnwrap(catalogue.encodeJSON())
        let decoded = try XCTUnwrap(PBRStringCatalog.decodeJSON(from: encoded))
        XCTAssertEqual(decoded, catalogue)

        let resolution = try decoded.resolve()
        XCTAssertEqual(resolution.directory.rawData().rawBytes, directoryMember.rawBytes,
                       "directory re-derived from the catalogue")

        // And every language copy of every table, byte for byte.
        var rebuilt = 0
        for table in resolution.tables {
            for language in table.languages {
                let original = try XCTUnwrap(
                    parsed.first { $0.table.tableID == table.tableID
                                && $0.table.languageCode == language.code },
                    "table \(table.tableID) \(language.code)"
                )
                let output = PBRStringTable(
                    tableID: table.tableID,
                    languageCode: language.code,
                    idHighBits: original.table.idHighBits,
                    strings: language.strings
                )
                XCTAssertEqual(try output.rawData().rawBytes, original.source.data.rawBytes,
                               "table \(table.tableID) \(language.code)")
                rebuilt += 1
            }
        }
        XCTAssertEqual(rebuilt, byTable.values.reduce(0) { $0 + Set($1.map(\.table.languageCode)).count })
    }
}
