import GoDFoundation
import GoDEngine
import Structs

/// Parser and serializer for the GS `.fnt` font format.
///
/// A `.fnt` file is a linked list of **font blocks** (each a different glyph
/// size, e.g. 22×22 primary + 18×18 secondary). The runtime walks the list via
/// `GSmsgFontOpen` (see `scripts/Disassembly-XD/text1/GSmsg/GSmsgFontOpen.s`).
///
/// Per-block layout:
///
/// ```
/// +0x00  u16  fontId              (0, 1, 2…; 0xFFFF terminates list)
/// +0x02  u8   glyphWidth
/// +0x03  u8   glyphHeight
/// +0x04  u32  nextBlockOffset     (relative to THIS block's start;
///                                  0 = last block. Matches the asm:
///                                  `r31 += r0` in GSmsgFontOpen)
/// +0x08  u16  count               (searchable char-table entries)
/// +0x0A  u16  unknown0A          (0 in most fonts, 1 in every block of
///                                  the kana+Latin fonts; meaning unknown)
/// +0x0C  u16  reserved (0)
/// +0x0E  u16  lastEntryOffset     (offset of the FINAL char-table entry,
///                                  = bmpStart in our earlier parlance)
/// +0x10  8 B  chain-ptr slot      (runtime writes next/prev links here at
///                                  load time via `stw r0, 0x8(r4)` in
///                                  GSmsgFontOpen; all-zero on disk)
/// +0x18  count × 8  char table    (code u16, adv u8, h u8, flags u16, bmpOff u16;
///                                  sorted by code for binary search)
/// +lastEntryOffset+8   bitmap data (per-entry `bmpOff` relative to here;
///                                  each glyph uses ⌈adv/2⌉ × h bytes, 4bpp)
/// ```
///
/// `_msgGetCodeInfo` binary-searches `count` entries starting at `r6+0x10`
/// (where `r6 = file+0x08`), i.e. from `file+0x18`. The "null entry" at
/// `file+0x10` is **not** part of the table — it's the 8 bytes the runtime
/// writes `next`/`prev` linked-list pointers into. On disk those 8 bytes are
/// always zero.
///
/// Bitmaps are read as 4bpp scanline data with upper nibble = left pixel. No
/// rotation, mirror, or row transform — verified against `_msgMakeTexture`.
public struct GSFont {
    public static let formatName = "fnt"

    /// Base filename used by FileFormat outputs/init(outputs:). Default
    /// `fnt` produces `fnt.fnt.json`/`fnt.fnt.pgm`; set to e.g. "pda_menu"
    /// to produce `pda_menu.fnt.json`/`pda_menu.fnt.pgm`.
    public var name: String = "fnt"

    public struct Glyph {
        /// Character code (Unicode / Shift-JIS depending on font)
        public let code: UInt16
        /// Horizontal advance in pixels
        public let advanceWidth: UInt8
        /// Height of this glyph in pixels
        public let height: UInt8
        /// Rendering flags (high byte varies; runtime usage unidentified)
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

    /// Sequential block ID in the file-level font chain (0 for the first
    /// block, 1 for the second, etc.). Written to the runtime font manager
    /// so callers can select a specific size.
    public let fontId: UInt16
    /// Font-wide glyph width (max), in pixels.
    public let glyphWidth: Int
    /// Font-wide glyph height (max), in pixels.
    public let glyphHeight: Int
    /// Glyphs in the char table, sorted by `code`. Each is independently
    /// searchable via binary search at runtime.
    public let glyphs: [Glyph]
    /// Next font block in the chain (smaller-size variant, usually 18×18 when
    /// this block is 22×22). `nil` means this is the last block. Boxed in a
    /// class to break infinite-size recursion of the struct.
    internal let nextFontBox: NextFontBox?
    public var nextFont: GSFont? { nextFontBox?.font }

    public final class NextFontBox {
        public let font: GSFont
        public init(_ font: GSFont) { self.font = font }
    }
    /// Byte padding between this block's last glyph bitmap and the start of
    /// the next block (or end of file). Typically a handful of zero bytes for
    /// alignment; preserved verbatim for byte-identical round-trip.
    public let blockPadding: [UInt8]
    /// Header word `+0x0A`. Long documented as reserved-zero, but every block
    /// of the kana+Latin fonts (in `main.dol`, and Colosseum's large
    /// `common.rel` font) carries 1. Nothing found reads it; it is carried so
    /// a rebuilt font keeps it.
    public let unknown0A: UInt16

