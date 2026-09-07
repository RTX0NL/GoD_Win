//
//  PBRFontAtlas.swift
//  PBR
//
//  Editable artifacts for `PBRFont`: one greyscale atlas image plus a JSON
//  manifest, mirroring what `GSFontAtlas` does for Colosseum/XD fonts so both
//  font families present the same editing surface.
//
//  The atlas is a greyscale PNG. It was a binary PGM, which is trivially
//  simple to write but opens nowhere on Windows without extra software, and
//  is an order of magnitude larger — these sheets are mostly empty, so PNG
//  compresses them 10-50x. Every other image artifact the tool emits (GTX,
//  ATX, flash-menu textures) is already PNG, so fonts were the odd one out.
//
//  PNG's tolerance is the one thing it costs us: a PGM can only be one thing,
//  whereas an editor may hand back RGB, 16-bit or colour-managed pixels. The
//  importer therefore *checks* rather than assumes — see `verify(...)`, which
//  warns instead of failing, because a warning is recoverable and a hard
//  failure on someone else's exported file is not.
//
//  The atlas is a grid of fixed-size cells, one glyph per cell, blocks stacked
//  top to bottom. Cells are uniform *within* a block and sized from that
//  block's widest glyph and lowest occupied row, so a cell is the glyph's line
//  box rather than a tight crop — a glyph is drawn at its own `firstRow`, and
//  the rows above and below it stay blank. That keeps glyphs visually aligned
//  in the sheet, which is the point of editing them as a sheet.
//
//  Per-glyph metrics live in the manifest, not in the pixels. Deriving
//  `firstRow`/`lastRow` back from ink would mean a glyph silently changed
//  metrics whenever someone painted a stray pixel, and an all-blank glyph
//  (the corpus has several) would lose its extent entirely. The manifest is
//  authoritative, so a round trip is exact and editing metrics is deliberate.
//

import Foundation
import GoDFoundation

public enum PBRFontAtlas {

    public struct Metadata: Codable, Equatable {
        /// Atlas filename, relative to the manifest's own folder.
        public let atlasPath: String
        /// Glyphs per row in the sheet.
        public let columns: Int
        public let blocks: [Block]

        public struct Block: Codable, Equatable {
            public let language: String
            public let nominalSize: Int
            /// Cell size for this block, in pixels.
            public let cellWidth: Int
            public let cellHeight: Int
            /// Row of the atlas (in cells) this block starts at.
            public let originRow: Int
            public let glyphs: [Glyph]
        }

        public struct Glyph: Codable, Equatable {
            public let code: Int
            /// The character, for readability when editing. Never parsed.
            public let character: String
            public let width: Int
            public let firstRow: Int
            public let lastRow: Int
            public let lineHeight: Int
            public let gridRow: Int
            public let gridCol: Int
        }
    }

