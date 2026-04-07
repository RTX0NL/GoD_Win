import GoDFoundation
import GoDEngine
import Structs

/// Parser and serializer for the GS .fnt font format.
///
/// File layout:
/// - 0x10 byte header (glyph dimensions, entry count, bitmap offset)
/// - Character table: entry_count × 8 bytes, sorted by character code
/// - Glyph bitmaps: 4bpp intensity data, ~242 bytes per 22×22 glyph
public struct GSFont: FileFormat {
    public static let formatName = "fnt"

    public struct Glyph {
        /// Unicode code point
        public let code: UInt16
        /// Horizontal advance in pixels
        public let advanceWidth: UInt8
        /// Height of this glyph in pixels
        public let height: UInt8
        /// Rendering flags
        public let flags: UInt16
        /// 4bpp intensity bitmap data (each byte = 2 pixels, upper nibble = left)
        public let bitmap: [UInt8]

        public init(code: UInt16, advanceWidth: UInt8, height: UInt8, flags: UInt16, bitmap: [UInt8]) {
            self.code = code
            self.advanceWidth = advanceWidth
            self.height = height
            self.flags = flags
            self.bitmap = bitmap
        }
    }

    /// Maximum glyph width in pixels (from header)
    public let glyphWidth: Int
    /// Maximum glyph height in pixels (from header)
    public let glyphHeight: Int
    /// Sorted array of glyphs (entry 0 is the null sentinel)
    public let glyphs: [Glyph]

    /// Bytes per glyph bitmap: ceil(glyphWidth / 2) × glyphHeight
    public var bytesPerGlyph: Int {
        ((glyphWidth + 1) / 2) * glyphHeight
    }

    // MARK: - Parse from FNT binary

    public init(data: GoDData) throws {
        data.setByteOrder(.big)
        guard data.length >= 0x10 else { throw Self.invalidFileError }

        let gw: UInt8 = data.readSafely(atAddress: 0x02)
        let gh: UInt8 = data.readSafely(atAddress: 0x03)
        let entryCount: UInt16 = data.readSafely(atAddress: 0x08)
        let bitmapOffset: UInt16 = data.readSafely(atAddress: 0x0E)

        self.glyphWidth = Int(gw)
        self.glyphHeight = Int(gh)

        let bpp = ((Int(gw) + 1) / 2) * Int(gh)
        let count = Int(entryCount)
        let bmpStart = Int(bitmapOffset)

        var parsedGlyphs = [Glyph]()
        for i in 0..<count {
            let entryOffset = 0x10 + i * 8
            guard entryOffset + 8 <= data.length else { break }

            let code: UInt16 = data.readSafely(atAddress: entryOffset)
            let advance: UInt8 = data.readSafely(atAddress: entryOffset + 2)
            let height: UInt8 = data.readSafely(atAddress: entryOffset + 3)
            let flags: UInt16 = data.readSafely(atAddress: entryOffset + 4)
            let bmpOff: UInt16 = data.readSafely(atAddress: entryOffset + 6)

            var bitmap = [UInt8]()
            if code != 0 || advance != 0 || height != 0 {
                let bmpAddr = bmpStart + Int(bmpOff)
                if bmpAddr + bpp <= data.length {
                    if let bmpData = data.read(atAddress: bmpAddr, length: bpp) {
                        bitmap = bmpData.rawBytes
                    }
                }
            }

            parsedGlyphs.append(Glyph(
                code: code,
                advanceWidth: advance,
                height: height,
                flags: flags,
                bitmap: bitmap
            ))
        }

        self.glyphs = parsedGlyphs
    }

    // MARK: - Serialize to FNT binary

    public var data: GoDData {
        get throws {
            let count = glyphs.count
            let bmpOffset = 0x10 + count * 8
            let bpp = bytesPerGlyph

            // Build bitmap data and track offsets
            var bitmapData = GoDData(byteOrder: .big)
            var bitmapOffsets = [UInt16]()

            for glyph in glyphs {
                if glyph.code == 0 && glyph.advanceWidth == 0 && glyph.height == 0 {
                    bitmapOffsets.append(0)
                } else {
                    bitmapOffsets.append(UInt16(bitmapData.length))
                    let glyphData: [UInt8]
                    if glyph.bitmap.count >= bpp {
                        glyphData = Array(glyph.bitmap.prefix(bpp))
                    } else {
                        glyphData = glyph.bitmap + [UInt8](repeating: 0, count: bpp - glyph.bitmap.count)
                    }
                    bitmapData.append(GoDData(byteStream: glyphData, byteOrder: .big))
                }
            }

            let dataSize = bitmapData.length < 0x10000 ? bitmapData.length : 0
            let result = GoDData(length: bmpOffset + bitmapData.length, byteOrder: .big)

            // Header
            result.write(UInt16(0), atAddress: 0x00)
            result.write(UInt8(glyphWidth), atAddress: 0x02)
            result.write(UInt8(glyphHeight), atAddress: 0x03)
            result.write(UInt16(0), atAddress: 0x04)
            result.write(UInt16(dataSize), atAddress: 0x06)
            result.write(UInt16(count), atAddress: 0x08)
            result.write(UInt16(0), atAddress: 0x0A)
            result.write(UInt16(0), atAddress: 0x0C)
            result.write(UInt16(bmpOffset), atAddress: 0x0E)

            // Character table
            for (i, glyph) in glyphs.enumerated() {
                let off = 0x10 + i * 8
                result.write(glyph.code, atAddress: off)
                result.write(glyph.advanceWidth, atAddress: off + 2)
                result.write(glyph.height, atAddress: off + 3)
                result.write(glyph.flags, atAddress: off + 4)
                result.write(bitmapOffsets[i], atAddress: off + 6)
            }

            // Bitmap data
            result.write(bitmapData, atAddress: bmpOffset)

            return result
        }
    }

    /// Get only the non-null glyphs (skip entry 0)
    public var visibleGlyphs: [Glyph] {
        glyphs.filter { $0.code != 0 || $0.advanceWidth != 0 || $0.height != 0 }
    }
}
