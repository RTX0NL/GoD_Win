//
//  PBRFontTests.swift
//  PBRTests
//
//  Two layers, following the project's encode/decode split:
//
//  1. Synthetic fonts built in memory, so the geometry rules are asserted
//     against a stated expectation rather than against the parser's own
//     output. These always run.
//  2. The real PAL and JP corpora, which repack byte-identically. These skip
//     cleanly without a PBR dump.
//

import XCTest
import Foundation
import GoDFoundation
@testable import PBR

final class PBRFontTests: XCTestCase {

    // MARK: - Helpers

    /// A glyph whose bitmap is `stride × height` of a recognisable value, so
    /// a misplaced read shows up as wrong bytes rather than a size mismatch.
    ///
    /// An odd width leaves the final byte's low nibble outside the glyph — it
    /// is not a pixel, and the real corpus always leaves it zero. The fixture
    /// does the same, because the atlas carries pixels and cannot round-trip
    /// a value stored where no pixel exists.
    private func glyph(
        code: UInt16, width: Int, firstRow: Int, lastRow: Int,
        lineHeight: Int = 26, fill: UInt8 = 0xAB
    ) -> PBRFont.Glyph {
        let stride = (width + 1) / 2
        let height = lastRow - firstRow + 1
        var bitmap = [UInt8](repeating: fill, count: max(0, stride * height))
        if width % 2 == 1 {
            for row in 0 ..< max(0, height) {
                bitmap[row * stride + stride - 1] &= 0xF0
            }
        }
        return .init(
            code: code, width: width, firstRow: firstRow, lastRow: lastRow,
            lineHeight: lineHeight, bitmap: bitmap
        )
    }

    private func sampleFont() -> PBRFont {
        PBRFont(blocks: [
            .init(language: "U", nominalSize: 32, glyphs: [
                glyph(code: 0x20, width: 6, firstRow: 26, lastRow: 26),
                glyph(code: 0x41, width: 12, firstRow: 9, lastRow: 26),
                glyph(code: 0x4E00, width: 22, firstRow: 11, lastRow: 25),
            ]),
            .init(language: "U", nominalSize: 24, glyphs: [
                glyph(code: 0x41, width: 9, firstRow: 7, lastRow: 19, lineHeight: 20),
            ]),
        ], name: "sample")
    }

    // MARK: - Geometry

    /// Height is the one field the format doesn't store — it falls out of the
    /// two row bounds — so it gets asserted directly.
    func testGlyphHeightAndStrideDeriveFromTheRowBounds() {
        let g = glyph(code: 0x41, width: 9, firstRow: 7, lastRow: 19)
        XCTAssertEqual(g.height, 13, "lastRow - firstRow + 1")
        XCTAssertEqual(g.stride, 5, "ceil(width / 2) at 4bpp")
        XCTAssertEqual(g.bitmap.count, 65, "stride × height")
    }

    func testDecodeReadsTheDeclaredGeometry() throws {
        let decoded = try PBRFont(data: sampleFont().data)
        XCTAssertEqual(decoded.blocks.count, 2)
        XCTAssertEqual(decoded.blocks[0].language, "U")
        XCTAssertEqual(decoded.blocks[0].nominalSize, 32)
        XCTAssertEqual(decoded.blocks[0].glyphs.map(\.code), [0x20, 0x41, 0x4E00])
        XCTAssertEqual(decoded.blocks[1].nominalSize, 24)

        let wide = try XCTUnwrap(decoded.blocks[0].glyphs.first { $0.code == 0x4E00 })
        XCTAssertEqual(wide.width, 22)
        XCTAssertEqual(wide.height, 15)
        XCTAssertEqual(wide.bitmap.count, 11 * 15)
        XCTAssertTrue(wide.bitmap.allSatisfy { $0 == 0xAB }, "pixel rows must survive intact")
    }

    /// The offset table has no count field — its length is implied by its own
    /// first entry — so a writer that miscounts blocks corrupts the file.
    func testOffsetTableLengthIsImpliedByItsFirstEntry() throws {
        let bytes = sampleFont().data
        bytes.setByteOrder(.big)
        let first: UInt32 = bytes.readSafely(atAddress: 0)
        XCTAssertEqual(Int(first) / 4, 2, "two blocks means a two-entry table")

        // Every entry must point at a 'FONT' magic.
        for i in 0 ..< Int(first) / 4 {
            let offset = Int(bytes.readSafely(atAddress: i * 4) as UInt32)
            let magic = try XCTUnwrap(bytes.read(atAddress: offset, length: 4))
            XCTAssertEqual(magic.rawBytes, Array("FONT".utf8), "block \(i)")
        }
    }

