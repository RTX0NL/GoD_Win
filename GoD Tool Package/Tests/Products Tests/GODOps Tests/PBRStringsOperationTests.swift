//
//  PBRStringsOperationTests.swift
//  GODOpsTests
//
//  Operation-body coverage for the PBR strings dump/build pair.
//
//  Everything runs against synthetic tables built in memory, so these need
//  no ROM — the format itself is pinned against the real disc by
//  `PBRStringRealCorpusTests`. What's under test here is the *operation*:
//  which files it picks up, what the document says, that a build puts the
//  text back where it came from, and that an edit the format can't express
//  fails by name instead of shipping.
//

import XCTest
import Foundation
import GoDFoundation
import PBR
@testable import GODOps

final class PBRStringsOperationTests: XCTestCase {

    // MARK: - Fixtures

    private static let unpacked = Folder("/project/Unpacked")
    private static let messages = Folder("/project/Unpacked/Data/Text/Messages")
    private static let directoryFile = File("/project/Unpacked/Data/Common/common_091.bin")
    private static let document = File("/project/Source/Text/Strings.json")

    /// Two tables in two languages, with table 2 shipping a second copy —
    /// the shape the real disc has, in miniature.
    ///
    /// Ids interleave across the tables on purpose (1 and 3 in table 1, 2
    /// and 4 in table 2), because a catalogue that only ever saw contiguous
    /// per-table runs could pass while getting the directory wrong.
    private func discFiles() -> InMemoryFST {
        let fst = InMemoryFST()
        let tables: [(id: Int, code: String, paths: [String], strings: [String])] = [
            (1, "USUK", ["English/mes_common_001.msg"], ["First", "Third"]),
            (1, "GRGR", ["German/mes_common_g_001.msg"], ["Erste", "Dritte"]),
            (2, "USUK", ["English/mes_bpass_002.msg", "English/mes_fight_001.msg"], ["Second", "Fourth"]),
            (2, "GRGR", ["German/mes_bpass_g_002.msg", "German/mes_fight_g_001.msg"], ["Zweite", "Vierte"]),
        ]
        for table in tables {
            let binary = try! PBRStringTable(
                tableID: table.id,
                languageCode: table.code,
                strings: table.strings.map { GSString(string: $0, format: .gsPBR) }
            ).rawData()
            for path in table.paths {
                try! fst.writeFile(binary, at: Self.messages.file(path), overwrite: true)
            }
        }

        // id 1 → table 1 index 1, id 2 → table 2 index 1, id 3 → table 1
        // index 2, id 4 → table 2 index 2.
        let directory = PBRStringDirectory(tableCount: 2, records: [
            .init(tableID: 1, index: 1),
            .init(tableID: 2, index: 1),
            .init(tableID: 1, index: 2),
            .init(tableID: 2, index: 2),
        ])
        try! fst.writeFile(directory.rawData(), at: Self.directoryFile, overwrite: true)
        return fst
    }

