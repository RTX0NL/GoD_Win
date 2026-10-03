//
//  ZstdPredefinedTableTests.swift
//
//  Pins the three predefined FSE tables against the ones the reference
//  implementation ships precomputed (`LL_defaultDTable`, `OF_defaultDTable`,
//  `ML_defaultDTable` in facebook/zstd `lib/decompress/zstd_decompress_block.c`),
//  transcribed here as (symbol, nbBits, newState) per state.
//
//  This is the highest-value test in the decoder, because a wrong
//  distribution is invisible in isolation. Getting the match-length
//  distribution's low-probability run wrong — five `-1`s where the format
//  has seven — still builds a table that fills its 64 states, still decodes
//  most streams, and only shows up as a short match where a long one
//  belonged. Comparing state by state against the reference is what turns
//  that into a named failure.
//

import XCTest
@testable import GoDFoundation

final class ZstdPredefinedTableTests: XCTestCase {

    /// (symbol, nbBits, newState) per state, from zstd's precomputed literalLength table.
    static let reference_literalLength: [(UInt8, UInt8, UInt16)] = [
        (0, 4, 0), (0, 4, 16), (1, 5, 32), (3, 5, 0),
        (4, 5, 0), (6, 5, 0), (7, 5, 0), (9, 5, 0),
        (10, 5, 0), (12, 5, 0), (14, 6, 0), (16, 5, 0),
        (18, 5, 0), (19, 5, 0), (21, 5, 0), (22, 5, 0),
        (24, 5, 0), (25, 5, 32), (26, 5, 0), (27, 6, 0),
        (29, 6, 0), (31, 6, 0), (0, 4, 32), (1, 4, 0),
        (2, 5, 0), (4, 5, 32), (5, 5, 0), (7, 5, 32),
        (8, 5, 0), (10, 5, 32), (11, 5, 0), (13, 6, 0),
        (16, 5, 32), (17, 5, 0), (19, 5, 32), (20, 5, 0),
        (22, 5, 32), (23, 5, 0), (25, 4, 0), (25, 4, 16),
        (26, 5, 32), (28, 6, 0), (30, 6, 0), (0, 4, 48),
        (1, 4, 16), (2, 5, 32), (3, 5, 32), (5, 5, 32),
        (6, 5, 32), (8, 5, 32), (9, 5, 32), (11, 5, 32),
        (12, 5, 32), (15, 6, 0), (17, 5, 32), (18, 5, 32),
        (20, 5, 32), (21, 5, 32), (23, 5, 32), (24, 5, 32),
        (35, 6, 0), (34, 6, 0), (33, 6, 0), (32, 6, 0),
    ]

    /// (symbol, nbBits, newState) per state, from zstd's precomputed offset table.
    static let reference_offset: [(UInt8, UInt8, UInt16)] = [
        (0, 5, 0), (6, 4, 0), (9, 5, 0), (15, 5, 0),
        (21, 5, 0), (3, 5, 0), (7, 4, 0), (12, 5, 0),
        (18, 5, 0), (23, 5, 0), (5, 5, 0), (8, 4, 0),
        (14, 5, 0), (20, 5, 0), (2, 5, 0), (7, 4, 16),
        (11, 5, 0), (17, 5, 0), (22, 5, 0), (4, 5, 0),
        (8, 4, 16), (13, 5, 0), (19, 5, 0), (1, 5, 0),
        (6, 4, 16), (10, 5, 0), (16, 5, 0), (28, 5, 0),
        (27, 5, 0), (26, 5, 0), (25, 5, 0), (24, 5, 0),
    ]

