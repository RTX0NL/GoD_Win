import GoDFoundation

/// Export/import font glyph atlases as grayscale images with JSON metadata.
///
/// The atlas arranges all glyphs in a grid. Each cell is glyphWidth × glyphHeight pixels.
/// Exported as PGM (Portable GrayMap) — viewable in most image viewers and editable
/// in any image editor. 4bpp nibble values (0-15) are scaled to 8-bit (× 17 → 0-255).
public struct GSFontAtlas {

    /// Metadata sidecar for the atlas image
    public struct Metadata: Codable {
        public let glyphWidth: Int
        public let glyphHeight: Int
        public let columns: Int
        public let rows: Int
        public let glyphs: [GlyphInfo]

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

    /// Export a font to an atlas image (PGM) and metadata JSON.
    public static func exportAtlas(
        font: GSFont,
        columns: Int = 32
    ) -> (imageData: GoDData, metadata: Metadata) {
        let visible = font.visibleGlyphs
        let cols = min(columns, max(visible.count, 1))
        let rows = (visible.count + cols - 1) / cols

        let imgWidth = cols * font.glyphWidth
        let imgHeight = rows * font.glyphHeight

        // Build grayscale pixel buffer
        var pixels = [UInt8](repeating: 0, count: imgWidth * imgHeight)

        var glyphInfos = [Metadata.GlyphInfo]()

        for (index, glyph) in visible.enumerated() {
            let gridRow = index / cols
            let gridCol = index % cols
            let baseX = gridCol * font.glyphWidth
            let baseY = gridRow * font.glyphHeight

            // Decode 4bpp bitmap to 8-bit grayscale
            let bytesPerRow = (font.glyphWidth + 1) / 2
            for y in 0..<font.glyphHeight {
                for x in 0..<font.glyphWidth {
                    let byteIndex = y * bytesPerRow + x / 2
                    guard byteIndex < glyph.bitmap.count else { continue }
                    let byte = glyph.bitmap[byteIndex]
                    let nibble: UInt8
                    if x % 2 == 0 {
                        nibble = (byte >> 4) & 0x0F
                    } else {
                        nibble = byte & 0x0F
                    }
                    let pixelValue = nibble * 17  // 0→0, 15→255
                    let px = baseX + x
                    let py = baseY + y
                    if px < imgWidth && py < imgHeight {
                        pixels[py * imgWidth + px] = pixelValue
                    }
                }
            }

            let codeInt = Int(glyph.code)
            let charStr: String?
            if codeInt >= 0x20 && codeInt < 0xD800 {
                charStr = String(UnicodeScalar(codeInt)!)
            } else {
                charStr = nil
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

        // Build PGM (P5 binary format) — universally supported
        var pgmHeader = "P5\n\(imgWidth) \(imgHeight)\n255\n"
        var pgmData = [UInt8](pgmHeader.utf8)
        pgmData.append(contentsOf: pixels)

        let imageData = GoDData(byteStream: pgmData, byteOrder: .big)

        let metadata = Metadata(
            glyphWidth: font.glyphWidth,
            glyphHeight: font.glyphHeight,
            columns: cols,
            rows: rows,
            glyphs: glyphInfos
        )

        return (imageData: imageData, metadata: metadata)
    }

    /// Import a font from an atlas image (PGM) and metadata JSON.
    public static func importAtlas(
        imageData: GoDData,
        metadata: Metadata
    ) throws -> GSFont {
        let imgBytes = imageData.rawBytes

        // Parse PGM P5 header to find pixel data start
        guard imgBytes.count > 10 else { throw GSFontError.invalidAtlas }
        guard imgBytes[0] == 0x50 && imgBytes[1] == 0x35 else {  // "P5"
            throw GSFontError.invalidAtlas
        }

        // Skip header lines to find pixel data
        var headerEnd = 0
        var newlineCount = 0
        for i in 0..<imgBytes.count {
            if imgBytes[i] == 0x0A {  // newline
                newlineCount += 1
                if newlineCount == 3 {
                    headerEnd = i + 1
                    break
                }
            }
        }
        guard headerEnd > 0 else { throw GSFontError.invalidAtlas }

        let pixels = Array(imgBytes[headerEnd...])
        let imgWidth = metadata.columns * metadata.glyphWidth
        let bytesPerRow = (metadata.glyphWidth + 1) / 2

        // Build null glyph + visible glyphs
        var glyphs = [GSFont.Glyph]()

        // Entry 0: null sentinel
        glyphs.append(GSFont.Glyph(code: 0, advanceWidth: 0, height: 0, flags: 0, bitmap: []))

        for info in metadata.glyphs {
            let baseX = info.gridCol * metadata.glyphWidth
            let baseY = info.gridRow * metadata.glyphHeight

            // Encode 8-bit grayscale back to 4bpp
            var bitmap = [UInt8](repeating: 0, count: bytesPerRow * metadata.glyphHeight)
            for y in 0..<metadata.glyphHeight {
                for x in 0..<metadata.glyphWidth {
                    let px = baseX + x
                    let py = baseY + y
                    let pixelIndex = py * imgWidth + px
                    let pixelValue: UInt8 = pixelIndex < pixels.count ? pixels[pixelIndex] : 0
                    let nibble = min(pixelValue / 17, 15)

                    let byteIndex = y * bytesPerRow + x / 2
                    if x % 2 == 0 {
                        bitmap[byteIndex] |= (nibble << 4)
                    } else {
                        bitmap[byteIndex] |= nibble
                    }
                }
            }

            glyphs.append(GSFont.Glyph(
                code: UInt16(info.code),
                advanceWidth: UInt8(info.advanceWidth),
                height: UInt8(info.height),
                flags: UInt16(info.flags),
                bitmap: bitmap
            ))
        }

        // Sort by character code
        glyphs.sort { $0.code < $1.code }

        return GSFont(
            glyphWidth: metadata.glyphWidth,
            glyphHeight: metadata.glyphHeight,
            glyphs: glyphs
        )
    }
}

enum GSFontError: Error {
    case invalidAtlas
}

// MARK: - GSFont init from components (for import)

extension GSFont {
    public init(glyphWidth: Int, glyphHeight: Int, glyphs: [Glyph]) {
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
    }
}
