//
//  FileFormatAssertions.swift
//
//  Encode/decode assertions for `FileFormat` conformers.
//
//  We deliberately do NOT test round-trips (binary → outputs → binary).
//  Not every format is round-trip faithful, and a round-trip can pass
//  while both reader and writer are wrong in compensating ways. Instead we
//  test each direction against independent, checked-in ground truth:
//
//    DECODE  — given the canonical binary, does the reader produce the
//              canonical artifacts?  (a failure blames the reader)
//    ENCODE  — given the canonical artifacts, does the writer produce the
//              canonical binary?     (a failure blames the writer)
//
//  A format that is not byte-faithful on encode (lossy texture/audio
//  codecs, Wii fakesigning) passes a `.custom` tolerance instead of
//  `.exact`, and simply never claims byte identity.
//

import XCTest
import GoDFoundation

// MARK: - Encode tolerance

/// How closely a re-encoded binary must match the golden binary.
public enum BinaryTolerance {
    /// Byte-for-byte identical (REL, THP, GCI, MSG, FSYS, DOL, …).
    case exact
    /// Named predicate for lossy encoders (pixel-stable re-decode, valid
    /// structure, size-only, …). The predicate receives (actual, expected).
    case custom(String, (_ actual: [UInt8], _ expected: [UInt8]) -> Bool)
}

/// Compares two artifact byte buffers under a tolerance. Returns true when
/// they match. Used for lossy decode companions (a DSP-ADPCM WAV, a CMPR
/// PNG) where byte-equality is the wrong bar.
public typealias ArtifactComparator = (_ actual: [UInt8], _ expected: [UInt8]) -> Bool

// MARK: - Artifact-set comparison

/// Compares two artifact bundles keyed by file. For each artifact: if its
/// extension has an entry in `tolerances`, that comparator decides; else
/// `.json` compares semantically (see `assertJSONEqual`) and everything else
/// compares byte-for-byte. Reports missing / unexpected keys first.
public func assertArtifactsEqual(
    _ actual: [FileData],
    _ expected: [FileData],
    tolerances: [String: ArtifactComparator] = [:],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualByFile = actual.byFile
    let expectedByFile = expected.byFile
    let actualKeys = Set(actualByFile.keys)
    let expectedKeys = Set(expectedByFile.keys)

    let missing = expectedKeys.subtracting(actualKeys).map(\.path).sorted()
    let unexpected = actualKeys.subtracting(expectedKeys).map(\.path).sorted()
    guard missing.isEmpty && unexpected.isEmpty else {
        XCTFail(
            "artifact set mismatch — missing: \(missing); unexpected: \(unexpected)",
            file: file, line: line
        )
        return
    }

    for key in expectedKeys.sorted() {
        let actualData = actualByFile[key]!
        let expectedData = expectedByFile[key]!
        let ext = (key.fileType ?? "").lowercased()
        if let comparator = tolerances[ext] {
            if !comparator(actualData.rawBytes, expectedData.rawBytes) {
                XCTFail(
                    "artifact \(key.path) failed '\(ext)' tolerance check "
                    + "(expected \(expectedData.rawBytes.count) bytes, got \(actualData.rawBytes.count))",
                    file: file, line: line
                )
            }
        } else if ext == "json" {
            assertJSONEqual(actualData.data, expectedData.data, "artifact \(key.path)", file: file, line: line)
        } else {
            assertBytesEqual(actualData.rawBytes, expectedData.rawBytes, "artifact \(key.path)", file: file, line: line)
        }
    }
}

// MARK: - Decode

/// DECODE: parse `binaries` as `F` and assert its artifacts equal `expected`.
/// `tolerances` (keyed by lowercased file extension) let lossy companions —
/// a DSP-ADPCM `wav`, a CMPR `png` — pass a semantic check instead of byte
/// equality; the JSON manifest still compares exactly.
public func assertDecodes<F: FileFormat>(
    _ type: F.Type,
    from binaries: [FileData],
    producesArtifacts expected: [FileData],
    tolerances: [String: ArtifactComparator] = [:],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let format = try F(binaries: binaries)
    let actual = try format.outputs
    assertArtifactsEqual(actual, expected, tolerances: tolerances, file: file, line: line)
}

/// Single-binary convenience.
public func assertDecodes<F: FileFormat>(
    _ type: F.Type,
    from binary: FileData,
    producesArtifacts expected: [FileData],
    tolerances: [String: ArtifactComparator] = [:],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try assertDecodes(type, from: [binary], producesArtifacts: expected, tolerances: tolerances, file: file, line: line)
}

// MARK: - Encode

/// ENCODE: build `F` from `artifacts` and assert its binaries equal
/// `expected` under `tolerance`.
public func assertEncodes<F: FileFormat>(
    _ type: F.Type,
    from artifacts: [FileData],
    producesBinaries expected: [FileData],
    tolerance: BinaryTolerance = .exact,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let format = try F(outputs: artifacts)
    let actual = try format.binaries

    guard actual.count == expected.count else {
        XCTFail(
            "binary piece count mismatch — expected \(expected.count), got \(actual.count)",
            file: file, line: line
        )
        return
    }

    for (actualPiece, expectedPiece) in zip(actual, expected) {
        let actualBytes = actualPiece.data.rawBytes
        let expectedBytes = expectedPiece.data.rawBytes
        switch tolerance {
        case .exact:
            assertBytesEqual(actualBytes, expectedBytes, "binary \(expectedPiece.file.path)", file: file, line: line)
        case let .custom(name, predicate):
            if !predicate(actualBytes, expectedBytes) {
                XCTFail(
                    "binary \(expectedPiece.file.path) failed '\(name)' tolerance "
                    + "(expected \(expectedBytes.count) bytes, got \(actualBytes.count))",
                    file: file, line: line
                )
            }
        }
    }
}

/// Single-binary convenience.
public func assertEncodes<F: FileFormat>(
    _ type: F.Type,
    from artifacts: [FileData],
    producesBinary expected: FileData,
    tolerance: BinaryTolerance = .exact,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try assertEncodes(type, from: artifacts, producesBinaries: [expected], tolerance: tolerance, file: file, line: line)
}