    private func dump(_ fst: InMemoryFST) throws {
        try PBRStringsDump.dump(
            config: .init(
                unpackedFolder: Self.unpacked,
                messagesFolder: Self.messages,
                directoryFile: Self.directoryFile,
                outputFile: Self.document,
                overwrite: true
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
    }

    private func build(_ fst: InMemoryFST) throws {
        try PBRStringsBuild.build(
            config: .init(stringsFile: Self.document, unpackedFolder: Self.unpacked, overwrite: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
    }

    private func catalogue(in fst: InMemoryFST) throws -> PBRStringCatalog {
        try fst.decodeJSON(from: Self.document)
    }

    private func write(_ catalogue: PBRStringCatalog, in fst: InMemoryFST) throws {
        try fst.writeJSON(catalogue, at: Self.document, overwrite: true)
    }

    // MARK: - Dump

    func testDumpWritesOneRowPerIDWithEveryLanguage() throws {
        let fst = discFiles()
        try dump(fst)
        let catalogue = try catalogue(in: fst)

        XCTAssertEqual(catalogue.directory, "Data/Common/common_091.bin")
        XCTAssertEqual(catalogue.tables.count, 2)

        // Table id is position, so table 1's rows are ids 1 and 3.
        XCTAssertEqual(catalogue.tables[0].strings.map(\.id), [1, 3])
        XCTAssertEqual(catalogue.tables[1].strings.map(\.id), [2, 4])

        XCTAssertEqual(catalogue.tables[0].strings[0].text.text(for: "USUK"), "First")
        XCTAssertEqual(catalogue.tables[0].strings[0].text.text(for: "GRGR"), "Erste")
        XCTAssertEqual(catalogue.tables[1].strings[1].text.text(for: "GRGR"), "Vierte")
    }

    func testDumpListsEveryBinaryALanguageIsWrittenBackTo() throws {
        let fst = discFiles()
        try dump(fst)
        let catalogue = try catalogue(in: fst)

        let english = try XCTUnwrap(catalogue.tables[1].files.first { $0.code == "USUK" })
        XCTAssertEqual(english.paths, [
            "Data/Text/Messages/English/mes_bpass_002.msg",
            "Data/Text/Messages/English/mes_fight_001.msg",
        ], "a table shipped twice has to name both copies or one goes stale")

        // Languages come out in the engine's order, not alphabetically.
        XCTAssertEqual(catalogue.tables[0].files.map(\.code), ["USUK", "GRGR"])
    }

    func testDumpSkipsFilesThatArentStringTables() throws {
        let fst = discFiles()
        try fst.writeFile(GoDData(byteStream: [0, 1, 2, 3], byteOrder: .big),
                          at: Self.messages.file("English/notes.txt"), overwrite: true)
        try dump(fst)
        XCTAssertEqual(try catalogue(in: fst).tables.count, 2)
    }

    // MARK: - Round trip

    func testBuildReproducesEveryBinaryAndTheDirectory() throws {
        let fst = discFiles()
        let before = [
            Self.messages.file("English/mes_common_001.msg"),
            Self.messages.file("German/mes_common_g_001.msg"),
            Self.messages.file("English/mes_bpass_002.msg"),
            Self.messages.file("English/mes_fight_001.msg"),
            Self.messages.file("German/mes_bpass_g_002.msg"),
            Self.messages.file("German/mes_fight_g_001.msg"),
            Self.directoryFile,
        ].map { ($0, fst.readFile(at: $0)?.allData?.rawBytes) }

        try dump(fst)
        try build(fst)

        for (file, bytes) in before {
            XCTAssertNotNil(bytes, file.path)
            XCTAssertEqual(fst.readFile(at: file)?.allData?.rawBytes, bytes, file.path)
        }
    }

    func testEditedTextReachesEveryCopyOfItsLanguage() throws {
        let fst = discFiles()
        try dump(fst)

        var catalogue = try catalogue(in: fst)
        var table = catalogue.tables[1]
        table = .init(files: table.files, strings: [
            .init(id: 2, text: .perLanguage(["USUK": "Edited", "GRGR": "Zweite"])),
            table.strings[1],
        ])
        catalogue = .init(directory: catalogue.directory, tables: [catalogue.tables[0], table])
        try write(catalogue, in: fst)
        try build(fst)

        for path in ["English/mes_bpass_002.msg", "English/mes_fight_001.msg"] {
            let rebuilt = try PBRStringTable(binary: fst.readFile(at: Self.messages.file(path))!)
            XCTAssertEqual(rebuilt.strings[0].string(format: .gsPBR), "Edited", path)
        }
    }

    /// The scenario the format exists to support: a new string added to one
    /// table, with every id that was already in use keeping its meaning.
    func testAppendingAnIDLeavesEveryExistingIDPointingAtTheSameText() throws {
        let fst = discFiles()
        try dump(fst)

        var catalogue = try catalogue(in: fst)
        let table = catalogue.tables[0]
        // Inserted in the *middle* of the table, which moves the index of
        // the row after it — the directory has to absorb that.
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(files: table.files, strings: [
                table.strings[0],
                .init(id: 5, text: .perLanguage(["USUK": "Fifth", "GRGR": "Fünfte"])),
                table.strings[1],
            ]),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        try build(fst)

        let directory = try PBRStringDirectory(binary: fst.readFile(at: Self.directoryFile)!)
        XCTAssertEqual(directory.records.count, 5)
        // Ids 1–4 still resolve to the text they always did; the new id 5
        // sits where it was inserted.
        let english = try PBRStringTable(
            binary: fst.readFile(at: Self.messages.file("English/mes_common_001.msg"))!
        )
        func text(_ id: Int) throws -> String {
            let record = try XCTUnwrap(directory.record(forStringID: id))
            XCTAssertEqual(record.tableID, 1)
            return english.strings[record.index - 1].string(format: .gsPBR)
        }
        XCTAssertEqual(try text(1), "First")
        XCTAssertEqual(try text(3), "Third")
        XCTAssertEqual(try text(5), "Fifth")
    }

    // MARK: - Validation

    func testBuildRefusesAGapInTheIDs() throws {
        let fst = discFiles()
        try dump(fst)
        var catalogue = try catalogue(in: fst)
        let table = catalogue.tables[0]
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(files: table.files, strings: [
                table.strings[0],
                .init(id: 9, text: .perLanguage(["USUK": "Ninth", "GRGR": "Neunte"])),
            ]),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        XCTAssertThrowsError(try build(fst)) { error in
            XCTAssertTrue("\(error)".contains("id 3 is missing"), "\(error)")
        }
    }

    /// A language that stops short is fine — the US disc's non-English
    /// tables do exactly that — but it can't start again afterwards, because
    /// index N has to mean the same id in every language.
    func testBuildRefusesALanguageThatResumesAfterStopping() throws {
        let fst = discFiles()
        try dump(fst)
        var catalogue = try catalogue(in: fst)
        let table = catalogue.tables[0]
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(files: table.files, strings: [
                .init(id: 1, text: .perLanguage(["USUK": "First"])),
                table.strings[1],
            ]),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        XCTAssertThrowsError(try build(fst)) { error in
            XCTAssertTrue("\(error)".contains("string 3"), "\(error)")
            XCTAssertTrue("\(error)".contains("GRGR"), "\(error)")
        }
    }

    /// The US shape: one language's table runs past another's, and the
    /// shorter one simply ends. Both come back at their own lengths.
    func testALanguageMayStopBeforeTheTableEnds() throws {
        let fst = discFiles()
        try dump(fst)
        var catalogue = try catalogue(in: fst)
        let table = catalogue.tables[0]
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(files: table.files, strings: [
                table.strings[0],
                .init(id: 3, text: .perLanguage(["USUK": "English only"])),
            ]),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        try build(fst)

        let english = try PBRStringTable(
            binary: fst.readFile(at: Self.messages.file("English/mes_common_001.msg"))!
        )
        let german = try PBRStringTable(
            binary: fst.readFile(at: Self.messages.file("German/mes_common_g_001.msg"))!
        )
        XCTAssertEqual(english.strings.count, 2)
        XCTAssertEqual(german.strings.count, 1, "German stops where its text does")
        XCTAssertEqual(english.strings[1].string(format: .gsPBR), "English only")

        // And the directory still addresses both rows.
        let directory = try PBRStringDirectory(binary: fst.readFile(at: Self.directoryFile)!)
        XCTAssertEqual(directory.record(forStringID: 3), .init(tableID: 1, index: 2))
    }

    func testBuildAcceptsOneTextForEveryLanguage() throws {
        let fst = discFiles()
        try dump(fst)
        var catalogue = try catalogue(in: fst)
        let table = catalogue.tables[0]
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(files: table.files, strings: [
                .init(id: 1, text: .everyLanguage("Shared")),
                table.strings[1],
            ]),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        try build(fst)

        for path in ["English/mes_common_001.msg", "German/mes_common_g_001.msg"] {
            let rebuilt = try PBRStringTable(binary: fst.readFile(at: Self.messages.file(path))!)
            XCTAssertEqual(rebuilt.strings[0].string(format: .gsPBR), "Shared", path)
        }
    }

    func testBuildRefusesToWriteOverTheWrongFile() throws {
        let fst = discFiles()
        try dump(fst)
        var catalogue = try catalogue(in: fst)
        // Point table 1's English copy at table 2's binary.
        let table = catalogue.tables[0]
        catalogue = .init(directory: catalogue.directory, tables: [
            .init(
                files: [
                    .init(code: "USUK", paths: ["Data/Text/Messages/English/mes_bpass_002.msg"]),
                    table.files[1],
                ],
                strings: table.strings
            ),
            catalogue.tables[1],
        ])
        try write(catalogue, in: fst)
        XCTAssertThrowsError(try build(fst)) { error in
            XCTAssertTrue("\(error)".contains("holds table 2"), "\(error)")
        }
    }

    func testDumpFailsWhenThereAreNoStringTables() throws {
        let fst = InMemoryFST()
        try fst.writeFile(PBRStringDirectory(tableCount: 0, records: []).rawData(),
                          at: Self.directoryFile, overwrite: true)
        XCTAssertThrowsError(try dump(fst)) { error in
            XCTAssertTrue("\(error)".contains("no PBR string tables"), "\(error)")
        }
    }
}
