import GoDFoundation

/// Export/import font glyph atlases as grayscale images with JSON metadata.
///
/// The atlas arranges every glyph from every font block (primary 22×22 +
/// secondary 18×18 + …) in a grid. Each block gets its own row range, with
/// each cell sized to the block's own glyph dimensions. 4bpp nibble values
/// (0-15) are scaled to 8-bit (× 17 → 0-255). Output is PGM (Portable
/// GrayMap) — viewable in most image viewers and editable in any image
/// editor.
public struct GSFontAtlas {

    /// Metadata sidecar for the atlas image
    public struct Metadata: Codable {
        /// Path to the atlas image file, relative to this metadata
        /// file's directory. Lets the build op locate the atlas without
        /// having to specify it separately in the config.
        public let atlasPath: String
        public let columns: Int
        /// One entry per font block in the file-level chain (primary first).
        public let blocks: [Block]

        public struct Block: Codable {
            public let fontId: Int
            public let glyphWidth: Int
            public let glyphHeight: Int
            public let gridOriginRow: Int  // starting row in the atlas image
            public let rows: Int
            public let glyphs: [GlyphInfo]
            /// Padding bytes between this block's last glyph and the next
            /// block's start (alignment filler). Hex-encoded.
            public let blockPaddingHex: String?
            /// The atlas cell this block's glyphs are drawn in. Usually the
            /// header's glyph size, but not always — a block can hold glyphs
            /// larger than the size it declares (Colosseum's kanji sheet says
            /// 21x21 and every one of its 2920 glyphs advances 22px), and a
            /// cell that doesn't fit its glyphs loses their last column to
            /// the neighbour drawn over it. Written by every dump; absent in
            /// metadata written before it existed, where the cell *was* the
            /// header's glyph size.
            public let cellWidth: Int?
            public let cellHeight: Int?
            /// The block header's `+0x0A` word; absent when zero.
            public let unknown0A: Int?

            /// The cell to draw and read this block's glyphs in.
            public var cell: (width: Int, height: Int) {
                (cellWidth ?? glyphWidth, cellHeight ?? glyphHeight)
            }
        }

        public struct GlyphInfo: Codable {
            public let code: Int
            public let character: String?
            public let advanceWidth: Int
            public let height: Int
            public let flags: Int
            public let gridRow: Int
            public let gridCol: Int
        }
    }

    /// How many pixel columns a glyph's bitmap actually stores.
    ///
    /// A 4bpp row is whole bytes, so a glyph that advances an odd number of
    /// pixels stores one column past its advance in the low nibble of each
    /// row's last byte. That column is usually zero, but not always — 133 of
    /// Colosseum JP's 137 fonts carry stray values there (the kanji `何` has
    /// 2 and 1 in two of its rows) — and drawing only `advanceWidth` columns
    /// dropped them, so every one of those fonts came back changed.
    static func storedWidth(advanceWidth: Int) -> Int {
        ((advanceWidth + 1) / 2) * 2
    }

    private struct BlockGrid {
        let cols: Int
        let rows: Int
        let cellWidth: Int
        let cellHeight: Int
        var width: Int { cols * cellWidth }
        var height: Int { rows * cellHeight }
    }

    private static func flattenBlocks(_ font: GSFont) -> [GSFont] {
        var blocks = [GSFont]()
        var current: GSFont? = font
        while let b = current {
            blocks.append(b)
            current = b.nextFont
        }
        return blocks
    }

