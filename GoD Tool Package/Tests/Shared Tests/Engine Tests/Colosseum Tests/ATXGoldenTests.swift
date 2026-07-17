import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX
import TestSupport

/// Encode/decode tests for `ATXFile` (animated texture) against a
/// checked-in golden fixture (defined by `ATXFixtures` in `FixtureCatalog`:
/// two RGBA32 frames + a two-step animation). RGBA32 is lossless so the
/// repacked sheet is deterministic and both directions are byte-exact.
/// (CMPR frames are lossy and would use a pixel tolerance.)
///
/// `outputs` fans out to a JSON manifest plus one PNG per frame, exercising
/// the multi-companion artifact path.
///
/// Regenerate: `swift run FixtureGen`
final class ATXGoldenTests: XCTestCase {

    private static let fixtureName = "atx_sample"

    /// DECODE: golden `.atx` → golden JSON + per-frame PNGs.
    func testATX_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).atx")
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).atx.json",
            "\(Self.fixtureName)_frame_000.png",
            "\(Self.fixtureName)_frame_001.png",
        ])
        try assertDecodes(ATXFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: golden JSON + frame PNGs → golden `.atx`, byte-for-byte.
    func testATX_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts([
            "\(Self.fixtureName).atx.json",
            "\(Self.fixtureName)_frame_000.png",
            "\(Self.fixtureName)_frame_001.png",
        ])
        let expected = try Fixtures.fileData("\(Self.fixtureName).atx")
        try assertEncodes(ATXFile.self, from: artifacts, producesBinary: expected)
    }
}
