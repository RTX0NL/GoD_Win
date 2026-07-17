import XCTest
import Foundation
import GoDFoundation
import Dolphin
import TestSupport

/// Encode/decode tests for `RELFile` against a checked-in golden fixture.
///
/// The fixture is defined by `RELFixtures` in the `FixtureCatalog` library:
/// a programmatic REL exercising every body kind, fixup kind and chunk kind
/// (empty / text / data / bss sections; plain, @ha, @lo and ADDR32
/// relocations against both DOL and self; binary and pointer data chunks;
/// multiple imported modules), serialised with the current writer and
/// frozen in its reader-canonical form.
///
/// Regenerate: `swift run FixtureGen`
final class RELGoldenTests: XCTestCase {

    private static let fixtureName = "rel_sample"

    /// DECODE: the golden `.rel` binary decodes to the golden JSON.
    func testREL_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("\(Self.fixtureName).rel")
        let expected = try Fixtures.artifacts(["\(Self.fixtureName).rel.json"])
        try assertDecodes(RELFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: the golden JSON encodes back to the golden `.rel` binary,
    /// byte-for-byte (REL rebuild is a hard byte-identical requirement).
    func testREL_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts(["\(Self.fixtureName).rel.json"])
        let expected = try Fixtures.fileData("\(Self.fixtureName).rel")
        try assertEncodes(RELFile.self, from: artifacts, producesBinary: expected)
    }
}
