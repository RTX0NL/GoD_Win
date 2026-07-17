import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import FixtureCatalog
import TestSupport

/// Encode/decode tests for `FSYSArchive` against a checked-in golden
/// fixture. FSYS is engine-bound (struct layouts + enums come from
/// `GeniusSonorityEngine`), so these use the in-memory
/// `defaultEngine(for: .colosseum)` — no project folder needed.
///
/// The sample (defined by `FSYSFixtures` in `FixtureCatalog`) has multiple
/// entries with multiple file types and generic names, each with
/// deterministic pseudo-random data, some LZSS-compressed and some not.
/// The catalog model is the decoded ground truth; the frozen blob is
/// additionally anchored to the FSYS spec by explicit offset assertions
/// (magic, counts, footer, LZSS headers) so the golden isn't purely
/// self-referential.
///
/// Regenerate: `swift run FixtureGen`
final class FSYSGoldenTests: XCTestCase {

    private let engine = FSYSFixtures.engine()

    // MARK: - Spec anchors (independent of reader AND writer)

    /// Pins the frozen blob to the documented FSYS layout so the golden
    /// isn't circular: header magic/groupID/count/file_size at their spec
    /// offsets, footer magic in the last 4 bytes, and exactly one LZSS
    /// header per compressed entry.
    func testFSYS_goldenBinary_matchesSpecLayout() throws {
        let bytes = try Fixtures.data("\(FSYSFixtures.name).fsys").rawBytes

        func u32(_ o: Int) -> Int {
            Int(bytes[o]) << 24 | Int(bytes[o + 1]) << 16 | Int(bytes[o + 2]) << 8 | Int(bytes[o + 3])
        }
        XCTAssertEqual(Array(bytes[0..<4]), Array("FSYS".utf8), "header magic")
        XCTAssertEqual(u32(0x08), FSYSFixtures.groupID, "group_id at 0x08")
        XCTAssertEqual(u32(0x0C), 4, "entry_count at 0x0C")
        XCTAssertEqual(u32(0x20), bytes.count, "file_size at 0x20 spans the whole blob")
        XCTAssertEqual(Array(bytes.suffix(4)), Array("FSYS".utf8), "footer magic")

        // Exactly two LZSS headers — entries B and C are compressed.
        let lzss = Array("LZSS".utf8)
        var lzssCount = 0
        for i in 0...(bytes.count - 4) where Array(bytes[i..<(i + 4)]) == lzss {
            lzssCount += 1
        }
        XCTAssertEqual(lzssCount, 2, "one LZSS header per compressed entry")
    }

    // MARK: - Decode

    /// DECODE: parsing the golden blob recovers the catalog model — names,
    /// types, identifiers, compression flags, and (decompressed) payloads.
    func testFSYS_decode_recoversModel() throws {
        let blob = try Fixtures.data("\(FSYSFixtures.name).fsys")
        let parsed = try FSYSArchive(data: blob, engine: engine)
        let expected = FSYSFixtures.entries()

        XCTAssertEqual(parsed.groupID, FSYSFixtures.groupID)
        XCTAssertEqual(parsed.entries.count, expected.count)
        for (p, e) in zip(parsed.entries, expected) {
            XCTAssertEqual(p.metadata.name, e.metadata.name)
            XCTAssertEqual(p.metadata.fileType, e.metadata.fileType)
            XCTAssertEqual(p.metadata.identifier, e.metadata.identifier)
            XCTAssertEqual(p.metadata.compress, e.metadata.compress,
                           "\(e.metadata.name): compression flag")
            assertBytesEqual(p.data.rawBytes, e.data.rawBytes,
                             "\(e.metadata.name): payload (decompressed)")
        }
    }

    // MARK: - Encode

    /// ENCODE: serializing the catalog model reproduces the golden blob
    /// byte-for-byte.
    func testFSYS_encode_producesGoldenBinary() throws {
        let expected = try Fixtures.data("\(FSYSFixtures.name).fsys")
        let blob = try FSYSFixtures.model().data(groupID: FSYSFixtures.groupID, engine: engine)
        assertBytesEqual(blob, expected)
    }
}
