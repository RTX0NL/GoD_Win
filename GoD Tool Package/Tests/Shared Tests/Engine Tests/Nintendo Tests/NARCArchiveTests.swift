//
//  NARCArchiveTests.swift
//  NintendoTests
//
//  Synthetic coverage for NARC. The real corpus is entirely big-endian and
//  entirely nameless, so these carry the little-endian path and the named
//  path, plus the ordering guarantee the format leans on: with no names, an
//  entry's index *is* its identity.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Nintendo

final class NARCArchiveTests: XCTestCase {

    private func engine() throws -> NintendoEngine { try .defaults() }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func namelessEntries() -> [NARCArchive.Entry] {
        [
            .init(name: nil, data: payload("zero")),
            .init(name: nil, data: payload("one, which is longer")),
            .init(name: nil, data: payload("two")),
        ]
    }

    private func namedEntries() -> [NARCArchive.Entry] {
        [
            .init(name: "first.bin", data: payload("first")),
            .init(name: "second.bin", data: payload("second contents")),
        ]
    }

    private func assertRoundTrips(
        _ entries: [NARCArchive.Entry],
        byteOrder: ByteOrder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let engine = try engine()
        let packed = try NARCArchive(byteOrder: byteOrder, entries: entries).data(engine: engine)
        let reparsed = try NARCArchive(data: packed, engine: engine)

        XCTAssertEqual(reparsed.byteOrder, byteOrder, "byte order lost", file: file, line: line)
        XCTAssertEqual(reparsed.entries.count, entries.count, "entry count changed", file: file, line: line)
        for (index, (rebuilt, source)) in zip(reparsed.entries, entries).enumerated() {
            XCTAssertEqual(
                rebuilt.data.rawBytes, source.data.rawBytes,
                "entry \(index) payload", file: file, line: line
            )
            XCTAssertEqual(rebuilt.name, source.name, "entry \(index) name", file: file, line: line)
        }

        let again = try reparsed.data(engine: engine)
        XCTAssertEqual(again.rawBytes, packed.rawBytes, "repack is not stable", file: file, line: line)
    }

    // MARK: - Round trips

    func testRoundTripNamelessBigEndian() throws {
        try assertRoundTrips(namelessEntries(), byteOrder: .big)
    }

    func testRoundTripNamelessLittleEndian() throws {
        try assertRoundTrips(namelessEntries(), byteOrder: .little)
    }

    func testRoundTripNamedBigEndian() throws {
        try assertRoundTrips(namedEntries(), byteOrder: .big)
    }

    func testRoundTripNamedLittleEndian() throws {
        try assertRoundTrips(namedEntries(), byteOrder: .little)
    }

    func testRoundTripEmptyArchive() throws {
        try assertRoundTrips([], byteOrder: .big)
    }

    func testRoundTripEmptyPayloads() throws {
        try assertRoundTrips(
            [
                .init(name: nil, data: GoDData(byteStream: [UInt8](), byteOrder: .big)),
                .init(name: nil, data: payload("after an empty one")),
            ],
            byteOrder: .big
        )
    }

    /// Sizes that aren't a multiple of the alignment force padding between
    /// files, which is where an offset table most easily goes wrong.
    func testRoundTripUnalignedSizes() throws {
        try assertRoundTrips(
            (0 ..< 12).map { .init(name: nil, data: payload(String(repeating: "x", count: $0 + 1))) },
            byteOrder: .big
        )
    }

    /// The archives this was built for address files purely by index — in
    /// PBR's `waza_seq_rev.narc` the index is the move ID — so order has to
    /// survive exactly, including entries that share their contents.
    func testIndexOrderSurvivesIdenticalPayloads() throws {
        let engine = try engine()
        let entries: [NARCArchive.Entry] = [
            .init(name: nil, data: payload("same")),
            .init(name: nil, data: payload("unique")),
            .init(name: nil, data: payload("same")),
        ]
        let packed = try NARCArchive(byteOrder: .big, entries: entries).data(engine: engine)
        let reparsed = try NARCArchive(data: packed, engine: engine)
        XCTAssertEqual(reparsed.entries.map { $0.data.string(format: .utf8) }, ["same", "unique", "same"])
    }

    // MARK: - Layout

