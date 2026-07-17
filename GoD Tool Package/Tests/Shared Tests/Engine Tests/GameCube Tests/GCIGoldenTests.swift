import XCTest
import Foundation
import GoDFoundation
import GameCube
import TestSupport

/// Encode/decode tests for `GCIFile` (GameCube memory-card save) against a
/// checked-in golden fixture (defined by `GCIFixtures` in `FixtureCatalog`).
/// GCI is byte-identical on both halves, so both directions assert `.exact`.
///
/// Regenerate: `swift run FixtureGen`
final class GCIGoldenTests: XCTestCase {

    private static let fixtureName = "gci_sample"

    /// DECODE: golden `.gci` → golden JSON manifest + `.gci.body.bin` sidecar.
    func testGCI_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).gci")
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).gci.json",
            "\(Self.fixtureName).gci.body.bin",
        ])
        try assertDecodes(GCIFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: golden JSON + body sidecar → golden `.gci`, byte-for-byte.
    func testGCI_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts([
            "\(Self.fixtureName).gci.json",
            "\(Self.fixtureName).gci.body.bin",
        ])
        let expected = try Fixtures.fileData("\(Self.fixtureName).gci")
        try assertEncodes(GCIFile.self, from: artifacts, producesBinary: expected)
    }
}