    /// Bytes per glyph bitmap for the font's max dimensions.
    public var bytesPerGlyph: Int {
        ((glyphWidth + 1) / 2) * glyphHeight
    }

    /// Visible glyphs — alias for `glyphs` (there is no null sentinel; every
    /// entry in the table is a real glyph).
    public var visibleGlyphs: [Glyph] { glyphs }

    // MARK: - Parse

    public init(data: GoDData) throws {
        try self.init(data: data, blockOffset: 0)
    }

    private init(data: GoDData, blockOffset: Int) throws {
        data.setByteOrder(.big)
        guard blockOffset + 0x18 <= data.length else { throw FileFormatErrors.invalid(format: Self.formatName) }

        let fontId: UInt16 = data.readSafely(atAddress: blockOffset + 0x00)
        let gw: UInt8 = data.readSafely(atAddress: blockOffset + 0x02)
        let gh: UInt8 = data.readSafely(atAddress: blockOffset + 0x03)
        let nextOffset: UInt32 = data.readSafely(atAddress: blockOffset + 0x04)
        let count: UInt16 = data.readSafely(atAddress: blockOffset + 0x08)
        let unknown0A: UInt16 = data.readSafely(atAddress: blockOffset + 0x0A)
        let lastEntryOff: UInt16 = data.readSafely(atAddress: blockOffset + 0x0E)

        self.fontId = fontId
        self.glyphWidth = Int(gw)
        self.glyphHeight = Int(gh)
        self.unknown0A = unknown0A

        let entryCount = Int(count)
        let lastEntryOffset = Int(lastEntryOff)

        // Sanity: `lastEntryOffset` must equal the offset of the final char-
        // table entry, i.e. `0x18 + (count-1)*8` relative to block start.
        // Verified against all 26 XD font samples.
        let expectedLastEntry = 0x18 + (entryCount - 1) * 8
        guard entryCount == 0 || lastEntryOffset == expectedLastEntry else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }

        // The 8 bytes at blockOffset+0x10 are chain-ptr storage; always zero
        // on disk. Not read as a char-table entry. Real entries start at +0x18.
        let charTableBase = blockOffset + 0x18
        let bitmapBase = blockOffset + lastEntryOffset + 8  // = charTableBase + count*8

        // Walk char-table entries. `bmpOff` is a UInt16 that wraps every
        // 0x10000 bytes for large fonts (e.g. Font_Data_24 at ~706 KB of
        // bitmap data). Entries are code-sorted but bitmap data is laid out
        // in the same order as entries, so bmpOff is monotonic except on wrap.
        var parsed = [Glyph]()
        parsed.reserveCapacity(entryCount)
        var bank = 0
        var prevBmpOff: UInt16 = 0
        var firstSeen = false
        var maxBitmapEnd = 0

        for i in 0..<entryCount {
            let entryAddr = charTableBase + i * 8
            let code: UInt16 = data.readSafely(atAddress: entryAddr + 0)
            let advance: UInt8 = data.readSafely(atAddress: entryAddr + 2)
            let height: UInt8 = data.readSafely(atAddress: entryAddr + 3)
            let flags: UInt16 = data.readSafely(atAddress: entryAddr + 4)
            let bmpOff: UInt16 = data.readSafely(atAddress: entryAddr + 6)

            if firstSeen && bmpOff < prevBmpOff {
                bank += 1
            }
            let absOff = Int(bmpOff) + bank * 0x10000
            let bpr = (Int(advance) + 1) / 2
            let glyphBytes = bpr * Int(height)
            let bmpAddr = bitmapBase + absOff

            var bitmap = [UInt8]()
            if glyphBytes > 0, bmpAddr + glyphBytes <= data.length,
               let b = data.read(atAddress: bmpAddr, length: glyphBytes) {
                bitmap = b.rawBytes
            }
            maxBitmapEnd = max(maxBitmapEnd, absOff + glyphBytes)
            prevBmpOff = bmpOff
            firstSeen = true

            parsed.append(Glyph(
                code: code,
                advanceWidth: advance,
                height: height,
                flags: flags,
                bitmap: bitmap
            ))
        }
        self.glyphs = parsed

        // `nextOffset` is relative to this block's start (matches the asm:
        // `r31 += r0` in GSmsgFontOpen). For the primary block at file+0,
        // relative == absolute, but nested blocks need base-offset.
        let nextBlockAbsolute = nextOffset == 0 ? 0 : blockOffset + Int(nextOffset)

