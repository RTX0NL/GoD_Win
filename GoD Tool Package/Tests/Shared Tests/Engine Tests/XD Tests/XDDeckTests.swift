//
//  XDDeckTests.swift
//
//  The `DECK` container: a header, then tagged sections back to back.
//  Synthetic decks pin the layout; GODDESS_XD_DECKS points the corpus test
//  at a folder of real `DeckData_*.bin` files.
//

import XCTest
import Foundation
import GoDFoundation
@testable import XD

final class XDDeckTests: XCTestCase {

    private func word(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// A deck with one 2-record section of 4-byte records and a string table.
    private var sampleBytes: [UInt8] {
        let records: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let strings: [UInt8] = Array("NULL".utf8) + [0, 0, 0, 0] + Array("abc".utf8) + [0]
        var out = Array("DECK".utf8) + word(UInt32(16 + 16 + records.count + 16 + strings.count)) + word(1) + word(0)
        out += Array("DTNR".utf8) + word(UInt32(16 + records.count)) + word(2) + word(0) + records
        out += Array("DSTR".utf8) + word(UInt32(16 + strings.count)) + word(0) + word(0) + strings
        return out
    }

    func testADeckParsesIntoItsSections() throws {
        let deck = try XDDeck(bytes: sampleBytes)
        XCTAssertEqual(deck.deckID, 1)
        XCTAssertEqual(deck.sections.map(\.tag), ["DTNR", "DSTR"])
        XCTAssertEqual(deck.sections[0].count, 2)
        XCTAssertEqual(deck.sections[0].body, [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(deck.sections[1].count, 0)
    }

    func testADeckSerializesToTheBytesItWasParsedFrom() throws {
        XCTAssertEqual(try XDDeck(bytes: sampleBytes).bytes, sampleBytes)
    }

    /// Sizes in the headers follow the bodies, so a section that gains a
    /// record is written with its new size and the file with its new total.
    func testSizesAreDerivedFromTheBodies() throws {
        var deck = try XDDeck(bytes: sampleBytes)
        deck.sections[0].body += [9, 10, 11, 12]
        deck.sections[0].count = 3
        let bytes = deck.bytes
        XCTAssertEqual(bytes.count, sampleBytes.count + 4)
        XCTAssertEqual(Array(bytes[4 ..< 8]), word(UInt32(bytes.count)))
        XCTAssertEqual(Array(bytes[20 ..< 24]), word(16 + 12))
        XCTAssertEqual(try XDDeck(bytes: bytes), deck)
    }

    func testMalformedDecksAreRejected() {
        var wrongSize = sampleBytes
        wrongSize[7] &+= 1
        var runsPastTheEnd = sampleBytes
        runsPastTheEnd[23] = 0xFF
        for (label, bytes) in [
            ("no magic", Array("KCED".utf8) + Array(sampleBytes.dropFirst(4))),
            ("size", wrongSize),
            ("section size", runsPastTheEnd),
            ("too short", Array(sampleBytes.prefix(8))),
        ] {
            XCTAssertThrowsError(try XDDeck(bytes: bytes), label)
        }
    }

    // MARK: - String table

    func testStringsArePaddedToFourBytes() {
        let texts = ["NULL", "haihu_01", "Mirabo_Esaba_a_01", "N100"]
        let body = XDDeck.encodeStrings(texts)
        XCTAssertEqual(XDDeck.stringOffsets(texts), [0, 8, 20, 40])
        XCTAssertEqual(body.count, 48)
        XCTAssertEqual(XDDeck.decodeStrings(body), zip([0, 8, 20, 40], texts).map {
            XDDeck.TaggedString(offset: $0, text: $1)
        })
    }

    /// A table that doesn't follow the layout isn't forced into strings.
    func testAStringTableWithOtherPaddingIsNotDecoded() {
        XCTAssertNil(XDDeck.decodeStrings(Array("ab".utf8) + [0, 0, 0]), "not a multiple of 4")
        XCTAssertNil(XDDeck.decodeStrings(Array("ab".utf8) + [0, 7, 0, 0]), "non-zero padding")
        XCTAssertNil(XDDeck.decodeStrings(Array("no terminator".utf8)))
    }

    // MARK: - Real decks

    func testEveryRealDeckRoundTripsAndItsStringsDecode() throws {
        guard let folder = ProcessInfo.processInfo.environment["GODDESS_XD_DECKS"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
            throw XCTSkip("Set GODDESS_XD_DECKS to a folder of DeckData_*.bin files")
        }
        let decks = names.filter { $0.hasPrefix("DeckData_") && $0.hasSuffix(".bin") }.sorted()
        XCTAssertFalse(decks.isEmpty)
        for name in decks {
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(name)))
            let deck = try XDDeck(bytes: bytes)
            XCTAssertEqual(deck.bytes, bytes, name)
            if let strings = deck.sections.first(where: { $0.tag == "DSTR" }) {
                XCTAssertNotNil(XDDeck.decodeStrings(strings.body), "\(name): DSTR doesn't decode")
            }
        }
    }
}
