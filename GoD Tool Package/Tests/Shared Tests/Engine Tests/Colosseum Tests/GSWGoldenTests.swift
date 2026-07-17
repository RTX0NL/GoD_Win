import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import TestSupport

/// Encode/decode tests for `GSWFile` (flash menu) against a checked-in
/// golden fixture (defined by `GSWFixtures` in `FixtureCatalog`: a
/// texture-free GSW, whose header + opaque tag stream round-trip
/// byte-identically). Embedded textures re-encode through the lossy GTX
/// path and are covered separately.
///
/// Regenerate: `swift run FixtureGen`
final class GSWGoldenTests: XCTestCase {

    private static let fixtureName = "gsw_sample"

    /// DECODE: golden `.gsw` → golden JSON (no texture PNGs).
    func testGSW_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).gsw")
        let expected = try Fixtures.artifacts(["\(Self.fixtureName).gsw.json"])
        try assertDecodes(GSWFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: golden JSON → golden `.gsw`, byte-for-byte.
    func testGSW_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts(["\(Self.fixtureName).gsw.json"])
        let expected = try Fixtures.fileData("\(Self.fixtureName).gsw")
        try assertEncodes(GSWFile.self, from: artifacts, producesBinary: expected)
    }
}
