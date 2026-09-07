//
//  PBRFont.swift
//  PBR
//
//  Parser and serializer for Battle Revolution's `.FNT` font container.
//
//  This is *not* the Genius Sonority `.fnt` that Colosseum and XD use, despite
//  the shared extension and a family resemblance in the pixel format — the
//  container, the magic, the record stride and the offset width all differ,
//  and `GSFont` rejects a PBR font outright. The two live side by side rather
//  than one extending the other.
//
//  Layout (big-endian), recovered from the PAL and JP corpora:
//
//  ```
//  +0x00  u32 × N   block offset table. N isn't stored: the first entry
//                   points at the first block, so N = firstOffset / 4.
//  ```
//
//  Each block:
//
//  ```
//  +0x00  char[4]  'FONT'
//  +0x04  u16      glyph count
//  +0x06  u8       language code, an ASCII letter ('U','S','G','F','I','J')
//  +0x07  u8       nominal glyph size (32 or 24)
//  +0x08  count × 10  glyph records, sorted ascending by character code:
//           +0x00  u16  character code (Unicode)
//           +0x02  u8   width, in pixels
//           +0x03  u8   first occupied row within the line box
//           +0x04  u8   last occupied row (inclusive)
//           +0x05  u8   line height
//           +0x06  u32  bitmap offset, relative to the block's start
//         bitmap data, 4bpp intensity, upper nibble = left pixel
//  ```
//
//  A glyph's bitmap is `ceil(width / 2) × (lastRow - firstRow + 1)` bytes.
//  **The height is not stored** — it falls out of the two row bounds, which
//  is the one non-obvious thing about the format. Bitmaps are laid out
//  contiguously in offset order starting immediately after the record table,
//  and the block is padded to a 4-byte boundary.
//
//  Measured across every font in both corpora (22 files, 20,898 glyphs): every
//  glyph's bitmap tiles exactly at `stride × height` with no gaps, and the only
//  slack anywhere is that trailing 1–3 byte block alignment.
//

import Foundation
import GoDFoundation

public struct PBRFont: Equatable {
    public static let formatName = "fnt"

    /// Base name used for artifact filenames.
    public var name: String = "fnt"

    public struct Glyph: Equatable {
        /// Character code (Unicode).
        public let code: UInt16
        /// Bitmap width in pixels. The row stride is `ceil(width / 2)`.
        public let width: Int
        /// First occupied row within the line box.
        public let firstRow: Int
        /// Last occupied row, inclusive. `height` derives from the pair.
        public let lastRow: Int
        /// Line height this glyph was authored against. Constant within a
        /// block in every font measured, but stored per glyph on disk, so
        /// it's kept per glyph rather than hoisted and re-derived.
        public let lineHeight: Int
        /// 4bpp intensity rows, `stride × height` bytes.
        public let bitmap: [UInt8]

        public var height: Int { lastRow - firstRow + 1 }
        public var stride: Int { (width + 1) / 2 }

        public init(
            code: UInt16, width: Int, firstRow: Int, lastRow: Int,
            lineHeight: Int, bitmap: [UInt8]
        ) {
            self.code = code
            self.width = width
            self.firstRow = firstRow
            self.lastRow = lastRow
            self.lineHeight = lineHeight
            self.bitmap = bitmap
        }
    }

    public struct Block: Equatable {
        /// ASCII letter identifying the language this block serves.
        public let language: Character
        /// Nominal glyph size the block was authored at (32 or 24).
        public let nominalSize: Int
        /// Glyphs, in the file's order (ascending by code — the runtime
        /// binary-searches them, so the order is load-bearing).
        public let glyphs: [Glyph]

        public init(language: Character, nominalSize: Int, glyphs: [Glyph]) {
            self.language = language
            self.nominalSize = nominalSize
            self.glyphs = glyphs
        }
    }

    /// Blocks in offset-table order. A file carries one per language/size
    /// combination — ten in most fonts, six in `Fnt_reference_JP`.
    public let blocks: [Block]

    public init(blocks: [Block], name: String = "fnt") {
        self.blocks = blocks
        self.name = name
    }

