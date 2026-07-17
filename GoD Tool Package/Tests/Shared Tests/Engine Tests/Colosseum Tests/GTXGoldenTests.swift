import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX
import TestSupport

/// Encode/decode tests for `GTXFile` against a checked-in golden fixture
/// (defined by `GTXFixtures` in `FixtureCatalog`: a 4×4 RGBA32 gradient —
/// lossless format → byte-faithful encode). Also the canary for the
/// image-companion path: `outputs` emits a `.png` sidecar alongside the
/// JSON, compared byte-for-byte (swift-png at compression level 0 is
/// deterministic).
///
/// Regenerate: `swift run FixtureGen`
final class GTXGoldenTests: XCTestCase {

    private static let fixtureName = "gtx_rgba32"

    /// DECODE: golden `.gtx` → golden JSON + PNG sidecar.
    func testGTX_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).gtx")
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).gtx.json",
            "\(Self.fixtureName).gtx.png",
        ])
        try assertDecodes(GTXFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: golden JSON + PNG → golden `.gtx`, byte-for-byte (RGBA32 is
    /// lossless).
    func testGTX_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts([
            "\(Self.fixtureName).gtx.json",
            "\(Self.fixtureName).gtx.png",
        ])
        let expected = try Fixtures.fileData("\(Self.fixtureName).gtx")
        try assertEncodes(GTXFile.self, from: artifacts, producesBinary: expected)
    }
}
