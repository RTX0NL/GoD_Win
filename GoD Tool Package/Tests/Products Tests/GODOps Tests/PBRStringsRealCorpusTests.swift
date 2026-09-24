//
//  PBRStringsRealCorpusTests.swift
//  GODOpsTests
//
//  Runs the strings operations over a real disc's files.
//
//  `PBRStringsOperationTests` covers the operation's behaviour on synthetic
//  input and `PBRStringRealCorpusTests` covers the format against the disc;
//  what's left — and what this covers — is the operation meeting the real
//  thing: every language of every table discovered and grouped correctly,
//  the duplicate copies both written, and the whole disc's text surviving a
//  round trip through the document.
//
//  Works off a decrypted `DATA/files` folder, so it needs no unpacked
//  project. GODDESS_PBR_FILES overrides the path; the test skips cleanly
//  without one, and is region-agnostic — point it at a US, PAL or JP disc.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import PBR
@testable import GODOps

final class PBRStringsRealCorpusTests: XCTestCase {

    private static let unpacked = Folder("/disc")
    private static let messages = Folder("/disc/Data/Text/Messages")
    private static let document = File("/project/Source/Text/Strings.json")

    private static func filesFolder() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"],
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files",
            NSHomeDirectory() + "/Documents/GoD Tool/PBR dumped PBR Tool/Game Files/Dump/DATA/files",
        ].compactMap { $0 }
        return candidates.first { path in
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            return exists && isFolder.boolValue
        }
    }

    /// Lays the disc's string files out the way an unpack does: the message
    /// binaries under a folder per language, the directory under Data/Common.
    ///
    /// Archives are filtered by name rather than by scanning every entry of
    /// all 1100+ of them, which would mean LZSS-decompressing the whole disc.
    /// PAL keeps every copy under `mes_*` and `menu_btutorial*`; US ships
    /// four more English copies in `menu_bpass2`, `menu_name2` and
    /// `menu_fight_s`; JP has no `mes_*` archives at all and keeps its main
    /// table in `common.fsys`, which is read here anyway for the directory.
    private func discFiles() throws -> (fst: InMemoryFST, originals: [(File, [UInt8])], directory: File) {
        guard let folder = Self.filesFolder() else {
            throw XCTSkip("No PBR disc files — set GODDESS_PBR_FILES to a DATA/files folder.")
        }
        let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let fst = InMemoryFST()
        var originals = [(File, [UInt8])]()

        let names = try FileManager.default.contentsOfDirectory(atPath: folder)
            .filter { $0.hasSuffix(".fsys") }
            .filter { name in
                ["mes_", "menu_btutorial", "menu_bpass", "menu_name", "menu_fight", "common"]
                    .contains { name.hasPrefix($0) }
            }
            .sorted()
        var common: FSYSArchive?
        for name in names {
            guard let bytes = FileManager.default.contents(atPath: folder + "/" + name),
                  let archive = try? FSYSArchive(
                      data: GoDData(data: bytes, byteOrder: .big), engine: engine
                  )
            else { continue }
            if name == "common.fsys" { common = archive }
            for (index, entry) in archive.entries.enumerated()
            where PBRStringTable.isStringTable(entry.data) {
                let table = try PBRStringTable(binary: entry.data)
                let stem = name.replacingOccurrences(of: ".fsys", with: "")
                let file = Self.messages
                    .folder(table.languageCode)
                    .file(stem + "_" + String(format: "%03d", index) + ".msg")
                try fst.writeFile(entry.data, at: file, overwrite: true)
                originals.append((file, entry.data.rawBytes))
            }
        }
        guard !originals.isEmpty else {
            throw XCTSkip("No MESG members under \(folder).")
        }

        // The directory, out of common.fsys. US/PAL and JP put it at
        // different member indexes; whichever one parses is the one.
        guard let common else {
            throw XCTSkip("No common.fsys under \(folder).")
        }
        let engineData = PBREngine.Data()
        for japanese in [false, true] {
            let index = japanese ? engineData.japaneseStringDirectoryIndex : engineData.stringDirectoryIndex
            guard index < common.entries.count else { continue }
            let member = common.entries[index].data
            guard (try? PBRStringDirectory(binary: member)) != nil else { continue }
            let file = Self.unpacked.folder("Data").folder("Common")
                .file(engineData.stringDirectoryFileName(japanese: japanese))
            try fst.writeFile(member, at: file, overwrite: true)
            originals.append((file, member.rawBytes))
            return (fst, originals, file)
        }
        throw XCTSkip("No string directory in common.fsys.")
    }

    private func dump(_ fst: InMemoryFST, directory: File) throws {
        try PBRStringsDump.dump(
            config: .init(
                unpackedFolder: Self.unpacked,
                messagesFolder: Self.messages,
                directoryFile: directory,
                outputFile: Self.document,
                overwrite: true
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
    }

    /// Disc → document → disc, through the operations, byte for byte.
    func testOperationsRoundTripTheWholeDisc() throws {
        let (fst, originals, directory) = try discFiles()
        try dump(fst, directory: directory)
        try PBRStringsBuild.build(
            config: .init(stringsFile: Self.document, unpackedFolder: Self.unpacked, overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        for (file, bytes) in originals {
            XCTAssertEqual(fst.readFile(at: file)?.allData?.rawBytes, bytes, file.path)
        }
    }

    /// The document describes the disc it came from: four tables, every id
    /// accounted for exactly once, and every language file named.
    func testDocumentCoversEveryStringAndFile() throws {
        let (fst, originals, directory) = try discFiles()
        try dump(fst, directory: directory)
        let catalogue: PBRStringCatalog = try fst.decodeJSON(from: Self.document)

        XCTAssertEqual(catalogue.tables.count, 4, "retail discs ship four string tables")

        // Ids are a dense 1…N across the whole document.
        let ids = catalogue.tables.flatMap { $0.strings.map(\.id) }.sorted()
        XCTAssertEqual(ids, Array(1...ids.count), "ids must cover 1…N exactly once")

        // Every message binary laid down is named by exactly one language of
        // one table — nothing dumped is left unreferenced, which is what a
        // build needs in order to write all of them back.
        let referenced = Set(catalogue.tables.flatMap { $0.files.flatMap(\.paths) })
        let laidDown = Set(originals.map(\.0.path)
            .filter { $0.hasPrefix(Self.messages.path) }
            .map { String($0.dropFirst(Self.unpacked.path.count + 1)) })
        XCTAssertEqual(referenced, laidDown)

        // Each table carries the same language set, and each row has a text
        // for each of them.
        for (position, table) in catalogue.tables.enumerated() {
            let codes = Set(table.files.map(\.code))
            // A table the directory declares but the disc doesn't ship keeps
            // its slot as an empty section — the JP disc does this with the
            // battle tutorial's table — so that the tables after it aren't
            // renumbered.
            guard !codes.isEmpty else {
                XCTAssertTrue(table.strings.isEmpty,
                              "table \(position + 1) has strings but no file to write them to")
                continue
            }
            // A row carries text for the languages whose table reaches it —
            // which on the US disc isn't all of them, since its English
            // tables run past the others.
            for entry in table.strings {
                guard let named = entry.text.codes else { continue }
                XCTAssertTrue(named.isSubset(of: codes),
                              "string \(entry.id) names a language the table has no file for")
                XCTAssertFalse(named.isEmpty, "string \(entry.id) has no text at all")
            }
        }
    }
}