        // This block ends at the next block's start (or end-of-file for the
        // last block). Preserve any alignment padding between its last glyph
        // and that boundary for byte-identical round-trip.
        let blockEnd = (nextOffset == 0) ? data.length : nextBlockAbsolute
        let paddingStart = bitmapBase + maxBitmapEnd
        if paddingStart < blockEnd, paddingStart < data.length,
           let pad = data.read(atAddress: paddingStart, length: min(blockEnd, data.length) - paddingStart) {
            self.blockPadding = pad.rawBytes
        } else {
            self.blockPadding = []
        }

        if nextOffset != 0, nextBlockAbsolute < data.length {
            let next = try GSFont(data: data, blockOffset: nextBlockAbsolute)
            self.nextFontBox = NextFontBox(next)
        } else {
            self.nextFontBox = nil
        }
    }

    // MARK: - Serialize

    public var data: GoDData {
        get throws {
            let result = GoDData(byteOrder: .big)
            try appendBlock(to: result, parentBlockStart: nil)
            return result
        }
    }

    /// Append this block's bytes to `out`. If `parent` is given, patches the
    /// parent block's `nextBlockOffset` (at parentBlockStart+0x04) to
    /// `blockStart - parentBlockStart` (relative offset, as the runtime
    /// expects for `r31 += r0`).
    private func appendBlock(to out: GoDData, parentBlockStart: Int?) throws {
        let blockStart = out.length
        if let parentStart = parentBlockStart {
            let relative = UInt32(blockStart - parentStart)
            out.write(relative, atAddress: parentStart + 0x04)
        }

        let count = glyphs.count
        let lastEntryOffset = 0x18 + (count - 1) * 8  // = offset of final entry
        let bitmapBaseOffset = lastEntryOffset + 8    // = 0x18 + count*8

        // Block header + reserved + chain-ptr slot = 0x18 bytes
        let headerAndChainSlot = GoDData(length: 0x18, byteOrder: .big)
        headerAndChainSlot.write(fontId, atAddress: 0x00)
        headerAndChainSlot.write(UInt8(glyphWidth), atAddress: 0x02)
        headerAndChainSlot.write(UInt8(glyphHeight), atAddress: 0x03)
        headerAndChainSlot.write(UInt32(0), atAddress: 0x04) // nextOffset — patched later if needed
        headerAndChainSlot.write(UInt16(count), atAddress: 0x08)
        headerAndChainSlot.write(unknown0A, atAddress: 0x0A)
        headerAndChainSlot.write(UInt16(0), atAddress: 0x0C)
        headerAndChainSlot.write(UInt16(count == 0 ? 0 : lastEntryOffset), atAddress: 0x0E)
        // 0x10..0x17: chain-ptr slot, remains zero
        out.append(headerAndChainSlot)

        // Char table + bitmap data (both built together so `bmpOff` values are
        // known as we emit entries).
        let bitmapData = GoDData(byteOrder: .big)
        var entryRecords = [(UInt16, UInt8, UInt8, UInt16, UInt16)]()  // code,adv,h,flags,bmpOff

        for glyph in glyphs {
            let absOff = bitmapData.length
            let bmpOff = UInt16(truncatingIfNeeded: absOff)
            let glyphBpp = ((Int(glyph.advanceWidth) + 1) / 2) * Int(glyph.height)
            let glyphData: [UInt8]
            if glyph.bitmap.count >= glyphBpp {
                glyphData = Array(glyph.bitmap.prefix(glyphBpp))
            } else {
                glyphData = glyph.bitmap + [UInt8](repeating: 0, count: glyphBpp - glyph.bitmap.count)
            }
            bitmapData.append(GoDData(byteStream: glyphData, byteOrder: .big))
            entryRecords.append((glyph.code, glyph.advanceWidth, glyph.height, glyph.flags, bmpOff))
        }

        // Emit char table after the chain-ptr slot
        let charTable = GoDData(length: count * 8, byteOrder: .big)
        for (i, rec) in entryRecords.enumerated() {
            let off = i * 8
            charTable.write(rec.0, atAddress: off + 0)
            charTable.write(rec.1, atAddress: off + 2)
            charTable.write(rec.2, atAddress: off + 3)
            charTable.write(rec.3, atAddress: off + 4)
            charTable.write(rec.4, atAddress: off + 6)
        }
        out.append(charTable)

        _ = bitmapBaseOffset  // for symmetry; bitmap base addr in out is blockStart + 0x18 + count*8
        out.append(bitmapData)

        if !blockPadding.isEmpty {
            out.append(GoDData(byteStream: blockPadding, byteOrder: .big))
        }

        if let next = nextFont {
            try next.appendBlock(to: out, parentBlockStart: blockStart)
        }
    }
}
