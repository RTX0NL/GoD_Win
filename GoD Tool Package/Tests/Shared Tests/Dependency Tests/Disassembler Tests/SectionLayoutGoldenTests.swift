import XCTest
import Foundation
import GoDFoundation
import Disassembler
import FixtureCatalog
import TestSupport

/// Encode/decode tests for the `sections.txt` layout format
/// (`SectionLayoutWriter` ↔ `SectionLayoutParser`) against a checked-in
/// golden (defined by `SectionLayoutFixtures` in `FixtureCatalog`). This is
/// the text file the DOL disassembly op emits and the assembly op parses
/// back, so its format must stay stable.
///
/// Regenerate: `swift run FixtureGen`
final class SectionLayoutGoldenTests: XCTestCase {

    private func goldenText() throws -> String {
        let bytes = try Fixtures.data("sections_sample.txt").rawBytes
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Spec anchors: the frozen text uses the documented line shapes.
    func testLayout_goldenText_matchesSpecShapes() throws {
        let text = try goldenText()
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, "# DOL Section Layout")
        XCTAssertTrue(text.contains("# Entry point: 0x80003154"))
        XCTAssertTrue(text.contains("# BSS: 0x804205C0 (849860 bytes)"))
        XCTAssertTrue(text.contains("# Symbols: 42"))
        XCTAssertTrue(text.contains("text0: 0x80003100 (9472 bytes)"))
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("data5: 0x80457200") }),
                      "size-less section line present")
    }

    /// DECODE: parsing the golden text recovers the catalog model exactly.
    func testLayout_parse_recoversModel() throws {
        let parsed = SectionLayoutParser().parse(try goldenText())
        XCTAssertEqual(parsed, SectionLayoutFixtures.model())
    }

    /// ENCODE: writing the catalog model reproduces the golden text
    /// character-for-character.
    func testLayout_write_producesGoldenText() throws {
        let written = SectionLayoutWriter().write(
            SectionLayoutFixtures.model(),
            symbolCount: SectionLayoutFixtures.symbolCount
        )
        XCTAssertEqual(written, try goldenText())
    }

    /// `allSectionRanges` folds text + data + BSS into scan ranges,
    /// skipping size-less sections.
    func testLayout_allSectionRanges_includesSizedSectionsAndBSS() {
        let ranges = SectionLayoutFixtures.model().allSectionRanges
        // text0, text1, data0 (sized) + BSS; data5 has no size.
        XCTAssertEqual(ranges.count, 4)
        XCTAssertTrue(ranges.contains(where: { $0.start == 0x8000_3100 && $0.end == 0x8000_3100 + 9_472 }))
        XCTAssertTrue(ranges.contains(where: { $0.start == 0x8042_05C0 && $0.end == 0x8042_05C0 + 849_860 }))
    }
}