    public enum Error: GoDError {
        case invalidAtlas(ErrorTrace = .init())
        case atlasTooSmall(expected: String, got: String, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .invalidAtlas(trace):
                return "Error: font atlas is not a readable PNG.\n\(trace)"
            case let .atlasTooSmall(expected, got, trace):
                return "Error: font atlas is \(got); the manifest describes \(expected).\n\(trace)"
            }
        }
    }

    // MARK: - Export

    public static func exportAtlas(
        font: PBRFont,
        atlasPath: String,
        columns: Int = 16
    ) -> (imageData: GoDData, metadata: Metadata) {
        // Lay every block out first so the sheet's dimensions are known
        // before any pixel is written.
        struct Placed {
            let cellWidth: Int, cellHeight: Int, rows: Int, originRow: Int
        }
        var placements = [Placed]()
        var originRow = 0
        for block in font.blocks {
            let cellWidth = max(1, block.glyphs.map(\.width).max() ?? 1)
            let cellHeight = max(1, block.glyphs.map { $0.lastRow + 1 }.max() ?? 1)
            let rows = block.glyphs.isEmpty ? 0 : (block.glyphs.count + columns - 1) / columns
            placements.append(Placed(cellWidth: cellWidth, cellHeight: cellHeight,
                                     rows: rows, originRow: originRow))
            originRow += rows
        }

        let imageWidth = max(1, placements.map { $0.cellWidth * columns }.max() ?? 1)
        let imageHeight = max(1, zip(font.blocks, placements).reduce(0) {
            $0 + $1.1.rows * $1.1.cellHeight
        })
        var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight)

        var metaBlocks = [Metadata.Block]()
        var yCursor = 0
        for (block, placed) in zip(font.blocks, placements) {
            var metaGlyphs = [Metadata.Glyph]()
            for (index, glyph) in block.glyphs.enumerated() {
                let gridRow = index / columns
                let gridCol = index % columns
                let originX = gridCol * placed.cellWidth
                let originY = yCursor + gridRow * placed.cellHeight

                // 4bpp source, upper nibble = left pixel, expanded to 8bpp by
                // replicating the nibble so mid-tones survive a round trip.
                for row in 0 ..< max(0, glyph.height) {
                    for column in 0 ..< glyph.width {
                        let byteIndex = row * glyph.stride + column / 2
                        guard byteIndex < glyph.bitmap.count else { continue }
                        let byte = glyph.bitmap[byteIndex]
                        let nibble = column % 2 == 0 ? (byte >> 4) : (byte & 0x0F)
                        let y = originY + glyph.firstRow + row
                        let x = originX + column
                        guard y < imageHeight, x < imageWidth else { continue }
                        pixels[y * imageWidth + x] = nibble * 0x11
                    }
                }
                metaGlyphs.append(.init(
                    code: Int(glyph.code),
                    character: UnicodeScalar(glyph.code).map { String(Character($0)) } ?? "",
                    width: glyph.width, firstRow: glyph.firstRow, lastRow: glyph.lastRow,
                    lineHeight: glyph.lineHeight, gridRow: gridRow, gridCol: gridCol
                ))
            }
            metaBlocks.append(.init(
                language: String(block.language), nominalSize: block.nominalSize,
                cellWidth: placed.cellWidth, cellHeight: placed.cellHeight,
                originRow: placed.originRow, glyphs: metaGlyphs
            ))
            yCursor += placed.rows * placed.cellHeight
        }

        let image = GreyscaleImage(width: imageWidth, height: imageHeight, pixels: pixels)
        let encoded = image.pngData() ?? GoDData(byteStream: [UInt8](), byteOrder: .big)
        return (encoded,
                Metadata(atlasPath: atlasPath, columns: columns, blocks: metaBlocks))
    }

    // MARK: - Import

    /// Imports the atlas, returning the font plus anything questionable about
    /// the image the caller should surface. Warnings rather than errors: an
    /// atlas that came back from an image editor slightly off-spec should
    /// still load, with the drift reported.
    public static func importAtlas(
        imageData: GoDData,
        metadata: Metadata,
        name: String = "fnt"
    ) throws -> (font: PBRFont, warnings: [String]) {
        var warnings = [String]()
        guard let image = GreyscaleImage.fromPNG(imageData) else {
            throw Error.invalidAtlas()
        }
        let imageWidth = image.width, imageHeight = image.height, pixels = image.pixels
        warnings.append(contentsOf: verify(image))

        var blocks = [PBRFont.Block]()
        var yCursor = 0
        for block in metadata.blocks {
            var glyphs = [PBRFont.Glyph]()
            for glyph in block.glyphs {
                let originX = glyph.gridCol * block.cellWidth
                let originY = yCursor + glyph.gridRow * block.cellHeight
                let height = glyph.lastRow - glyph.firstRow + 1
                let stride = (glyph.width + 1) / 2
                var bitmap = [UInt8](repeating: 0, count: max(0, stride * height))

                for row in 0 ..< max(0, height) {
                    for column in 0 ..< glyph.width {
                        let y = originY + glyph.firstRow + row
                        let x = originX + column
                        guard y < imageHeight, x < imageWidth else {
                            throw Error.atlasTooSmall(
                                expected: "at least \(x + 1)x\(y + 1)",
                                got: "\(imageWidth)x\(imageHeight)"
                            )
                        }
                        let nibble = pixels[y * imageWidth + x] >> 4
                        let byteIndex = row * stride + column / 2
                        if column % 2 == 0 {
                            bitmap[byteIndex] |= nibble << 4
                        } else {
                            bitmap[byteIndex] |= nibble
                        }
                    }
                }
                glyphs.append(.init(
                    code: UInt16(glyph.code), width: glyph.width,
                    firstRow: glyph.firstRow, lastRow: glyph.lastRow,
                    lineHeight: glyph.lineHeight, bitmap: bitmap
                ))
            }
            blocks.append(.init(
                language: block.language.first ?? " ",
                nominalSize: block.nominalSize,
                glyphs: glyphs
            ))
            let rows = block.glyphs.isEmpty
                ? 0
                : (block.glyphs.count + metadata.columns - 1) / metadata.columns
            yCursor += rows * block.cellHeight
        }
        return (PBRFont(blocks: blocks, name: name), warnings)
    }

    /// Preconditions the atlas should meet, checked rather than assumed.
    ///
    /// A PGM could only ever be 8-bit greyscale; a PNG can come back as RGB,
    /// 16-bit or colour-managed, and `GreyscaleImage` will quietly collapse
    /// all of it. These are the two ways that collapse can lose information,
    /// so they get named explicitly instead of silently rounding.
    private static func verify(_ image: GreyscaleImage) -> [String] {
        var out = [String]()
        if !image.wasNeutral {
            out.append(
                "Font atlas contains coloured pixels; it was converted to greyscale by "
                + "luminance. Save it as a greyscale image to keep intensities exact."
            )
        }
        // The font is 4bpp, so every pixel must land on one of 16 levels
        // (nibble x 0x11). Anything else was introduced by an editor —
        // anti-aliasing, resampling or a colour profile — and gets rounded
        // to the nearest level on the way back in.
        var offGrid = 0
        for value in image.pixels where value % 0x11 != 0 { offGrid += 1 }
        if offGrid > 0 {
            let percent = Double(offGrid) * 100 / Double(max(1, image.pixels.count))
            out.append(String(
                format: "Font atlas has %d pixels (%.2f%%) that aren't one of the 16 levels "
                      + "a 4bpp font can store; they will be rounded to the nearest.",
                offGrid, percent
            ))
        }
        return out
    }

}
