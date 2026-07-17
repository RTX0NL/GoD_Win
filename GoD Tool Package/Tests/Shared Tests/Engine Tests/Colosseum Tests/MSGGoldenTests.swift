import XCTest
import GoDFoundation
import GeniusSonority
import TestSupport

/// Encode/decode tests for `MSGFile` driven by the shared `TestSupport`
/// harness against checked-in golden fixtures (`Fixtures/msg_minimal.*`).
///
/// Unlike the real-ROM samples in `FileFormatProtocolTests`, these always
/// run — the fixture and its expected decoded form are both committed, so
/// each direction is checked against independent ground truth rather than
/// the tool's own output.
final class MSGGoldenTests: XCTestCase {

    /// DECODE: the golden `.msg` binary must decode to the golden JSON.
    func testMSG_decode_producesGoldenArtifacts() throws {
        let binary = try Fixtures.fileData("msg_minimal.msg")
        let expected = try Fixtures.artifacts(["msg_minimal.msg.json"])
        try assertDecodes(MSGFile.self, from: binary, producesArtifacts: expected)
    }

    /// ENCODE: the golden JSON must encode back to the golden `.msg` binary,
    /// byte-for-byte (MSG is a byte-faithful format).
    func testMSG_encode_producesGoldenBinary() throws {
        let artifacts = try Fixtures.artifacts(["msg_minimal.msg.json"])
        let expectedBinary = try Fixtures.fileData("msg_minimal.msg")
        try assertEncodes(MSGFile.self, from: artifacts, producesBinary: expectedBinary)
    }
}
