//
//  GSFontAtlasTests.swift
//  ColosseumTests
//
//  The atlas is a grid of cells, one glyph each. Which size those cells are
//  is the whole of this file: the block header declares a glyph size, but it
//  is a nominal size rather than a measured one, and Colosseum's 2920-glyph
//  kanji block declares 21x21 while every glyph in it advances 22px. Cells
//  sized from the header put that last column in the next cell, where the
//  glyph drawn there overwrote it — so the font came back with each glyph
//  wearing its neighbour's first column, and the two copies of that sheet
//  were the only fonts on the US disc that didn't rebuild byte-identically.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class GSFontAtlasTests: XCTestCase {

    /// A glyph whose every pixel is set, so losing any column shows up.
    private func solidGlyph(code: UInt16, advance: UInt8, height: UInt8) -> GSFont.Glyph {
        let bytesPerRow = (Int(advance) + 1) / 2
        return GSFont.Glyph(
            code: code,
            advanceWidth: advance,
            height: height,
            flags: 0,
            bitmap: [UInt8](repeating: 0xF9, count: bytesPerRow * Int(height))
        )
    }

    private func font(
        declaring size: (width: Int, height: Int),
        glyphs: [GSFont.Glyph],
        next: GSFont? = nil
    ) -> GSFont {
        GSFont(
            fontId: 0,
            glyphWidth: size.width,
            glyphHeight: size.height,
            glyphs: glyphs,
            nextFont: next,
            blockPadding: []
        )
    }

    private func roundTrip(_ font: GSFont) throws -> GSFont {
        let (image, metadata) = try GSFontAtlas.exportAtlas(font: font, atlasPath: "atlas.png")
        return try GSFontAtlas.importAtlas(imageData: image, metadata: metadata).font
    }

    /// The Colosseum kanji case: glyphs a pixel wider than the size their
    /// block declares survive the atlas.
    func testGlyphsWiderThanTheirBlockHeaderSurviveTheAtlas() throws {
        let glyphs = (0..<40).map { solidGlyph(code: UInt16(0x4E00 + $0), advance: 22, height: 21) }
        let original = font(declaring: (width: 21, height: 21), glyphs: glyphs)

        let rebuilt = try roundTrip(original)

        XCTAssertEqual(try rebuilt.data.rawBytes, try original.data.rawBytes,
                       "a glyph wider than its block's declared size lost pixels in the atlas")
        XCTAssertEqual(rebuilt.glyphs.map(\.bitmap), original.glyphs.map(\.bitmap))
        // The header still says what it said; only the atlas cell grew.
        XCTAssertEqual(rebuilt.glyphWidth, 21)
        XCTAssertEqual(rebuilt.glyphHeight, 21)
    }

    /// Same for a glyph taller than its block.
    func testGlyphsTallerThanTheirBlockHeaderSurviveTheAtlas() throws {
        let glyphs = (0..<8).map { solidGlyph(code: UInt16(0x30 + $0), advance: 18, height: 20) }
        let original = font(declaring: (width: 18, height: 18), glyphs: glyphs)

        XCTAssertEqual(try roundTrip(original).data.rawBytes, try original.data.rawBytes)
    }

    /// The cell the dump drew in is written down rather than left to be
    /// re-derived, so an atlas and its metadata can't disagree.
    func testMetadataRecordsTheCellItDrewIn() throws {
        let wide = font(declaring: (width: 21, height: 21),
                        glyphs: [solidGlyph(code: 0x4E00, advance: 22, height: 21)])
        let (_, metadata) = try GSFontAtlas.exportAtlas(font: wide, atlasPath: "atlas.png")
        XCTAssertEqual(metadata.blocks.first?.cellWidth, 22)
        XCTAssertEqual(metadata.blocks.first?.cellHeight, 21)

        // A block whose glyphs fit keeps the header's size, so an atlas of an
        // ordinary font is laid out exactly as it always was.
        let ordinary = font(declaring: (width: 22, height: 22),
                            glyphs: [solidGlyph(code: 0x41, advance: 12, height: 18)])
        let (_, plain) = try GSFontAtlas.exportAtlas(font: ordinary, atlasPath: "atlas.png")
        XCTAssertEqual(plain.blocks.first?.cellWidth, 22)
        XCTAssertEqual(plain.blocks.first?.cellHeight, 22)
    }

    /// Metadata written before the cell was recorded is read the way it was
    /// written: the cell was the header's glyph size.
    func testMetadataWithoutACellFallsBackToTheHeaderSize() throws {
        let json = """
        {
          "atlasPath": "atlas.png",
          "columns": 32,
          "blocks": [
            {
              "fontId": 0,
              "glyphWidth": 21,
              "glyphHeight": 21,
              "gridOriginRow": 0,
              "rows": 1,
              "glyphs": []
            }
          ]
        }
        """
        let metadata = try JSONDecoder().decode(GSFontAtlas.Metadata.self, from: Data(json.utf8))
        let block = try XCTUnwrap(metadata.blocks.first)
        XCTAssertNil(block.cellWidth)
        XCTAssertEqual(block.cell.width, 21)
        XCTAssertEqual(block.cell.height, 21)
    }

    /// An odd-advance glyph stores one column past its advance — the low
    /// nibble of each row's last byte — and real fonts put stray values
    /// there. Colosseum JP's `pocket_menu` font has 2 and 1 in two rows of
    /// `何` (U+4F55, advance 23), and 133 of that disc's 137 fonts carry
    /// something similar.
    func testTheColumnPastAnOddAdvanceSurvivesTheAtlas() throws {
        // advance 23 -> 12 bytes a row, 24 stored columns. Fill the final
        // low nibble of every row with a value the advance doesn't cover.
        let advance = 23, height = 20, bytesPerRow = 12
        var bitmap = [UInt8](repeating: 0x5A, count: bytesPerRow * height)
        for row in 0..<height { bitmap[row * bytesPerRow + bytesPerRow - 1] = 0x02 }
        let glyph = GSFont.Glyph(code: 0x4F55, advanceWidth: UInt8(advance),
                                 height: UInt8(height), flags: 0, bitmap: bitmap)
        let original = font(declaring: (width: 22, height: 22), glyphs: [glyph])

        let rebuilt = try roundTrip(original)

        XCTAssertEqual(rebuilt.glyphs.first?.bitmap, bitmap,
                       "the column past the advance was dropped")
        XCTAssertEqual(try rebuilt.data.rawBytes, try original.data.rawBytes)
        XCTAssertEqual(rebuilt.glyphs.first?.advanceWidth, 23, "the advance itself must not grow")
    }

    /// Each block in the chain gets its own cell, and a wide block doesn't
    /// move the block below it.
    func testEachBlockInTheChainKeepsItsOwnCell() throws {
        let secondary = font(declaring: (width: 18, height: 18),
                             glyphs: (0..<5).map { solidGlyph(code: UInt16(0x41 + $0), advance: 18, height: 18) })
        let primary = font(declaring: (width: 21, height: 21),
                           glyphs: (0..<5).map { solidGlyph(code: UInt16(0x4E00 + $0), advance: 22, height: 21) },
                           next: secondary)

        let rebuilt = try roundTrip(primary)
        XCTAssertEqual(try rebuilt.data.rawBytes, try primary.data.rawBytes)
        let (_, metadata) = try GSFontAtlas.exportAtlas(font: primary, atlasPath: "atlas.png")
        XCTAssertEqual(metadata.blocks.map(\.cellWidth), [22, 18])
        XCTAssertEqual(metadata.blocks.map(\.cellHeight), [21, 18])
    }
}
