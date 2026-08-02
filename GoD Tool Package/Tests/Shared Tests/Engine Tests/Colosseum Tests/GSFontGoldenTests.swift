import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import TestSupport

/// Encode/decode tests for `GSFont` against a checked-in golden fixture
/// (defined by `GSFontFixtures` in `FixtureCatalog`: a primary block
/// chained to a smaller secondary block). The raw `.fnt` binary round-trips
/// byte-identically; the PGM atlas is a normalized re-render, but the
/// ×17/÷17 nibble mapping is exactly invertible, so the reader-canonical
/// golden keeps both directions `.exact`.
///
/// Regenerate: `swift run FixtureGen`
final class GSFontGoldenTests: XCTestCase {

    private static let fixtureName = "fnt_sample"

    /// DECODE: golden `.fnt` → golden JSON metadata + PGM atlas.
    func testGSFont_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).fnt")
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).fnt.json",
            "\(Self.fixtureName).fnt.pgm",
        ])
        try assertDecodes(GSFont.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: golden JSON + PGM → golden `.fnt`, byte-for-byte.
    func testGSFont_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts([
            "\(Self.fixtureName).fnt.json",
            "\(Self.fixtureName).fnt.pgm",
        ])
        let expected = try Fixtures.fileData("\(Self.fixtureName).fnt")
        try assertEncodes(GSFont.self, from: artifacts, producesBinary: expected)
    }
}
