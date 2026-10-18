//
//  DeckOperationTests.swift
//  GODOpsTests
//
//  `dumpXDDecks` / `buildXDDecks`: an XD trainer deck to a folder of CSVs
//  and back. The synthetic decks below use the engines' real struct
//  definitions, so the column names and enum spellings are the ones a dump
//  of the disc produces. GODDESS_XD_DECKS points the corpus test at a folder
//  of real `DeckData_*.bin` files.
//

import XCTest
import Foundation
import GoDFoundation
import XD
import Pokemon
@testable import GODOps

final class DeckOperationTests: XCTestCase {

    private func word(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private func section(_ tag: String, count: UInt32, _ body: [UInt8]) -> [UInt8] {
        Array(tag.utf8) + word(UInt32(16 + body.count)) + word(count) + word(0) + body
    }

    /// One trainer with one Pokémon (Pikachu, level 30), one AI record, and a
    /// two-string tag table, laid out the way the disc's decks are.
    private var deckBytes: [UInt8] {
        var trainer = [UInt8](repeating: 0, count: 0x38)
        trainer[1] = 8                  // stringID → "trainer_01"
        trainer[0x1D] = 0               // pokemonIndexes[0] = 0
        trainer[0x28 + 1] = 0           // aiIndex = 0
        var pokemon = [UInt8](repeating: 0, count: 0x20)
        pokemon[1] = 25                 // species: Pikachu
        pokemon[2] = 30                 // level
        let ai = [UInt8](repeating: 0, count: 0x20)
        let strings = XDDeck.encodeStrings(["NULL", "trainer_01"])
        let sections = section("DTNR", count: 1, trainer) + section("DPKM", count: 1, pokemon)
            + section("DTAI", count: 1, ai) + section("DSTR", count: 0, strings)
        return Array("DECK".utf8) + word(UInt32(16 + sections.count)) + word(1) + word(0) + sections
    }

    private func project(deck: [UInt8], named name: String = "DeckData_Test") throws -> (InMemoryFST, [Folder]) {
        let fst = InMemoryFST()
        let engines = Folder("/project/Engines")
        let folders = [
            installEngine(try XDEngine.defaults(), under: engines, in: fst),
            installEngine(try PokemonEngine.defaults(), under: engines, in: fst),
        ]
        try fst.writeFile(GoDData(byteStream: deck, byteOrder: .big),
                          at: File("/project/Decks/\(name).bin"), overwrite: true)
        return (fst, folders)
    }

    private func dump(_ fst: InMemoryFST, engines: [Folder]) throws {
        try ColoXD.dumpXDDecks(in: Folder("/project/Decks"), outputFolder: Folder("/project/Source"),
                               overwrite: true, engines: engines, fileSystem: fst, logger: SilentLogger())
    }

    private func build(_ fst: InMemoryFST, engines: [Folder]) throws {
        try ColoXD.buildXDDecks(in: Folder("/project/Source"), outputFolder: Folder("/project/Decks"),
                                overwrite: true, engines: engines, fileSystem: fst, logger: SilentLogger())
    }

    private func text(_ fst: InMemoryFST, _ path: String) throws -> String {
        try XCTUnwrap(fst.readFile(at: File(path))?.allData, path).string(format: .utf8)
    }

    func testADeckDumpsToCSVsNamedBySection() throws {
        let (fst, engines) = try project(deck: deckBytes)
        try dump(fst, engines: engines)

        let folder = "/project/Source/DeckData_Test"
        let pokemon = try text(fst, "\(folder)/Pokemon.csv")
        XCTAssertTrue(pokemon.contains("PIKACHU"), "species by name:\n\(pokemon)")
        XCTAssertNotNil(fst.readFile(at: File("\(folder)/Trainers.csv")))
        XCTAssertNotNil(fst.readFile(at: File("\(folder)/AI.csv")))
        XCTAssertTrue(try text(fst, "\(folder)/Strings.json").contains("trainer_01"))
        XCTAssertTrue(try text(fst, "\(folder)/DeckData_Test.deck.json").contains("DeckTrainerPokemon"))
    }

    func testAnUnmodifiedDeckRebuildsByteForByte() throws {
        let (fst, engines) = try project(deck: deckBytes)
        try dump(fst, engines: engines)
        try fst.deleteFile(at: File("/project/Decks/DeckData_Test.bin"))
        try build(fst, engines: engines)
        XCTAssertEqual(fst.readFile(at: File("/project/Decks/DeckData_Test.bin"))?.allData?.rawBytes, deckBytes)
    }

    func testAnEditedCellReachesTheRebuiltDeck() throws {
        let (fst, engines) = try project(deck: deckBytes)
        try dump(fst, engines: engines)
        let csvPath = "/project/Source/DeckData_Test/Pokemon.csv"
        let edited = try text(fst, csvPath).replacingOccurrences(of: "PIKACHU,30", with: "PIKACHU,55")
        XCTAssertNotEqual(edited, try text(fst, csvPath), "the premise: species then level")
        try fst.writeFile(GoDData(string: edited, format: .utf8), at: File(csvPath), overwrite: true)
        try build(fst, engines: engines)

        let deck = try XDDeck(bytes: try XCTUnwrap(fst.readFile(at: File("/project/Decks/DeckData_Test.bin"))?.allData).rawBytes)
        XCTAssertEqual(deck.sections[1].body[2], 55)
    }

    /// The game reads each section's count from its header, so a row added
    /// to a CSV is a record the deck gains.
    func testARowAddedToACSVGrowsItsSection() throws {
        let (fst, engines) = try project(deck: deckBytes)
        try dump(fst, engines: engines)
        let csvPath = "/project/Source/DeckData_Test/Pokemon.csv"
        let lines = try text(fst, csvPath).split(separator: "\n").map(String.init)
        try fst.writeFile(GoDData(string: (lines + [lines[1]]).joined(separator: "\n") + "\n", format: .utf8),
                          at: File(csvPath), overwrite: true)
        try build(fst, engines: engines)

        let bytes = try XCTUnwrap(fst.readFile(at: File("/project/Decks/DeckData_Test.bin"))?.allData).rawBytes
        let deck = try XDDeck(bytes: bytes)
        XCTAssertEqual(deck.sections[1].count, 2)
        XCTAssertEqual(deck.sections[1].body.count, 0x40)
        XCTAssertEqual(bytes.count, deckBytes.count + 0x20)
    }

    /// Trainers name their tag by its byte offset, so a string that changes
    /// length moves every string after it. That is an error naming the
    /// string, not a deck whose trainers point at the wrong tags.
    func testAStringThatShiftsLaterStringsIsAnError() throws {
        let (fst, engines) = try project(deck: deckBytes)
        try dump(fst, engines: engines)
        let path = "/project/Source/DeckData_Test/Strings.json"
        let edited = try text(fst, path).replacingOccurrences(of: "\"NULL\"", with: "\"NULLNULL\"")
        try fst.writeFile(GoDData(string: edited, format: .utf8), at: File(path), overwrite: true)

        XCTAssertThrowsError(try build(fst, engines: engines)) { error in
            XCTAssertTrue("\(error)".contains("deck"), "\(error)")
        }
    }

    /// A section this operation has no struct for is kept as bytes, and the
    /// deck still rebuilds exactly.
    func testAnUnknownSectionIsKeptAsBytes() throws {
        let body = section("ABCD", count: 3, [9, 8, 7, 6])
        let bytes = Array("DECK".utf8) + word(UInt32(16 + body.count)) + word(9) + word(0) + body
        let (fst, engines) = try project(deck: bytes)
        try dump(fst, engines: engines)
        XCTAssertEqual(fst.readFile(at: File("/project/Source/DeckData_Test/0-ABCD.bin"))?.allData?.rawBytes, [9, 8, 7, 6])
        try build(fst, engines: engines)
        XCTAssertEqual(fst.readFile(at: File("/project/Decks/DeckData_Test.bin"))?.allData?.rawBytes, bytes)
    }

    // MARK: - Real decks

    func testEveryRealDeckDumpsAsTextAndRebuildsByteForByte() throws {
        guard let folder = ProcessInfo.processInfo.environment["GODDESS_XD_DECKS"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
            throw XCTSkip("Set GODDESS_XD_DECKS to a folder of DeckData_*.bin files")
        }
        let decks = names.filter { $0.hasPrefix("DeckData_") && $0.hasSuffix(".bin") }.sorted()
        XCTAssertFalse(decks.isEmpty)
        for name in decks {
            let original = [UInt8](try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(name)))
            let stem = String(name.dropLast(4))
            let (fst, engines) = try project(deck: original, named: stem)
            try dump(fst, engines: engines)

            let manifest = try text(fst, "/project/Source/\(stem)/\(stem).deck.json")
            XCTAssertFalse(manifest.contains(".bin"), "\(name): a section fell back to bytes\n\(manifest)")

            try fst.deleteFile(at: File("/project/Decks/\(name)"))
            try build(fst, engines: engines)
            XCTAssertEqual(fst.readFile(at: File("/project/Decks/\(name)"))?.allData?.rawBytes, original, name)
        }
    }
}
