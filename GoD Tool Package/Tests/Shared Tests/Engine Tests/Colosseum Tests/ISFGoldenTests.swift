import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import TestSupport

/// Encode/decode tests for `ISFFile` (paired `.ish` + `.isd` DSP-ADPCM
/// audio) against checked-in golden fixtures (defined by `ISFFixtures` in
/// `FixtureCatalog`: a short stereo tone).
///
/// DSP-ADPCM is lossy: the WAV in `outputs` carries the decoded PCM
/// losslessly and the ADPCM encoder is deterministic, so `outputs →
/// binaries` reproduces the frozen `.ish`/`.isd` byte-for-byte — but the
/// decoded PCM drifts slightly each requant cycle and never reaches a
/// byte-stable fixed point, so the decode side compares the WAV within a
/// small RMS error (measured ≈112 for this fixture; bound 200). These
/// guard reader/writer *consistency*; absolute audio fidelity is covered
/// by the RMS/correlation checks in ISFFileTests.
///
/// Regenerate: `swift run FixtureGen`
final class ISFGoldenTests: XCTestCase {

    private static let fixtureName = "isf_sample"

    /// DECODE: golden `.ish` + `.isd` → golden JSON + WAV (RMS-tolerant).
    func testISF_decode_producesGoldenArtifacts() throws {
        let binaries = try Fixtures.artifacts([
            "\(Self.fixtureName).ish",
            "\(Self.fixtureName).isd",
        ])
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).isf.json",
            "\(Self.fixtureName).wav",
        ])
        try assertDecodes(
            ISFFile.self, from: binaries, producesArtifacts: expected,
            tolerances: ["wav": wavPCMTolerance(maxRMS: 200)]
        )
    }

    /// ENCODE: golden JSON + WAV → golden `.ish` + `.isd`, byte-for-byte.
    func testISF_encode_producesGoldenBinaries() throws {
        let artifacts = try Fixtures.artifacts([
            "\(Self.fixtureName).isf.json",
            "\(Self.fixtureName).wav",
        ])
        let expected = try Fixtures.artifacts([
            "\(Self.fixtureName).ish",
            "\(Self.fixtureName).isd",
        ])
        try assertEncodes(ISFFile.self, from: artifacts, producesBinaries: expected)
    }
}