    func testMagicMatchesTheByteOrder() throws {
        let engine = try engine()
        let big = try NARCArchive(byteOrder: .big, entries: namelessEntries()).data(engine: engine)
        let little = try NARCArchive(byteOrder: .little, entries: namelessEntries()).data(engine: engine)
        XCTAssertEqual(Array(big.rawBytes.prefix(4)), Array("CRAN".utf8))
        XCTAssertEqual(Array(little.rawBytes.prefix(4)), Array("NARC".utf8))
    }

    /// The section codes flip with the archive's magic, so a big-endian file
    /// spells them backwards too.
    func testSectionMagicsFlipWithTheArchive() throws {
        let engine = try engine()
        let big = try NARCArchive(byteOrder: .big, entries: namelessEntries()).data(engine: engine)
        let little = try NARCArchive(byteOrder: .little, entries: namelessEntries()).data(engine: engine)
        let bigText = String(decoding: big.rawBytes, as: UTF8.self)
        let littleText = String(decoding: little.rawBytes, as: UTF8.self)
        for spelled in ["FATB", "FNTB", "FIMG"] {
            XCTAssertTrue(bigText.contains(spelled), "big-endian archive is missing \(spelled)")
        }
        for spelled in ["BTAF", "BTNF", "GMIF"] {
            XCTAssertTrue(littleText.contains(spelled), "little-endian archive is missing \(spelled)")
        }
    }

    func testHeaderDeclaresTheRealTotalSize() throws {
        let engine = try engine()
        let packed = try NARCArchive(byteOrder: .big, entries: namelessEntries()).data(engine: engine)
        let reader = ArchiveReader(bytes: packed.rawBytes, byteOrder: .big, format: "NARC")
        XCTAssertEqual(Int(try reader.u32(8)), packed.length)
        XCTAssertEqual(Int(try reader.u16(0x0C)), 0x10)
        XCTAssertEqual(Int(try reader.u16(0x0E)), 3)
    }

    /// A nameless name table read off a real file is replayed verbatim: the
    /// two 16-bit fields sit in the opposite order on the two platforms and
    /// replaying sidesteps having to pick a side.
    func testRawNameTableIsReplayedVerbatim() throws {
        let engine = try engine()
        let odd: [UInt8] = [0x00, 0x00, 0x00, 0x04, 0xAB, 0xCD, 0xEF, 0x01]
        let archive = NARCArchive(byteOrder: .big, entries: namelessEntries(), rawNameTable: odd)
        let packed = try archive.data(engine: engine)
        let reparsed = try NARCArchive(data: packed, engine: engine)
        XCTAssertEqual(reparsed.rawNameTable, odd)
        XCTAssertEqual(try reparsed.data(engine: engine).rawBytes, packed.rawBytes)
    }

    func testHasNames() {
        XCTAssertFalse(NARCArchive(byteOrder: .big, entries: namelessEntries()).hasNames)
        XCTAssertTrue(NARCArchive(byteOrder: .big, entries: namedEntries()).hasNames)
    }

    // MARK: - Errors

    func testParsingRejectsAForeignMagic() throws {
        let engine = try engine()
        let bytes = GoDData(byteStream: [0x55, 0xAA, 0x38, 0x2D] + [UInt8](repeating: 0, count: 32), byteOrder: .big)
        XCTAssertThrowsError(try NARCArchive(data: bytes, engine: engine)) { error in
            guard case let NintendoArchiveError.wrongFormat(expected, found) = error else {
                return XCTFail("expected wrongFormat, got \(error)")
            }
            XCTAssertEqual(expected, .narc)
            XCTAssertEqual(found, .u8)
        }
    }

    func testParsingRejectsATruncatedFile() throws {
        let engine = try engine()
        let bytes = GoDData(byteStream: Array("CRAN".utf8) + [0xFF, 0xFE], byteOrder: .big)
        XCTAssertThrowsError(try NARCArchive(data: bytes, engine: engine)) { error in
            guard case NintendoArchiveError.truncated = error else {
                return XCTFail("expected truncated, got \(error)")
            }
        }
    }

    func testSerializingRejectsAnOverlongName() throws {
        let engine = try engine()
        let archive = NARCArchive(
            byteOrder: .big,
            entries: [.init(name: String(repeating: "n", count: 200), data: payload("x"))]
        )
        XCTAssertThrowsError(try archive.data(engine: engine)) { error in
            guard case NintendoArchiveError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }
}