    /// (symbol, nbBits, newState) per state, from zstd's precomputed matchLength table.
    static let reference_matchLength: [(UInt8, UInt8, UInt16)] = [
        (0, 6, 0), (1, 4, 0), (2, 5, 32), (3, 5, 0),
        (5, 5, 0), (6, 5, 0), (8, 5, 0), (10, 6, 0),
        (13, 6, 0), (16, 6, 0), (19, 6, 0), (22, 6, 0),
        (25, 6, 0), (28, 6, 0), (31, 6, 0), (33, 6, 0),
        (35, 6, 0), (37, 6, 0), (39, 6, 0), (41, 6, 0),
        (43, 6, 0), (45, 6, 0), (1, 4, 16), (2, 4, 0),
        (3, 5, 32), (4, 5, 0), (6, 5, 32), (7, 5, 0),
        (9, 6, 0), (12, 6, 0), (15, 6, 0), (18, 6, 0),
        (21, 6, 0), (24, 6, 0), (27, 6, 0), (30, 6, 0),
        (32, 6, 0), (34, 6, 0), (36, 6, 0), (38, 6, 0),
        (40, 6, 0), (42, 6, 0), (44, 6, 0), (1, 4, 32),
        (1, 4, 48), (2, 4, 16), (4, 5, 32), (5, 5, 32),
        (7, 5, 32), (8, 5, 32), (11, 6, 0), (14, 6, 0),
        (17, 6, 0), (20, 6, 0), (23, 6, 0), (26, 6, 0),
        (29, 6, 0), (52, 6, 0), (51, 6, 0), (50, 6, 0),
        (49, 6, 0), (48, 6, 0), (47, 6, 0), (46, 6, 0),
    ]


    private func assertMatches(
        _ table: ZstdFSETable,
        _ reference: [(UInt8, UInt8, UInt16)],
        _ name: String,
        expectedLog: Int
    ) {
        XCTAssertEqual(table.tableLog, expectedLog, "\(name) accuracy log")
        XCTAssertEqual(table.entries.count, reference.count, "\(name) state count")
        guard table.entries.count == reference.count else { return }
        for state in 0..<reference.count {
            let built = table.entries[state]
            let (symbol, nbBits, newState) = reference[state]
            XCTAssertEqual(built.symbol, symbol, "\(name) state \(state) symbol")
            XCTAssertEqual(built.nbBits, nbBits, "\(name) state \(state) nbBits")
            XCTAssertEqual(built.newState, newState, "\(name) state \(state) newState")
        }
    }

    func testLiteralLengthTableMatchesTheReference() {
        assertMatches(ZstdSequenceTables.literalLength, Self.reference_literalLength, "literal length", expectedLog: 6)
    }

    func testOffsetTableMatchesTheReference() {
        assertMatches(ZstdSequenceTables.offset, Self.reference_offset, "offset", expectedLog: 5)
    }

    func testMatchLengthTableMatchesTheReference() {
        assertMatches(ZstdSequenceTables.matchLength, Self.reference_matchLength, "match length", expectedLog: 6)
    }

    /// Each distribution's counts must fill its table exactly; that is the
    /// invariant `ZstdFSETable` enforces, and the one a miscount breaks.
    func testDistributionsFillTheirTables() {
        let cases: [(String, [Int16], Int)] = [
            ("literal length", ZstdSequenceTables.literalLengthCounts, 6),
            ("match length", ZstdSequenceTables.matchLengthCounts, 6),
            ("offset", ZstdSequenceTables.offsetCounts, 5),
        ]
        for (name, counts, log) in cases {
            let total = counts.reduce(0) { $0 + Int($1.magnitude) }
            XCTAssertEqual(total, 1 << log, "\(name) distribution covers \(total) of \(1 << log) states")
        }
        XCTAssertEqual(ZstdSequenceTables.literalLengthCounts.count, 36)
        XCTAssertEqual(ZstdSequenceTables.matchLengthCounts.count, 53)
        XCTAssertEqual(ZstdSequenceTables.offsetCounts.count, 29)
    }

    /// Baseline and extra-bit tables are indexed by symbol, so a missing
    /// entry is an out-of-bounds read on a valid stream rather than a wrong
    /// answer.
    func testCodeTablesCoverEverySymbol() {
        XCTAssertEqual(ZstdSequenceTables.literalLengthBaseline.count, 36)
        XCTAssertEqual(ZstdSequenceTables.literalLengthExtraBits.count, 36)
        XCTAssertEqual(ZstdSequenceTables.matchLengthBaseline.count, 53)
        XCTAssertEqual(ZstdSequenceTables.matchLengthExtraBits.count, 53)
    }
}