    /// One cell per glyph, sized to hold the largest glyph in the block.
    ///
    /// The block header's glyph size is the font's nominal cell and is what
    /// this used to lay out, but it is a declared size rather than a measured
    /// one: Colosseum's 2920-glyph kanji block declares 21x21 while every
    /// glyph in it advances 22px. Cells a pixel too narrow put each glyph's
    /// last column in the next cell, where the glyph drawn there overwrote
    /// it, so the column came back as its neighbour's on the way in.
    private static func computeGrids(_ blocks: [GSFont], columns: Int) -> [BlockGrid] {
        return blocks.map { b in
            let cols = min(columns, max(b.visibleGlyphs.count, 1))
            let rows = (b.visibleGlyphs.count + cols - 1) / cols
            let cellWidth = max(
                b.glyphWidth,
                b.visibleGlyphs.map { storedWidth(advanceWidth: Int($0.advanceWidth)) }.max() ?? 0
            )
            let cellHeight = max(b.glyphHeight, b.visibleGlyphs.map { Int($0.height) }.max() ?? 0)
            return BlockGrid(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        }
    }

    private static func drawGlyph(
        _ glyph: GSFont.Glyph,
        into pixels: inout [UInt8],
        baseX: Int, baseY: Int, imgWidth: Int, imgHeight: Int
    ) {
        let glyphW = storedWidth(advanceWidth: Int(glyph.advanceWidth))
        let glyphH = Int(glyph.height)
        let bpr = glyphW / 2
        for y in 0..<glyphH {
            for x in 0..<glyphW {
                let byteIndex = y * bpr + x / 2
                guard byteIndex < glyph.bitmap.count else { continue }
                let byte = glyph.bitmap[byteIndex]
                let nibble: UInt8 = (x % 2 == 0)
                    ? (byte >> 4) & 0x0F
                    : byte & 0x0F
                let py = baseY + y
                let px = baseX + x
                if px < imgWidth && py < imgHeight {
                    pixels[py * imgWidth + px] = nibble * 17
                }
            }
        }
    }

    private static func makeBlockMetadata(
        block: GSFont,
        grid: BlockGrid,
        gridOriginRow: Int,
        pixels: inout [UInt8],
        imgWidth: Int,
        imgHeight: Int
    ) -> Metadata.Block {
        var glyphInfos = [Metadata.GlyphInfo]()
        for (index, glyph) in block.visibleGlyphs.enumerated() {
            let gridRow = index / grid.cols
            let gridCol = index % grid.cols
            let baseX = gridCol * grid.cellWidth
            let baseY = gridOriginRow + gridRow * grid.cellHeight
            drawGlyph(glyph, into: &pixels, baseX: baseX, baseY: baseY, imgWidth: imgWidth, imgHeight: imgHeight)
            let codeInt = Int(glyph.code)
            var charStr: String? = nil
            if codeInt >= 0x20 && codeInt < 0xD800 {
                charStr = String(UnicodeScalar(codeInt)!)
            }
            glyphInfos.append(Metadata.GlyphInfo(
                code: codeInt,
                character: charStr,
                advanceWidth: Int(glyph.advanceWidth),
                height: Int(glyph.height),
                flags: Int(glyph.flags),
                gridRow: gridRow,
                gridCol: gridCol
            ))
        }
        let padHex: String? = block.blockPadding.isEmpty ? nil
            : block.blockPadding.map { String(format: "%02X", $0) }.joined()
        return Metadata.Block(
            fontId: Int(block.fontId),
            glyphWidth: block.glyphWidth,
            glyphHeight: block.glyphHeight,
            gridOriginRow: gridOriginRow,
            rows: grid.rows,
            glyphs: glyphInfos,
            blockPaddingHex: padHex,
            cellWidth: grid.cellWidth,
            cellHeight: grid.cellHeight,
            unknown0A: block.unknown0A == 0 ? nil : Int(block.unknown0A)
        )
    }

    /// Export every font block to a single grayscale atlas + metadata JSON.
    ///
    /// `atlasPath` is written into the metadata so the build op can locate
    /// the PGM without needing a separate config field. It's stored as a
    /// relative path — interpreted relative to the metadata JSON's directory.
    public static func exportAtlas(
        font: GSFont,
        atlasPath: String,
        columns: Int = 32
    ) throws -> (imageData: GoDData, metadata: Metadata) {
        let blocks = flattenBlocks(font)
        let blockGrids = computeGrids(blocks, columns: columns)

        var imgWidth = 0
        var imgHeight = 0
        for g in blockGrids {
            if g.width > imgWidth { imgWidth = g.width }
            imgHeight += g.height
        }

        var pixels = [UInt8](repeating: 0, count: imgWidth * imgHeight)
        var metaBlocks = [Metadata.Block]()
        var yCursor = 0
        for i in 0..<blocks.count {
            metaBlocks.append(makeBlockMetadata(
                block: blocks[i],
                grid: blockGrids[i],
                gridOriginRow: yCursor,
                pixels: &pixels,
                imgWidth: imgWidth,
                imgHeight: imgHeight
            ))
            yCursor += blockGrids[i].height
        }

        // Greyscale PNG. This was a binary PGM: trivial to write, but it
        // opens nowhere on Windows without extra software and is an order of
        // magnitude larger, since these sheets are mostly empty. Every other
        // image artifact the tool emits is already PNG.
        // A failed encode used to fall back to an empty `GoDData`, so the
        // dump wrote a zero-byte PNG and the failure only surfaced on the way
        // back in, as an unreadable atlas with nothing to say about why.
        guard let imageData = GreyscaleImage(width: imgWidth, height: imgHeight, pixels: pixels).pngData() else {
            throw GSFontError.atlasEncodingFailed(width: imgWidth, height: imgHeight)
        }

        let metadata = Metadata(atlasPath: atlasPath, columns: columns, blocks: metaBlocks)
        return (imageData: imageData, metadata: metadata)
    }

    /// Import a font (chain of blocks) from atlas image + metadata JSON.
    /// Preconditions the atlas should meet, checked rather than assumed.
    ///
    /// A PGM could only ever be 8-bit greyscale; a PNG can come back as RGB,
    /// 16-bit or colour-managed, and `GreyscaleImage` will quietly collapse
    /// all of it. These are the two ways that collapse loses information, so
    /// they are named explicitly instead of silently rounded away.
    private static func verify(_ image: GreyscaleImage) -> [String] {
        var out = [String]()
        if !image.wasNeutral {
            out.append(
                "Font atlas contains coloured pixels; it was converted to greyscale by "
                + "luminance. Save it as a greyscale image to keep intensities exact."
            )
        }
        // The font is 4bpp, so every pixel must be one of 16 levels
        // (nibble x 0x11). Anything else came from an editor — anti-aliasing,
        // resampling or a colour profile — and is rounded to the nearest.
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

    /// Imports the atlas, plus anything questionable about the image that the
    /// caller should surface. Warnings rather than errors: an atlas that came
    /// back from an image editor slightly off-spec should still load, with
    /// the drift reported.
    public static func importAtlas(
        imageData: GoDData,
        metadata: Metadata
    ) throws -> (font: GSFont, warnings: [String]) {
        guard let image = GreyscaleImage.fromPNG(imageData) else {
            throw GSFontError.atlasImageUnreadable
        }
        let imgWidth = image.width
        let pixels = image.pixels
        let warnings = verify(image)

        // Reconstruct each block, then chain via nextFont.
        var blocks = [GSFont]()
        for block in metadata.blocks {
            let cell = block.cell
            var glyphs = [GSFont.Glyph]()
            for info in block.glyphs {
                let baseX = info.gridCol * cell.width
                let baseY = block.gridOriginRow + info.gridRow * cell.height
                let glyphW = storedWidth(advanceWidth: info.advanceWidth)
                let glyphH = info.height
                let bpr = glyphW / 2
                var bitmap = [UInt8](repeating: 0, count: bpr * glyphH)
                for y in 0..<glyphH {
                    for x in 0..<glyphW {
                        let py = baseY + y
                        let px = baseX + x
                        let pixelIndex = py * imgWidth + px
                        let pv = pixelIndex < pixels.count ? pixels[pixelIndex] : 0
                        let nibble = min(pv / 17, 15)
                        let byteIndex = y * bpr + x / 2
                        if x % 2 == 0 { bitmap[byteIndex] |= (nibble << 4) }
                        else { bitmap[byteIndex] |= nibble }
                    }
                }
                glyphs.append(GSFont.Glyph(
                    code: UInt16(info.code),
                    advanceWidth: UInt8(info.advanceWidth),
                    height: UInt8(glyphH),
                    flags: UInt16(info.flags),
                    bitmap: bitmap
                ))
            }
            glyphs.sort { $0.code < $1.code }
            let padding = block.blockPaddingHex.flatMap(Self.decodeHex) ?? []
            blocks.append(GSFont(
                fontId: UInt16(block.fontId),
                glyphWidth: block.glyphWidth,
                glyphHeight: block.glyphHeight,
                glyphs: glyphs,
                nextFont: nil,
                blockPadding: padding,
                unknown0A: UInt16(block.unknown0A ?? 0)
            ))
        }

        // Chain from last to first
        var head: GSFont? = nil
        for b in blocks.reversed() {
            head = GSFont(
                fontId: b.fontId,
                glyphWidth: b.glyphWidth,
                glyphHeight: b.glyphHeight,
                glyphs: b.glyphs,
                nextFont: head,
                blockPadding: b.blockPadding,
                unknown0A: b.unknown0A
            )
        }
        guard let root = head else { throw GSFontError.atlasHasNoBlocks }
        return (root, warnings)
    }

    private static func decodeHex(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }
}

public enum GSFontError: Error, CustomStringConvertible {
    /// The atlas image isn't a PNG this can read.
    case atlasImageUnreadable
    /// Metadata that names no block describes no font.
    case atlasHasNoBlocks
    /// The atlas image couldn't be encoded — a size the PNG writer rejects,
    /// which is how a font with no glyphs at all used to reach the project as
    /// a zero-byte file that only failed later, on the way back in.
    case atlasEncodingFailed(width: Int, height: Int)

    public var description: String {
        switch self {
        case .atlasImageUnreadable:
            return "Error: the font atlas isn't a readable PNG."
        case .atlasHasNoBlocks:
            return "Error: the font atlas metadata names no font blocks."
        case let .atlasEncodingFailed(width, height):
            return "Error: couldn't encode a \(width)x\(height) font atlas as a PNG."
        }
    }
}

// MARK: - GSFont init from components

extension GSFont {
    public init(
        fontId: UInt16,
        glyphWidth: Int,
        glyphHeight: Int,
        glyphs: [Glyph],
        nextFont: GSFont?,
        blockPadding: [UInt8],
        unknown0A: UInt16 = 0
    ) {
        self.fontId = fontId
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
        self.nextFontBox = nextFont.map { NextFontBox($0) }
        self.blockPadding = blockPadding
        self.unknown0A = unknown0A
    }
}
