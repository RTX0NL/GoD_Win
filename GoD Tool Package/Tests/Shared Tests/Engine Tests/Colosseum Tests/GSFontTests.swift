import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class GSFontTests: XCTestCase {

    private let samplesDir = "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Assets/Text/Fonts"

    private func loadSampleData(_ name: String) -> GoDData? {
        let url = URL(fileURLWithPath: samplesDir).appendingPathComponent(name)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return GoDData(byteStream: Array(raw), byteOrder: .big)
    }

    func testRoundTripFont_Data_14() throws {
        guard let orig = loadSampleData("Font_Data_14.fnt") else {
            throw XCTSkip("Sample Font_Data_14.fnt not available")
        }
        let font = try GSFont(data: orig)
        let rebuilt = try font.data
        XCTAssertEqual(rebuilt.rawBytes, orig.rawBytes,
                       "Font_Data_14 round-trip mismatch (size: \(rebuilt.length) vs \(orig.length))")
    }

    func testRoundTripFont_Data_16() throws {
        guard let orig = loadSampleData("Font_Data_16.fnt") else {
            throw XCTSkip("Sample Font_Data_16.fnt not available")
        }
        let font = try GSFont(data: orig)
        let rebuilt = try font.data
        XCTAssertEqual(rebuilt.rawBytes, orig.rawBytes, "Font_Data_16 round-trip mismatch")
    }

    func testRoundTripFont_Data_24() throws {
        // Large CJK set, single font block (no secondary), ~729 KB.
        guard let orig = loadSampleData("Font_Data_24.fnt") else {
            throw XCTSkip("Sample Font_Data_24.fnt not available")
        }
        let font = try GSFont(data: orig)
        let rebuilt = try font.data
        XCTAssertEqual(rebuilt.rawBytes, orig.rawBytes, "Font_Data_24 round-trip mismatch")
    }

    func testTwoFontBlocksParsed() throws {
        // Font_Data_14 is 22×22 primary + 18×18 secondary, same char codes.
        guard let orig = loadSampleData("Font_Data_14.fnt") else {
            throw XCTSkip("Sample Font_Data_14.fnt not available")
        }
        let primary = try GSFont(data: orig)
        XCTAssertEqual(primary.fontId, 0)
        XCTAssertEqual(primary.glyphWidth, 22)
        XCTAssertEqual(primary.glyphHeight, 22)
        XCTAssertEqual(primary.glyphs.count, 6)
        // Primary's last glyph (the one I used to mistake for a "sentinel")
        XCTAssertEqual(primary.glyphs.last?.code, 0x9854)

        guard let secondary = primary.nextFont else {
            return XCTFail("Expected secondary font block at dataSize offset")
        }
        XCTAssertEqual(secondary.fontId, 1)
        XCTAssertEqual(secondary.glyphWidth, 18)
        XCTAssertEqual(secondary.glyphHeight, 18)
        XCTAssertEqual(secondary.glyphs.count, 6)
        XCTAssertNil(secondary.nextFont)
    }

    func testRoundTripFont_Data_5_triNested() throws {
        // Font_Data_5 has three nested blocks (primary 22×22 + two nested
        // 18×18 blocks). Exercises relative nextOffset handling.
        guard let orig = loadSampleData("Font_Data_5.fnt") else {
            throw XCTSkip("Sample Font_Data_5.fnt not available")
        }
        let font = try GSFont(data: orig)
        let rebuilt = try font.data
        XCTAssertEqual(rebuilt.rawBytes, orig.rawBytes, "Font_Data_5 round-trip mismatch")
        // Count blocks in chain
        var blocks = 0
        var cur: GSFont? = font
        while let b = cur { blocks += 1; cur = b.nextFont }
        XCTAssertEqual(blocks, 3, "Expected 3 nested font blocks in Font_Data_5")
    }

    func testSingleBlockFontHasNoSecondary() throws {
        // Font_Data_24's nextBlockOffset is 0 — only one block.
        guard let orig = loadSampleData("Font_Data_24.fnt") else {
            throw XCTSkip("Sample Font_Data_24.fnt not available")
        }
        let font = try GSFont(data: orig)
        XCTAssertEqual(font.glyphs.count, 2919)
        XCTAssertNil(font.nextFont)
    }

    func testSpaceGlyphIsAllZero() throws {
        // Font_Data_16 glyph for U+0020 (space) must have an all-zero 88-byte
        // bitmap (adv=8, h=22 → 4×22 = 88 bytes). Catches off-by-one errors
        // in where the bitmap region starts.
        guard let orig = loadSampleData("Font_Data_16.fnt") else {
            throw XCTSkip("Sample Font_Data_16.fnt not available")
        }
        let font = try GSFont(data: orig)
        guard let space = font.glyphs.first(where: { $0.code == 0x20 }) else {
            return XCTFail("Space glyph not found in Font_Data_16 primary")
        }
        XCTAssertEqual(space.bitmap.count, 88)
        XCTAssertTrue(space.bitmap.allSatisfy { $0 == 0 })
    }
}