    public enum Error: GoDError {
        case notAFontContainer(ErrorTrace = .init())
        case truncated(block: Int, ErrorTrace = .init())
        case glyphOutOfBounds(block: Int, code: UInt16, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .notAFontContainer(trace):
                return "Error: not a PBR font container (no 'FONT' block at the first table offset).\n\(trace)"
            case let .truncated(block, trace):
                return "Error: PBR font block \(block) runs past the end of the file.\n\(trace)"
            case let .glyphOutOfBounds(block, code, trace):
                return "Error: PBR font block \(block): glyph U+\(String(format: "%04X", code)) "
                    + "declares a bitmap outside its block.\n\(trace)"
            }
        }
    }

    // MARK: - Parse

    public init(data: GoDData, name: String = "fnt") throws {
        data.setByteOrder(.big)
        self.name = name

        // The table length is implied by its first entry: everything before
        // the first block is the table.
        guard data.length >= 8 else { throw Error.notAFontContainer() }
        let firstOffset = Int(data.readSafely(atAddress: 0) as UInt32)
        guard firstOffset >= 4, firstOffset % 4 == 0, firstOffset < data.length else {
            throw Error.notAFontContainer()
        }
        let blockCount = firstOffset / 4
        let offsets = (0 ..< blockCount).map {
            Int(data.readSafely(atAddress: $0 * 4) as UInt32)
        }
        guard let magic = data.read(atAddress: offsets[0], length: 4),
              magic.rawBytes == Array("FONT".utf8) else {
            throw Error.notAFontContainer()
        }

        // A block ends where the next begins; the last runs to EOF. The tail
        // of each is 0–3 bytes of alignment padding, which the writer
        // re-derives rather than storing.
        var parsed = [Block]()
        for (index, start) in offsets.enumerated() {
            let end = index + 1 < offsets.count ? offsets[index + 1] : data.length
            guard start + 8 <= end, end <= data.length else {
                throw Error.truncated(block: index)
            }
            let count = Int(data.readSafely(atAddress: start + 4) as UInt16)
            let language = Character(UnicodeScalar(data.readSafely(atAddress: start + 6) as UInt8))
            let nominalSize = Int(data.readSafely(atAddress: start + 7) as UInt8)

            var glyphs = [Glyph]()
            glyphs.reserveCapacity(count)
            for i in 0 ..< count {
                let record = start + 8 + i * 10
                guard record + 10 <= end else { throw Error.truncated(block: index) }
                let code: UInt16 = data.readSafely(atAddress: record)
                let width = Int(data.readSafely(atAddress: record + 2) as UInt8)
                let firstRow = Int(data.readSafely(atAddress: record + 3) as UInt8)
                let lastRow = Int(data.readSafely(atAddress: record + 4) as UInt8)
                let lineHeight = Int(data.readSafely(atAddress: record + 5) as UInt8)
                let bitmapOffset = Int(data.readSafely(atAddress: record + 6) as UInt32)

                let stride = (width + 1) / 2
                let height = lastRow - firstRow + 1
                let size = height > 0 ? stride * height : 0
                guard size >= 0, start + bitmapOffset + size <= end else {
                    throw Error.glyphOutOfBounds(block: index, code: code)
                }
                let bitmap = size == 0
                    ? []
                    : (data.read(atAddress: start + bitmapOffset, length: size)?.rawBytes ?? [])
                glyphs.append(Glyph(
                    code: code, width: width, firstRow: firstRow, lastRow: lastRow,
                    lineHeight: lineHeight, bitmap: bitmap
                ))
            }
            parsed.append(Block(language: language, nominalSize: nominalSize, glyphs: glyphs))
        }
        self.blocks = parsed
    }

    // MARK: - Serialize

    public var data: GoDData {
        var bytes = [UInt8]()

        func appendU16(_ value: Int, to array: inout [UInt8]) {
            array.append(UInt8((value >> 8) & 0xFF))
            array.append(UInt8(value & 0xFF))
        }
        func appendU32(_ value: Int, to array: inout [UInt8]) {
            array.append(UInt8((value >> 24) & 0xFF))
            array.append(UInt8((value >> 16) & 0xFF))
            array.append(UInt8((value >> 8) & 0xFF))
            array.append(UInt8(value & 0xFF))
        }

        // Each block is built standalone first, so the offset table can be
        // written from the real sizes rather than predicted.
        var blockBodies = [[UInt8]]()
        for block in blocks {
            var body = [UInt8]()
            body.append(contentsOf: Array("FONT".utf8))
            appendU16(block.glyphs.count, to: &body)
            body.append(block.language.asciiValue ?? 0)
            body.append(UInt8(block.nominalSize))

            // Bitmaps follow the record table contiguously, in glyph order.
            var bitmapOffset = 8 + block.glyphs.count * 10
            var bitmapRegion = [UInt8]()
            for glyph in block.glyphs {
                appendU16(Int(glyph.code), to: &body)
                body.append(UInt8(glyph.width))
                body.append(UInt8(glyph.firstRow))
                body.append(UInt8(glyph.lastRow))
                body.append(UInt8(glyph.lineHeight))
                appendU32(bitmapOffset, to: &body)
                bitmapRegion.append(contentsOf: glyph.bitmap)
                bitmapOffset += glyph.bitmap.count
            }
            body.append(contentsOf: bitmapRegion)
            // Blocks start on a 4-byte boundary.
            while body.count % 4 != 0 { body.append(0) }
            blockBodies.append(body)
        }

        var offset = blockBodies.count * 4
        for body in blockBodies {
            appendU32(offset, to: &bytes)
            offset += body.count
        }
        for body in blockBodies { bytes.append(contentsOf: body) }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }
}
