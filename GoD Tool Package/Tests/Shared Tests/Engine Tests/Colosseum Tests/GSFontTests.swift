import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

/// GSFont-specific format behavior beyond the protocol members (which
/// FileFormatProtocolTests covers): nested block chain, glyph parsing,
/// edge cases. Each test asserts a single observable property of the
/// parsed struct — no roundtrips.
final class GSFontTests: XCTestCase {

    /// GODDESS_FONT_SAMPLES overrides the folder of sample fonts.
    private let samplesDir = ProcessInfo.processInfo.environment["GODDESS_FONT_SAMPLES"]
        ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Assets/Text/Fonts"

    private func loadSampleData(_ name: String) -> GoDData? {
        let url = URL(fileURLWithPath: samplesDir).appendingPathComponent(name)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return GoDData(byteStream: Array(raw), byteOrder: .big)
    }

    /// Font_Data_14 is a 22×22 primary block with a linked 18×18 secondary
    /// block sharing the same 6 character codes. Asserts the primary block's
    /// fields match known values.
    func testFont14_primaryBlockHasExpectedFields() throws {
        guard let orig = loadSampleData("Font_Data_14.fnt") else {
            throw XCTSkip("Font_Data_14.fnt not available")
        }
        let primary = try GSFont(data: orig)
        XCTAssertEqual(primary.fontId, 0)
        XCTAssertEqual(primary.glyphWidth, 22)
        XCTAssertEqual(primary.glyphHeight, 22)
        XCTAssertEqual(primary.glyphs.count, 6)
        XCTAssertEqual(primary.glyphs.last?.code, 0x9854,
                       "last glyph in the char table")
    }

    /// The secondary block follows the primary in the linked-list chain.
    /// Asserts the secondary's fields are what we'd expect for Font_Data_14.
    func testFont14_secondaryBlockIsReachableFromPrimary() throws {
        guard let orig = loadSampleData("Font_Data_14.fnt") else {
            throw XCTSkip("Font_Data_14.fnt not available")
        }
        let primary = try GSFont(data: orig)
        let secondary = try XCTUnwrap(primary.nextFont,
                                      "Font_Data_14 has a secondary block")
        XCTAssertEqual(secondary.fontId, 1)
        XCTAssertEqual(secondary.glyphWidth, 18)
        XCTAssertEqual(secondary.glyphHeight, 18)
        XCTAssertEqual(secondary.glyphs.count, 6)
        XCTAssertNil(secondary.nextFont, "chain terminates at the secondary")
    }

    /// Font_Data_5 has three nested blocks (primary + two 18×18 siblings)
    /// — confirms the chain walker handles depth > 2.
    func testFont5_chainHasThreeBlocks() throws {
        guard let orig = loadSampleData("Font_Data_5.fnt") else {
            throw XCTSkip("Font_Data_5.fnt not available")
        }
        let font = try GSFont(data: orig)
        var blocks = 0
        var cur: GSFont? = font
        while let b = cur { blocks += 1; cur = b.nextFont }
        XCTAssertEqual(blocks, 3)
    }

    /// Font_Data_24 is a single ~729 KB block (CJK glyph set). Asserts
    /// the glyph count and absence of a secondary block.
    func testFont24_singleBlockHas2919Glyphs() throws {
        guard let orig = loadSampleData("Font_Data_24.fnt") else {
            throw XCTSkip("Font_Data_24.fnt not available")
        }
        let font = try GSFont(data: orig)
        XCTAssertEqual(font.glyphs.count, 2919)
        XCTAssertNil(font.nextFont)
    }

    /// The space glyph's bitmap is all zeros — catches off-by-one errors
    /// in where the bitmap region starts.
    func testFont16_spaceGlyphBitmapIsAllZero() throws {
        guard let orig = loadSampleData("Font_Data_16.fnt") else {
            throw XCTSkip("Font_Data_16.fnt not available")
        }
        let font = try GSFont(data: orig)
        let space = try XCTUnwrap(font.glyphs.first(where: { $0.code == 0x20 }),
                                  "space glyph present in primary block")
        XCTAssertEqual(space.bitmap.count, 88, "adv=8, h=22 → 4×22 bytes")
        XCTAssertTrue(space.bitmap.allSatisfy { $0 == 0 })
    }
}
