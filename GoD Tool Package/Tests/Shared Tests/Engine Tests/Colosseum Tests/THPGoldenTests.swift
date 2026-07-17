import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import TestSupport

/// Encode/decode tests for `THPFile` (paired `.thh` + `.thd` video) against
/// checked-in golden fixtures (defined by `THPFixtures` in
/// `FixtureCatalog`). THP round-trips bit-identically (the pointer fixup is
/// invertible), so both directions assert `.exact`.
///
/// This is the paired-format proof: `binaries` is two files (`.thh`, `.thd`)
/// and `outputs` is a single self-describing `.thp` with no JSON sidecar.
///
/// Regenerate: `swift run FixtureGen`
final class THPGoldenTests: XCTestCase {

    private static let fixtureName = "thp_sample"

    /// DECODE: golden `.thh` + `.thd` → golden combined `.thp`.
    func testTHP_decode_producesGoldenArtifacts() throws {
        let binaries = try Fixtures.artifacts([
            "\(Self.fixtureName).thh",
            "\(Self.fixtureName).thd",
        ])
        let expected = try Fixtures.artifacts(["\(Self.fixtureName).thp"])
        try assertDecodes(THPFile.self, from: binaries, producesArtifacts: expected)
    }

    /// ENCODE: golden `.thp` → golden `.thh` + `.thd`, byte-for-byte.
    func testTHP_encode_producesGoldenBinaries() throws {
        let artifacts = try Fixtures.artifacts(["\(Self.fixtureName).thp"])
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).thh",
            "\(Self.fixtureName).thd",
        ])
        try assertEncodes(THPFile.self, from: artifacts, producesBinaries: expected)
    }
}
