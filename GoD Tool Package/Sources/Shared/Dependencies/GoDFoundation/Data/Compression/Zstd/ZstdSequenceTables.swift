//
//  ZstdSequenceTables.swift
//
//  The fixed tables a Zstandard sequences section leans on: the three
//  predefined FSE distributions a block may use instead of sending its own,
//  and the baseline/extra-bit pairs that turn a decoded symbol back into a
//  length or an offset.
//
//  All of it is transcribed from the format specification. A distribution's
//  counts must add up to its table size (64, 64 and 32 here), which is the
//  check that a transcription is faithful — `ZstdFSETable` rejects one that
//  doesn't.
//
//  Reference: RFC 8878 §3.1.1.3.2
//

import Foundation

enum ZstdSequenceTables {

    // MARK: - Predefined distributions

    static let literalLengthCounts: [Int16] = [
         4,  3,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  1,  1,  1,
         2,  2,  2,  2,  2,  2,  2,  2,  2,  3,  2,  1,  1,  1,  1,  1,
        -1, -1, -1, -1,
    ]

    // Seven low-probability slots, at codes 46-52 — the long-match codes.
    // A low-probability symbol takes a state at the top of the table
    // instead of one from the spread, so miscounting them shifts every
    // symbol above code 32 and decodes long matches as short ones.
    static let matchLengthCounts: [Int16] = [
         1,  4,  3,  2,  2,  2,  2,  2,  2,  1,  1,  1,  1,  1,  1,  1,
         1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
         1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1, -1, -1,
        -1, -1, -1, -1, -1,
    ]

    static let offsetCounts: [Int16] = [
         1,  1,  1,  1,  1,  1,  2,  2,  2,  1,  1,  1,  1,  1,  1,  1,
         1,  1,  1,  1,  1,  1,  1,  1, -1, -1, -1, -1, -1,
    ]

    // Built once. The counts are constants that satisfy the builder's own
    // invariants, so a failure here would be a transcription error rather
    // than anything a stream could cause — hence the force-unwrap via a
    // fatalError-on-throw wrapper rather than an optional every caller
    // would have to unwrap.
    static let literalLength: ZstdFSETable = build(literalLengthCounts, tableLog: 6, name: "literal length")
    static let matchLength: ZstdFSETable = build(matchLengthCounts, tableLog: 6, name: "match length")
    static let offset: ZstdFSETable = build(offsetCounts, tableLog: 5, name: "offset")

    private static func build(_ counts: [Int16], tableLog: Int, name: String) -> ZstdFSETable {
        do {
            return try ZstdFSETable(predefinedCounts: counts, tableLog: tableLog)
        } catch {
            fatalError("Zstandard's predefined \(name) distribution does not fill its table: \(error)")
        }
    }

    // MARK: - Literal length codes

    static let literalLengthBaseline: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096,
        8192, 16384, 32768, 65536,
    ]

    static let literalLengthExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16,
    ]

    // MARK: - Match length codes

    static let matchLengthBaseline: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
        19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
        35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051,
        4099, 8195, 16387, 32771, 65539,
    ]

    static let matchLengthExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11,
        12, 13, 14, 15, 16,
    ]
}
