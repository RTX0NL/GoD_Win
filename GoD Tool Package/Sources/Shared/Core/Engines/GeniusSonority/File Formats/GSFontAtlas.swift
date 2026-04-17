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
        /// Path to the atlas `.pgm` image file, relative to this metadata
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

    private struct BlockGrid {
        let cols: Int
        let rows: Int
        let width: Int
        let height: Int
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

    private static func computeGrids(_ blocks: [GSFont], columns: Int) -> [BlockGrid] {
        return blocks.map { b in
            let cols = min(columns, max(b.visibleGlyphs.count, 1))
            let rows = (b.visibleGlyphs.count + cols - 1) / cols
            return BlockGrid(cols: cols, rows: rows, width: cols * b.glyphWidth, height: rows * b.glyphHeight)
        }
    }

    private static func drawGlyph(
        _ glyph: GSFont.Glyph,
        into pixels: inout [UInt8],
        baseX: Int, baseY: Int, imgWidth: Int, imgHeight: Int
    ) {
        let glyphW = Int(glyph.advanceWidth)
        let glyphH = Int(glyph.height)
        let bpr = (glyphW + 1) / 2
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
            let baseX = gridCol * block.glyphWidth
            let baseY = gridOriginRow + gridRow * block.glyphHeight
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
            blockPaddingHex: padHex
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
    ) -> (imageData: GoDData, metadata: Metadata) {
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

        // Build PGM (P5 binary format) — universally supported
        let pgmHeader = "P5\n\(imgWidth) \(imgHeight)\n255\n"
        var pgmData = [UInt8](pgmHeader.utf8)
        pgmData.append(contentsOf: pixels)
        let imageData = GoDData(byteStream: pgmData, byteOrder: .big)

        let metadata = Metadata(atlasPath: atlasPath, columns: columns, blocks: metaBlocks)
        return (imageData: imageData, metadata: metadata)
    }

    /// Import a font (chain of blocks) from atlas image + metadata JSON.
    public static func importAtlas(
        imageData: GoDData,
        metadata: Metadata
    ) throws -> GSFont {
        let imgBytes = imageData.rawBytes
        guard imgBytes.count > 10, imgBytes[0] == 0x50, imgBytes[1] == 0x35 else {
            throw GSFontError.invalidAtlas
        }
        var headerEnd = 0
        var newlineCount = 0
        for i in 0..<imgBytes.count {
            if imgBytes[i] == 0x0A {
                newlineCount += 1
                if newlineCount == 3 { headerEnd = i + 1; break }
            }
        }
        guard headerEnd > 0 else { throw GSFontError.invalidAtlas }
        let pixels = Array(imgBytes[headerEnd...])

        // Parse image width from header: "P5\n<W> <H>\n255\n"
        let headerStr = String(bytes: imgBytes[..<headerEnd], encoding: .ascii) ?? ""
        let lines = headerStr.split(separator: "\n")
        guard lines.count >= 2 else { throw GSFontError.invalidAtlas }
        let dims = lines[1].split(separator: " ")
        guard dims.count >= 1, let imgWidth = Int(dims[0]) else { throw GSFontError.invalidAtlas }

        // Reconstruct each block, then chain via nextFont.
        var blocks = [GSFont]()
        for block in metadata.blocks {
            var glyphs = [GSFont.Glyph]()
            for info in block.glyphs {
                let baseX = info.gridCol * block.glyphWidth
                let baseY = block.gridOriginRow + info.gridRow * block.glyphHeight
                let glyphW = info.advanceWidth
                let glyphH = info.height
                let bpr = (glyphW + 1) / 2
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
                    advanceWidth: UInt8(glyphW),
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
                blockPadding: padding
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
                blockPadding: b.blockPadding
            )
        }
        guard let root = head else { throw GSFontError.invalidAtlas }
        return root
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

enum GSFontError: Error {
    case invalidAtlas
}

// MARK: - GSFont init from components

extension GSFont {
    public init(
        fontId: UInt16,
        glyphWidth: Int,
        glyphHeight: Int,
        glyphs: [Glyph],
        nextFont: GSFont?,
        blockPadding: [UInt8]
    ) {
        self.fontId = fontId
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
        self.nextFontBox = nextFont.map { NextFontBox($0) }
        self.blockPadding = blockPadding
    }
}