    func testBlocksAreAlignedToFourBytes() throws {
        // Three glyphs of odd width give a body length that needs padding.
        let font = PBRFont(blocks: [
            .init(language: "J", nominalSize: 24, glyphs: [
                glyph(code: 0x41, width: 3, firstRow: 0, lastRow: 0),
            ]),
            .init(language: "J", nominalSize: 24, glyphs: [
                glyph(code: 0x42, width: 3, firstRow: 0, lastRow: 0),
            ]),
        ])
        let bytes = font.data
        bytes.setByteOrder(.big)
        let second = Int(bytes.readSafely(atAddress: 4) as UInt32)
        XCTAssertEqual(second % 4, 0, "a block must start on a 4-byte boundary")
        XCTAssertEqual(try PBRFont(data: bytes).blocks.count, 2)
    }

    func testRoundTripPreservesEveryField() throws {
        let original = sampleFont()
        let decoded = try PBRFont(data: original.data, name: original.name)
        XCTAssertEqual(decoded.blocks, original.blocks)
    }

    // MARK: - Rejection

    /// `GSFont` and `PBRFont` share the `.fnt` extension, so each must refuse
    /// the other's files rather than reading them as garbage.
    func testRejectsDataThatIsNotAFontContainer() {
        let notAFont = GoDData(byteStream: [0x00, 0x00, 0x16, 0x16, 0x00, 0x00, 0x02, 0x70], byteOrder: .big)
        XCTAssertThrowsError(try PBRFont(data: notAFont)) { error in
            guard case PBRFont.Error.notAFontContainer = error else {
                return XCTFail("expected notAFontContainer, got \(error)")
            }
        }
    }

    func testRejectsAGlyphWhoseBitmapLeavesItsBlock() throws {
        let original = sampleFont().data
        original.setByteOrder(.big)
        // Push the first glyph's bitmap offset past the block.
        let blockStart = Int(original.readSafely(atAddress: 0) as UInt32)
        var raw = original.rawBytes
        let field = blockStart + 8 + 6
        raw.replaceSubrange(field ..< (field + 4), with: [0xFF, 0xFF, 0xFF, 0x00])
        let bytes = GoDData(byteStream: raw, byteOrder: .big)
        XCTAssertThrowsError(try PBRFont(data: bytes)) { error in
            guard case PBRFont.Error.glyphOutOfBounds = error else {
                return XCTFail("expected glyphOutOfBounds, got \(error)")
            }
        }
    }

    // MARK: - Real corpus

    /// Folders that may hold unpacked PBR fonts. `GODDESS_PBR_FONTS` wins.
    private var fontFolders: [String] {
        if let override = ProcessInfo.processInfo.environment["GODDESS_PBR_FONTS"] {
            return [override]
        }
        let home = NSHomeDirectory()
        return [
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Unpacked",
            home + "/Downloads/GODDESS-JP-dump/PBR JP project/Build/Unpacked",
        ]
    }

    private func corpusFonts() -> [(name: String, bytes: GoDData)] {
        var found = [(name: String, bytes: GoDData)]()
        for root in fontFolders {
            guard let walker = FileManager.default.enumerator(atPath: root) else { continue }
            for case let path as String in walker where path.lowercased().hasSuffix(".fnt") {
                let full = root + "/" + path
                guard let data = FileManager.default.contents(atPath: full) else { continue }
                // The folder also holds Genius Sonority fonts on a Colo/XD
                // project; only PBR containers start with a table pointing at
                // a 'FONT' magic, and `init` is what decides that.
                found.append((full, GoDData(data: data, byteOrder: .big)))
            }
        }
        return found
    }

