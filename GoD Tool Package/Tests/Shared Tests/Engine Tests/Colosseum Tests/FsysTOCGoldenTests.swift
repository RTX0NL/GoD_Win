import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import FixtureCatalog
import TestSupport

/// Encode/decode tests for `FsysTOC` (the GSfsys table of contents mapping
/// filenames to fsys group IDs) against checked-in golden fixtures
/// (defined by `FsysTOCFixtures` in `FixtureCatalog`).
///
/// Two goldens cover both on-disc entry layouts: Colosseum uses the small
/// 8-byte TOC entry (and `unknown` 0x104), XD the full 16-byte entry (and
/// 0x201) — both driven by the in-memory `defaultEngine(for:)`.
///
/// Regenerate: `swift run FixtureGen`
final class FsysTOCGoldenTests: XCTestCase {

    // MARK: - Spec anchors

    func testTOC_goldenBinaries_matchSpecLayout() throws {
        let colo = try Fixtures.data("gsfsys_colo.toc").rawBytes
        let xd = try Fixtures.data("gsfsys_xd.toc").rawBytes

        func u32(_ bytes: [UInt8], _ o: Int) -> Int {
            Int(bytes[o]) << 24 | Int(bytes[o + 1]) << 16 | Int(bytes[o + 2]) << 8 | Int(bytes[o + 3])
        }
        for (bytes, unknown, label) in [(colo, 0x104, "colo"), (xd, 0x201, "xd")] {
            XCTAssertEqual(Array(bytes[0..<4]), Array("GLLA".utf8), "\(label): magic")
            XCTAssertEqual(u32(bytes, 0x04), unknown, "\(label): per-game unknown at 0x04")
            XCTAssertEqual(u32(bytes, 0x08), 3, "\(label): entry_count at 0x08")
        }
        // XD's full entries carry 8 extra padding bytes each — its TOC must
        // be strictly larger than Colo's for the same map.
        XCTAssertGreaterThan(xd.count, colo.count)
    }

    // MARK: - Decode

    func testTOC_decode_recoversLookupsBothWays() throws {
        for (fixture, game) in [("gsfsys_colo.toc", GSGame.colosseum),
                                ("gsfsys_xd.toc", GSGame.galeOfDarkness)] {
            let engine = GeniusSonorityEngine.defaultEngine(for: game)
            let toc = try FsysTOC(tocData: Fixtures.data(fixture), engine: engine)

            XCTAssertEqual(toc.unknown, engine.data.toc.unknown, "\(fixture): unknown")
            for (filename, id) in FsysTOCFixtures.idsByFilename {
                XCTAssertEqual(toc.fsysID(for: filename), id, "\(fixture): id for \(filename)")
                XCTAssertEqual(toc.filename(for: id), filename, "\(fixture): filename for \(id)")
            }
            XCTAssertNil(toc.fsysID(for: "nonexistent.fsys"), "\(fixture): unknown filename")
        }
    }

    // MARK: - Encode

    func testTOC_encode_producesGoldenBinaries() throws {
        for (fixture, game) in [("gsfsys_colo.toc", GSGame.colosseum),
                                ("gsfsys_xd.toc", GSGame.galeOfDarkness)] {
            let engine = GeniusSonorityEngine.defaultEngine(for: game)
            let expected = try Fixtures.data(fixture)
            let blob = try FsysTOCFixtures.model(engine: engine).tocData(with: engine)
            assertBytesEqual(blob, expected, fixture)
        }
    }
}