    /// Every real font must repack byte-identically. This is the claim that
    /// makes the format safe to edit: anything the parser drops shows up here.
    func testRealCorpusRepacksByteIdentically() throws {
        let fonts = corpusFonts()
        guard !fonts.isEmpty else {
            throw XCTSkip("No unpacked PBR fonts — set GODDESS_PBR_FONTS to run.")
        }
        var checked = 0
        var glyphs = 0
        for (name, bytes) in fonts {
            let font: PBRFont
            do {
                font = try PBRFont(data: bytes)
            } catch {
                // A Genius Sonority `.fnt` sitting in the same tree is not a
                // failure — it's a different format and must be refused.
                continue
            }
            let repacked = font.data
            XCTAssertEqual(
                repacked.rawBytes, bytes.rawBytes,
                "\(name) did not repack byte-identically"
            )
            checked += 1
            glyphs += font.blocks.reduce(0) { $0 + $1.glyphs.count }
        }
        guard checked > 0 else {
            throw XCTSkip("Found .fnt files but none were PBR font containers.")
        }
        XCTAssertGreaterThan(glyphs, 0)
        print("[PBRFont] \(checked) real fonts repacked byte-identically (\(glyphs) glyphs)")
    }

    /// Every glyph's bitmap must tile exactly at `stride × height` — no gaps,
    /// no overlap — which is what lets the writer re-derive the offsets
    /// instead of storing them.
    func testRealCorpusGlyphBitmapsTileExactly() throws {
        let fonts = corpusFonts()
        guard !fonts.isEmpty else {
            throw XCTSkip("No unpacked PBR fonts — set GODDESS_PBR_FONTS to run.")
        }
        var anyChecked = false
        for (name, bytes) in fonts {
            guard let font = try? PBRFont(data: bytes) else { continue }
            anyChecked = true
            for (index, block) in font.blocks.enumerated() {
                for g in block.glyphs {
                    XCTAssertEqual(
                        g.bitmap.count, g.stride * max(0, g.height),
                        "\(name) block \(index) U+\(String(format: "%04X", g.code))"
                    )
                }
            }
        }
        guard anyChecked else { throw XCTSkip("No PBR font containers found.") }
    }

    // MARK: - Atlas artifacts

    /// The editable bundle has to survive a full round trip, or editing a font
    /// silently degrades it. This is the claim that matters for the artifacts,
    /// exactly as byte-identical repacking is the claim for the binary.
    func testAtlasRoundTripReproducesTheFont() throws {
        let original = sampleFont()
        let bundle = try original.outputs
        XCTAssertEqual(bundle.count, 2, "manifest + atlas")
        XCTAssertTrue(bundle[0].file.path.hasSuffix(".fnt.json"))
        XCTAssertTrue(bundle[1].file.path.hasSuffix(".fnt.png"))

        let rebuilt = try PBRFont(outputs: bundle)
        XCTAssertEqual(rebuilt.blocks, original.blocks)
        XCTAssertEqual(try rebuilt.binaries[0].data.rawBytes, original.data.rawBytes)
    }

    /// A glyph with no ink still has an extent, and the manifest is what
    /// carries it — deriving the row bounds back from pixels would erase a
    /// blank glyph entirely. The real corpus contains several.
    func testBlankGlyphKeepsItsMetricsThroughTheAtlas() throws {
        let blank = PBRFont.Glyph(
            code: 0x20, width: 6, firstRow: 26, lastRow: 26, lineHeight: 26,
            bitmap: [0x00, 0x00, 0x00]
        )
        let font = PBRFont(blocks: [.init(language: "J", nominalSize: 32, glyphs: [blank])])
        let rebuilt = try PBRFont(outputs: try font.outputs)
        XCTAssertEqual(rebuilt.blocks[0].glyphs[0], blank)
    }

    /// Mid-tone pixels must survive: the atlas is 8bpp and the font 4bpp, so
    /// the expansion has to be reversible rather than a lossy scale.
    func testIntermediateIntensitiesSurviveTheAtlas() throws {
        let ramp = PBRFont.Glyph(
            code: 0x41, width: 4, firstRow: 0, lastRow: 1, lineHeight: 26,
            bitmap: [0x01, 0x23, 0x45, 0x67]
        )
        let font = PBRFont(blocks: [.init(language: "U", nominalSize: 24, glyphs: [ramp])])
        let rebuilt = try PBRFont(outputs: try font.outputs)
        XCTAssertEqual(rebuilt.blocks[0].glyphs[0].bitmap, ramp.bitmap)
    }

    /// Every real font must survive binary -> artifacts -> binary unchanged.
    func testRealCorpusSurvivesTheAtlasRoundTrip() throws {
        let fonts = corpusFonts()
        guard !fonts.isEmpty else {
            throw XCTSkip("No unpacked PBR fonts — set GODDESS_PBR_FONTS to run.")
        }
        var checked = 0
        for (name, bytes) in fonts {
            guard let font = try? PBRFont(data: bytes) else { continue }
            let rebuilt = try PBRFont(outputs: try font.outputs)
            XCTAssertEqual(
                try rebuilt.binaries[0].data.rawBytes, bytes.rawBytes,
                "\(name) did not survive the atlas round trip"
            )
            checked += 1
        }
        guard checked > 0 else { throw XCTSkip("No PBR font containers found.") }
        print("[PBRFont] \(checked) real fonts survived binary -> atlas -> binary")
    }

    // MARK: - Atlas format safeguards

    /// The atlas is a greyscale PNG now, not a PGM. Both matter: the magic
    /// proves the format, and greyscale (rather than RGBA) proves we didn't
    /// just reuse the texture encoder on intensity-only data.
    func testAtlasIsAGreyscalePNG() throws {
        let bundle = try sampleFont().outputs
        let atlas = try XCTUnwrap(bundle.first { $0.file.path.hasSuffix(".png") })
        let bytes = atlas.data.rawBytes
        XCTAssertEqual(Array(bytes.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                       "atlas should be a PNG")
        // IHDR colour-type byte sits at offset 25; 0 = greyscale.
        XCTAssertEqual(bytes[25], 0, "atlas should be greyscale, not RGB/RGBA")
        XCTAssertEqual(bytes[24], 8, "atlas should be 8 bits per sample")
    }

    /// A PNG can come back from an editor as colour, which a PGM never could.
    /// It must still load — and must say so.
    func testColouredAtlasLoadsAndWarns() throws {
        let font = sampleFont()
        let (image, metadata) = PBRFontAtlas.exportAtlas(font: font, atlasPath: "a.png")
        let grey = try XCTUnwrap(GreyscaleImage.fromPNG(image))
        // Rebuild the same pixels as an RGB image with one tinted pixel.
        var rgba = [UInt8]()
        for (i, v) in grey.pixels.enumerated() {
            // Pixel 0 is blank in this font, so the tint has to be
            // unconditional or nothing coloured actually reaches the importer.
            rgba += i == 0 ? [0xFF, 0x00, 0x00, 0xFF] : [v, v, v, 255]
        }
        let coloured = try XCTUnwrap(
            GoDImage(width: grey.width, height: grey.height,
                     pixels: GoDData(byteStream: rgba, byteOrder: .big)).pngData()
        )
        let imported = try PBRFontAtlas.importAtlas(imageData: coloured, metadata: metadata)
        XCTAssertFalse(imported.warnings.isEmpty, "a coloured atlas must be reported")
        XCTAssertTrue(imported.warnings.contains { $0.contains("colour") || $0.contains("grey") },
                      "got \(imported.warnings)")
    }

    /// A 4bpp font can only hold 16 levels. Anti-aliasing or resampling in an
    /// editor introduces values off that grid; they get rounded, and the user
    /// is told rather than left to discover it.
    func testOffGridIntensitiesAreReported() throws {
        let font = sampleFont()
        let (image, metadata) = PBRFontAtlas.exportAtlas(font: font, atlasPath: "a.png")
        var grey = try XCTUnwrap(GreyscaleImage.fromPNG(image))
        var pixels = grey.pixels
        // 0x80 is not a multiple of 0x11, so it cannot be a real 4bpp level.
        pixels[0] = 0x80
        grey = GreyscaleImage(width: grey.width, height: grey.height, pixels: pixels)
        let nudged = try XCTUnwrap(grey.pngData())
        let imported = try PBRFontAtlas.importAtlas(imageData: nudged, metadata: metadata)
        XCTAssertTrue(imported.warnings.contains { $0.contains("16 levels") },
                      "got \(imported.warnings)")
    }

    /// A clean round trip must produce no warnings at all — otherwise the
    /// checks would cry wolf on every ordinary rebuild.
    func testCleanRoundTripWarnsAboutNothing() throws {
        let font = sampleFont()
        let (image, metadata) = PBRFontAtlas.exportAtlas(font: font, atlasPath: "a.png")
        let imported = try PBRFontAtlas.importAtlas(imageData: image, metadata: metadata)
        XCTAssertEqual(imported.warnings, [], "a faithful atlas should be silent")
        XCTAssertEqual(imported.font.blocks, font.blocks)
    }
}
