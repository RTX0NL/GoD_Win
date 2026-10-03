import GoDFoundation

/// Metadata for a GX texture, stored in the FSYS registry for re-encoding on import
public struct GXTextureMetadata: Codable, Equatable {
    public let width: Int
    public let height: Int
    public let format: GXTextureFormat
    public let paletteFormat: GXPaletteFormat?

    public init(width: Int, height: Int, format: GXTextureFormat, paletteFormat: GXPaletteFormat? = nil) {
        self.width = width
        self.height = height
        self.format = format
        self.paletteFormat = paletteFormat
    }
}

/// One frame in an ATX animation's keyframe stream.
///
/// Each frame is a variable-length record: a flags byte followed by 0–4 optional fields.
/// The presence of each optional field is signaled by a bit in the flags byte
/// (see ATXMetadata documentation for the bit layout).
public struct ATXFrame: Codable, Equatable {
    /// bit 30 (0x02) — wait duration for this frame (engine scales by ~×0.45)
    public var timing: UInt8?
    /// bit 29 (0x04) — width index into the frameTable's sprite-rect records
    public var rectWidth: UInt8?
    /// bit 29 (0x04) — height index, paired with rectWidth
    public var rectHeight: UInt8?
    /// bit 31 (0x01) — increment added to the running sprite-frame counter
    public var frameDelta: UInt8?
    /// bit 28 (0x08) — when present, this frame ends the animation by looping
    /// the cursor back to this byte position (relative to the animation's start
    /// offset). Typically 0 to restart the stream from the beginning.
    public var loopTarget: Int?

    public init(
        timing: UInt8? = nil,
        rectWidth: UInt8? = nil,
        rectHeight: UInt8? = nil,
        frameDelta: UInt8? = nil,
        loopTarget: Int? = nil
    ) {
        self.timing = timing
        self.rectWidth = rectWidth
        self.rectHeight = rectHeight
        self.frameDelta = frameDelta
        self.loopTarget = loopTarget
    }

    /// Bytes occupied by this frame in the keyframe stream.
    public var byteLength: Int {
        1                                  // flags
            + (timing != nil ? 1 : 0)
            + (rectWidth != nil ? 2 : 0)
            + (frameDelta != nil ? 1 : 0)
            + (loopTarget != nil ? 1 : 0)
    }
}

/// One animation in an ATX file: an absolute file offset and a sequence of frames.
public struct ATXAnimation: Codable, Equatable {
    /// Absolute byte offset within the ATX file where this animation's keyframe
    /// stream begins. Preserved exactly so non-contiguous animation layouts round-trip.
    public var offset: Int
    public var frames: [ATXFrame]

    public init(offset: Int, frames: [ATXFrame]) {
        self.offset = offset
        self.frames = frames
    }
}

/// Metadata for an ATX file (animated texture used by Pokemon XD's poke_dance).
///
/// File layout (reverse-engineered from `ant.o` — see CAnt::setAnimation,
/// CAnt::drawAndUpdate, antGetGStexture):
///
///     [0x00..0x0F] 16-byte header (4 big-endian u32 fields below)
///         0x00  animationCount     — number of animations in this file
///         0x04  frameTableOffset   — absolute offset to the sprite-rect lookup table
///         0x08  innerTextureSize   — total byte length of the inner texture (header + data + palette)
///         0x0C  innerTextureOffset — absolute offset to the inner GTX-format texture header
///     [0x10..]                       animationOffsets: u16[animationCount] big-endian
///                                       Each value is the absolute byte offset where that
///                                       animation's keyframe stream begins.
///     [end of table .. frameTableOffset]
///                                    Keyframe streams. Each frame is a variable-length record
///                                    led by a flags byte; bits select which fields follow:
///                                      bit 30 (0x02) → timing u8
///                                      bit 29 (0x04) → rectWidth u8 + rectHeight u8
///                                      bit 31 (0x01) → frameDelta u8
///                                      bit 28 (0x08) → jump u8 (engine: cursor = cursor − jump,
///                                                                loops the animation)
///     [frameTableOffset .. innerTextureOffset]
///                                    frameTable: pairs of (count u16, relativeOffset u16) followed
///                                       by 28-byte sprite-rect records. Preserved verbatim — its
///                                       structure isn't unpacked here.
///     [innerTextureOffset .. +innerTextureSize]
///                                    inner GTX texture (parsed via `texture`)
///     [.. EOF]                       trailing bytes (typically empty for poke_dance ATX files)
public struct ATXMetadata: Codable, Equatable {
    /// Inner texture properties (dimensions, format, palette format)
    public let texture: GXTextureMetadata
    /// Header field 0x04 — absolute offset to the sprite-rect lookup table
    public let frameTableOffset: Int
    /// Header field 0x08 — total byte length of the inner texture (header + data + palette)
    public let innerTextureSize: Int
    /// Header field 0x0C — absolute offset to the inner GTX texture header
    public let innerTextureOffset: Int
    /// Animations in this file. Length equals the wrapper's animationCount field;
    /// each animation carries its absolute offset and decoded frame records.
    public let animations: [ATXAnimation]
    /// Raw frame/sprite-rect lookup table bytes (between frameTableOffset and innerTextureOffset)
    public let frameTable: Data
    /// Raw bytes after the inner texture+palette (typically empty)
    public let trailing: Data

    public init(
        texture: GXTextureMetadata,
        frameTableOffset: Int,
        innerTextureSize: Int,
        innerTextureOffset: Int,
        animations: [ATXAnimation],
        frameTable: Data,
        trailing: Data = Data()
    ) {
        self.texture = texture
        self.frameTableOffset = frameTableOffset
        self.innerTextureSize = innerTextureSize
        self.innerTextureOffset = innerTextureOffset
        self.animations = animations
        self.frameTable = frameTable
        self.trailing = trailing
    }

    /// Convenience accessor — animationCount is implicitly `animations.count` and
    /// is what gets written to the header field 0x00 on encode.
    public var animationCount: Int { animations.count }
}

/// GS palette format IDs. Case names map 1:1 to the byte at GTX header
/// offset 0x0F. `RGB5A3_3` is an undocumented Genius Sonority variant that
/// decodes as ordinary RGB5A3 — only the raw header byte differs (3 vs 2),
/// preserved here for byte-identical roundtrip.
public enum GXPaletteFormat: Int, Codable, CaseIterable {
    case IA8 = 0, RGB565 = 1, RGB5A3 = 2, RGB5A3_3 = 3

    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let m = Self.allCases.first(where: { "\($0)" == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown palette format: \(name)"))
        }
        self = m
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("\(self)")
    }
}

/// GS texture format IDs. Case names map 1:1 to the byte at GTX header
/// offset 0x0B.
public enum GXTextureFormat: Int, CaseIterable, Codable, Equatable {
    case C4 = 0x00, C8 = 0x01, C14X2 = 0x30
    case I4 = 0x40, IA4 = 0x41, I8 = 0x42, IA8 = 0x43
    case RGB565 = 0x44, RGBA32 = 0x45, RGB5A3 = 0x90, CMPR = 0xB0

    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let m = Self.allCases.first(where: { "\($0)" == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown texture format: \(name)"))
        }
        self = m
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("\(self)")
    }

    public var blockWidth: Int {
        switch self {
        case .I4, .C4, .CMPR: return 8
        case .IA4, .I8, .C8: return 8
        case .IA8, .RGB565, .RGB5A3, .RGBA32, .C14X2: return 4
        }
    }

    public var blockHeight: Int {
        switch self {
        case .I4, .C4, .CMPR: return 8
        case .IA4, .I8, .C8: return 4
        case .IA8, .RGB565, .RGB5A3, .RGBA32, .C14X2: return 4
        }
    }

    public var bitsPerPixel: Int {
        switch self {
        case .I4, .C4, .CMPR: return 4
        case .IA4, .I8, .C8: return 8
        case .IA8, .RGB565, .RGB5A3, .C14X2: return 16
        case .RGBA32: return 32
        }
    }

    public var isIndexed: Bool {
        switch self { case .C4, .C8, .C14X2: return true; default: return false }
    }

    public var paletteEntryCount: Int {
        switch self { case .C4: return 16; case .C8: return 256; case .C14X2: return 16384; default: return 0 }
    }
}

// MARK: - Decoder (mirrors legacy GoD tool approach)

public struct GXTextureDecoder {

    public init() {}

    public func parseHeader(data: GoDData, headerOffset: Int = 0) -> GXTextureMetadata? {
        guard data.length >= headerOffset + 0x50 else { return nil }
        data.setByteOrder(.big)
        let width: UInt16 = data.readSafely(atAddress: headerOffset)
        let height: UInt16 = data.readSafely(atAddress: headerOffset + 0x02)
        let fmtID: UInt8 = data.readSafely(atAddress: headerOffset + 0x0B)
        let palID: UInt8 = data.readSafely(atAddress: headerOffset + 0x0F)
        guard let fmt = GXTextureFormat(rawValue: Int(fmtID)) else { return nil }
        return GXTextureMetadata(width: Int(width), height: Int(height), format: fmt,
                                 paletteFormat: fmt.isIndexed ? GXPaletteFormat(rawValue: Int(palID)) : nil)
    }

    // MARK: - ATX support
    //
    // See ATXMetadata for the full file layout. The 16-byte header at offset 0
    // gives us animationCount (0x00), frameTableOffset (0x04), innerTextureSize (0x08),
    // and innerTextureOffset (0x0C). The animation offset table starts at 0x10 and
    // contains animationCount big-endian u16 entries.

    /// Keyframe stream flag bits (using PowerPC bit numbering: bit 31 = LSB)
    private static let atxFlagFrameDelta: UInt8 = 0x01  // bit 31
    private static let atxFlagTiming: UInt8     = 0x02  // bit 30
    private static let atxFlagRect: UInt8       = 0x04  // bit 29
    private static let atxFlagJump: UInt8       = 0x08  // bit 28

    /// Parses one animation's keyframe stream starting at `streamOffset`.
    /// Returns nil if the stream goes out of bounds before we hit a jump terminator.
    private func parseAnimationFrames(
        bytes: [UInt8],
        streamOffset: Int,
        bound: Int
    ) -> [ATXFrame]? {
        var frames = [ATXFrame]()
        var cursor = 0
        while streamOffset + cursor < bound {
            let flags = bytes[streamOffset + cursor]
            cursor += 1
            var frame = ATXFrame()

            if flags & Self.atxFlagTiming != 0 {
                guard streamOffset + cursor < bound else { return nil }
                frame.timing = bytes[streamOffset + cursor]; cursor += 1
            }
            if flags & Self.atxFlagRect != 0 {
                guard streamOffset + cursor + 1 < bound else { return nil }
                frame.rectWidth = bytes[streamOffset + cursor]; cursor += 1
                frame.rectHeight = bytes[streamOffset + cursor]; cursor += 1
            }
            if flags & Self.atxFlagFrameDelta != 0 {
                guard streamOffset + cursor < bound else { return nil }
                frame.frameDelta = bytes[streamOffset + cursor]; cursor += 1
            }
            if flags & Self.atxFlagJump != 0 {
                guard streamOffset + cursor < bound else { return nil }
                let jumpByte = bytes[streamOffset + cursor]
                // Engine: cursor = cursor − jumpByte (cursor at the jump byte's position).
                // Loop target = jumpBytePos − jumpByte, where jumpBytePos == cursor.
                frame.loopTarget = cursor - Int(jumpByte)
                cursor += 1
                frames.append(frame)
                return frames
            }
            frames.append(frame)
        }
        // Reached bound without a jump terminator — that's unusual for real files but
        // return what we have rather than failing outright.
        return frames
    }

    /// Decodes an ATX file: parses the wrapper into structured fields, decodes the
    /// inner texture to an image, and returns metadata sufficient for 1:1 rebuild.
    public func decodeATX(data: GoDData) -> (image: GoDImage, metadata: ATXMetadata)? {
        guard data.length >= 0x10 else { return nil }
        data.setByteOrder(.big)

        let animationCount: UInt32 = data.readSafely(atAddress: 0x00)
        let frameTableOffset: UInt32 = data.readSafely(atAddress: 0x04)
        let innerTextureSize: UInt32 = data.readSafely(atAddress: 0x08)
        let innerTextureOffset: UInt32 = data.readSafely(atAddress: 0x0C)

        let startOffset = Int(innerTextureOffset)
        let animCount = Int(animationCount)
        let frameTblOff = Int(frameTableOffset)
        let innerSize = Int(innerTextureSize)

        // Sanity checks — bail out if the header doesn't look like a wrapped ATX.
        let offsetTableEnd = 0x10 + animCount * 2
        guard startOffset > 0,
              startOffset <= data.length,
              frameTblOff >= offsetTableEnd,
              frameTblOff <= startOffset,
              animCount > 0,
              animCount < 256
        else { return nil }

        guard let meta = parseHeader(data: data, headerOffset: startOffset) else { return nil }
        guard let image = decode(data: data, headerOffset: startOffset) else { return nil }

        // Read the animation offset table (animationCount big-endian u16s)
        var offsets = [Int]()
        offsets.reserveCapacity(animCount)
        for i in 0..<animCount {
            let v: UInt16 = data.readSafely(atAddress: 0x10 + i * 2)
            offsets.append(Int(v))
        }

        let raw = data.rawBytes

        // Parse each animation's keyframe stream. The bound for each stream is
        // either the next animation's start (if any sit after it) or frameTableOffset.
        var animations = [ATXAnimation]()
        animations.reserveCapacity(animCount)
        for (i, animOffset) in offsets.enumerated() {
            // Conservative bound: stop at the lowest start-after-this-one across all
            // animations, falling back to frameTableOffset if there is none.
            let later = offsets.enumerated().compactMap { (j, o) -> Int? in
                (j != i && o > animOffset) ? o : nil
            }
            let bound = min(later.min() ?? frameTblOff, frameTblOff)
            guard let frames = parseAnimationFrames(bytes: raw, streamOffset: animOffset, bound: bound) else {
                return nil
            }
            animations.append(ATXAnimation(offset: animOffset, frames: frames))
        }

        let frameTableBytes = frameTblOff < startOffset
            ? Array(raw[frameTblOff..<startOffset])
            : []

        let textureEnd = startOffset + innerSize
        let trailingBytes = textureEnd < raw.count
            ? Array(raw[textureEnd..<raw.count])
            : []

        let metadata = ATXMetadata(
            texture: meta,
            frameTableOffset: frameTblOff,
            innerTextureSize: innerSize,
            innerTextureOffset: startOffset,
            animations: animations,
            frameTable: Data(frameTableBytes),
            trailing: Data(trailingBytes)
        )
        return (image, metadata)
    }

    /// Serializes a single frame to bytes, computing the jump byte from loopTarget.
    /// `streamCursor` is the position (relative to the animation's start) where this
    /// frame's flags byte will be written — needed to derive the jump value.
    private func encodeFrame(_ frame: ATXFrame, at streamCursor: Int) -> [UInt8] {
        var flags: UInt8 = 0
        if frame.timing != nil      { flags |= Self.atxFlagTiming }
        if frame.rectWidth != nil   { flags |= Self.atxFlagRect }
        if frame.frameDelta != nil  { flags |= Self.atxFlagFrameDelta }
        if frame.loopTarget != nil  { flags |= Self.atxFlagJump }

        var bytes: [UInt8] = [flags]
        if let v = frame.timing      { bytes.append(v) }
        if let w = frame.rectWidth   { bytes.append(w); bytes.append(frame.rectHeight ?? 0) }
        if let v = frame.frameDelta  { bytes.append(v) }
        if let target = frame.loopTarget {
            // Jump byte sits at the last position in this record. Engine computes
            // `cursor = cursor − jumpByte`, so jumpByte = jumpBytePos − target.
            let jumpBytePos = streamCursor + bytes.count
            bytes.append(UInt8(truncatingIfNeeded: jumpBytePos - target))
        }
        return bytes
    }

    /// Encodes an image back to ATX binary, reconstructing the wrapper from structured metadata.
    public func encodeATX(image: GoDImage, metadata: ATXMetadata) -> GoDData? {
        guard let inner = encode(image: image, metadata: metadata.texture) else { return nil }

        let animCount = metadata.animations.count
        let offsetTableEnd = 0x10 + animCount * 2
        let keyframeSectionStart = offsetTableEnd
        let keyframeSectionEnd = metadata.frameTableOffset
        guard keyframeSectionEnd >= keyframeSectionStart else { return nil }
        let keyframeSectionLength = keyframeSectionEnd - keyframeSectionStart

        // Lay out the keyframe section by writing each animation's bytes at its
        // offset. Gaps are zero-filled (matches all observed XD samples).
        var keyframeSection = [UInt8](repeating: 0, count: keyframeSectionLength)
        for animation in metadata.animations {
            let writeStart = animation.offset - keyframeSectionStart
            guard writeStart >= 0, writeStart <= keyframeSectionLength else { return nil }
            var cursor = 0
            for frame in animation.frames {
                let frameBytes = encodeFrame(frame, at: cursor)
                let dst = writeStart + cursor
                guard dst + frameBytes.count <= keyframeSectionLength else { return nil }
                for (i, b) in frameBytes.enumerated() {
                    keyframeSection[dst + i] = b
                }
                cursor += frameBytes.count
            }
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(metadata.innerTextureOffset + inner.rawBytes.count + metadata.trailing.count)

        // Header: four big-endian u32 fields
        func appendU32BE(_ v: UInt32) {
            bytes.append(UInt8((v >> 24) & 0xFF))
            bytes.append(UInt8((v >> 16) & 0xFF))
            bytes.append(UInt8((v >>  8) & 0xFF))
            bytes.append(UInt8(v & 0xFF))
        }
        appendU32BE(UInt32(animCount))
        appendU32BE(UInt32(metadata.frameTableOffset))
        appendU32BE(UInt32(metadata.innerTextureSize))
        appendU32BE(UInt32(metadata.innerTextureOffset))

        // Animation offset table: animationCount big-endian u16s
        for animation in metadata.animations {
            let off = UInt16(animation.offset)
            bytes.append(UInt8((off >> 8) & 0xFF))
            bytes.append(UInt8(off & 0xFF))
        }

        bytes.append(contentsOf: keyframeSection)
        bytes.append(contentsOf: metadata.frameTable)
        bytes.append(contentsOf: inner.rawBytes)
        bytes.append(contentsOf: metadata.trailing)

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// How many bytes the texture at `headerOffset` occupies, read off its
    /// own header.
    ///
    /// A GTX embedded in a larger buffer — a DOL data section, an archive
    /// member — ends where its palette does, and the palette's offset and
    /// entry count are both header fields, so the length is derivable
    /// rather than something the caller has to be told. That matters where
    /// the surrounding container would otherwise guess: XD's health-warning
    /// texture has its own symbol (`tex_warning`) on the palette, so the
    /// disassembler's "a chunk ends at the next symbol" rule cuts the
    /// texture 32 bytes short.
    ///
    /// Returns nil when the header doesn't parse.
    public func measuredLength(data: GoDData, headerOffset: Int = 0) -> Int? {
        guard let meta = parseHeader(data: data, headerOffset: headerOffset) else { return nil }
        let fmt = meta.format
        guard meta.width > 0, meta.height > 0 else { return nil }

        data.setByteOrder(.big)
        let texOff: UInt32 = data.readSafely(atAddress: headerOffset + 0x28)
        let palOff: UInt32 = data.readSafely(atAddress: headerOffset + 0x48)

        if fmt.isIndexed && palOff > 0 {
            return Int(palOff) + fmt.paletteEntryCount * 2
        }
        let pw = padUp(meta.width, fmt.blockWidth), ph = padUp(meta.height, fmt.blockHeight)
        return Int(texOff) + pw * ph * fmt.bitsPerPixel / 8
    }

    public func decode(data: GoDData, headerOffset: Int = 0) -> GoDImage? {
        guard let meta = parseHeader(data: data, headerOffset: headerOffset) else { return nil }
        let fmt = meta.format
        let w = meta.width, h = meta.height
        guard w > 0 && h > 0 else { return nil }

        data.setByteOrder(.big)
        let texOff: UInt32 = data.readSafely(atAddress: headerOffset + 0x28)
        let palOff: UInt32 = data.readSafely(atAddress: headerOffset + 0x48)
        let texStart = headerOffset + Int(texOff)

        let pw = padUp(w, fmt.blockWidth), ph = padUp(h, fmt.blockHeight)
        let texLen: Int
        if fmt.isIndexed && palOff > 0 {
            texLen = headerOffset + Int(palOff) - texStart
        } else {
            texLen = pw * ph * fmt.bitsPerPixel / 8
        }
        guard texLen > 0 && texStart >= 0 && texStart + texLen <= data.length else { return nil }

        var palette = [(UInt8, UInt8, UInt8, UInt8)]()
        if fmt.isIndexed && palOff > 0 {
            let palStart = headerOffset + Int(palOff)
            let palFmt = meta.paletteFormat?.rawValue ?? 0
            for i in 0..<fmt.paletteEntryCount {
                let off = palStart + i * 2
                guard off + 2 <= data.length else { break }
                let raw: UInt16 = data.readSafely(atAddress: off)
                palette.append(color16(Int(raw), palFmt))
            }
        }

        let blockPixels: [(UInt8, UInt8, UInt8, UInt8)]
        switch fmt {
        case .RGBA32: blockPixels = decodeRGBA32(data, texStart, texLen)
        case .CMPR:   blockPixels = decodeCMPR(data, texStart, texLen)
        default:      blockPixels = decodeFlat(data, texStart, texLen, fmt, palette)
        }

        let bw = fmt.blockWidth, bh = fmt.blockHeight
        let ppb = bw * bh, bpr = pw / bw
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for (i, p) in blockPixels.enumerated() {
            let bi = i / ppb, ii = i % ppb
            let x = (bi % bpr) * bw + ii % bw
            let y = (bi / bpr) * bh + ii / bw
            guard x < w && y < h else { continue }
            let d = (y * w + x) * 4
            rgba[d] = p.0; rgba[d+1] = p.1; rgba[d+2] = p.2; rgba[d+3] = p.3
        }
        return GoDImage(width: w, height: h, pixels: GoDData(byteStream: rgba, byteOrder: .big))
    }

    // MARK: - Flat formats

    private func decodeFlat(_ data: GoDData, _ start: Int, _ len: Int, _ fmt: GXTextureFormat,
                            _ palette: [(UInt8, UInt8, UInt8, UInt8)]) -> [(UInt8, UInt8, UInt8, UInt8)] {
        var px = [(UInt8, UInt8, UInt8, UInt8)]()
        switch fmt.bitsPerPixel {
        case 4:
            for i in 0..<len {
                let b: UInt8 = data.readSafely(atAddress: start + i)
                let hi = Int(b >> 4), lo = Int(b & 0xF)
                if fmt.isIndexed {
                    px.append(hi < palette.count ? palette[hi] : (0,0,0,0))
                    px.append(lo < palette.count ? palette[lo] : (0,0,0,0))
                } else {
                    px.append(colorVal(hi, fmt)); px.append(colorVal(lo, fmt))
                }
            }
        case 8:
            for i in 0..<len {
                let v: UInt8 = data.readSafely(atAddress: start + i)
                if fmt.isIndexed { px.append(Int(v) < palette.count ? palette[Int(v)] : (0,0,0,0)) }
                else { px.append(colorVal(Int(v), fmt)) }
            }
        case 16:
            for i in 0..<(len/2) {
                let v: UInt16 = data.readSafely(atAddress: start + i*2)
                if fmt.isIndexed {
                    let idx = fmt == .C14X2 ? Int(v >> 2) : Int(v)
                    px.append(idx < palette.count ? palette[idx] : (0,0,0,0))
                } else { px.append(color16(Int(v), fmt.rawValue)) }
            }
        default: break
        }
        return px
    }

    // MARK: - RGBA32 (split AR/GB blocks)

    private func decodeRGBA32(_ data: GoDData, _ start: Int, _ len: Int) -> [(UInt8, UInt8, UInt8, UInt8)] {
        var shorts = [UInt16]()
        for i in 0..<(len/2) { let v: UInt16 = data.readSafely(atAddress: start + i*2); shorts.append(v) }
        var px = [(UInt8, UInt8, UInt8, UInt8)]()
        let blocks = shorts.count / 32
        for i in 0..<blocks {
            let bs = i * 32
            for j in 0..<16 {
                guard bs+j < shorts.count && bs+j+16 < shorts.count else { px.append((0,0,0,0)); continue }
                let argb = (UInt32(shorts[bs+j]) << 16) | UInt32(shorts[bs+j+16])
                px.append((UInt8((argb>>16)&0xFF), UInt8((argb>>8)&0xFF), UInt8(argb&0xFF), UInt8((argb>>24)&0xFF)))
            }
        }
        return px
    }

    // MARK: - CMPR (DXT1)

    private func decodeCMPR(_ data: GoDData, _ start: Int, _ len: Int) -> [(UInt8, UInt8, UInt8, UInt8)] {
        var longs = [(UInt32, UInt32)]()
        for i in stride(from: 0, to: len/4, by: 2) {
            let a: UInt32 = data.readSafely(atAddress: start + i*4)
            let b: UInt32 = i+1 < len/4 ? data.readSafely(atAddress: start + (i+1)*4) : 0
            longs.append((a, b))
        }
        var all = [[(UInt8, UInt8, UInt8, UInt8)]]()
        for i in stride(from: 0, to: longs.count, by: 4) {
            var subs = [[(UInt8, UInt8, UInt8, UInt8)]]()
            for j in 0..<4 { subs.append(i+j < longs.count ? dxt1(longs[i+j]) : Array(repeating: (0,0,0,0), count: 16)) }
            var block = [(UInt8, UInt8, UInt8, UInt8)]()
            for sr in 0...1 { for row in 0...3 { for col in 0...3 { block.append(subs[sr*2][row*4+col]) }
                                                  for col in 0...3 { block.append(subs[sr*2+1][row*4+col]) } } }
            all.append(block)
        }
        return all.flatMap { $0 }
    }

    private func dxt1(_ pair: (UInt32, UInt32)) -> [(UInt8, UInt8, UInt8, UInt8)] {
        let (pr, idx) = pair
        let h1 = Int(pr >> 16), h2 = Int(pr & 0xFFFF)
        let c1 = rgb565(h1), c2 = rgb565(h2)
        var pal = [c1, c2, (UInt8(0),UInt8(0),UInt8(0),UInt8(0)), (UInt8(0),UInt8(0),UInt8(0),UInt8(0))]
        if h1 > h2 {
            pal[2] = (UInt8((2*Int(c1.0)+Int(c2.0))/3), UInt8((2*Int(c1.1)+Int(c2.1))/3), UInt8((2*Int(c1.2)+Int(c2.2))/3), 255)
            pal[3] = (UInt8((2*Int(c2.0)+Int(c1.0))/3), UInt8((2*Int(c2.1)+Int(c1.1))/3), UInt8((2*Int(c2.2)+Int(c1.2))/3), 255)
        } else {
            pal[2] = (UInt8((Int(c1.0)+Int(c2.0))/2), UInt8((Int(c1.1)+Int(c2.1))/2), UInt8((Int(c1.2)+Int(c2.2))/2), 255)
            pal[3] = (0, 0, 0, 0)
        }
        return (0...15).map { let n = UInt32(15-$0); return pal[Int((idx >> (n*2)) & 3)] }
    }

    // MARK: - Color helpers

    private func rgb565(_ raw: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        (UInt8((raw>>11)&0x1F)*8, UInt8((raw>>5)&0x3F)*4, UInt8(raw&0x1F)*8, 255)
    }

    private func colorVal(_ raw: Int, _ fmt: GXTextureFormat) -> (UInt8, UInt8, UInt8, UInt8) {
        switch fmt {
        case .I4:  let v = UInt8(raw * 0x11); return (v, v, v, 255)
        case .I8:  let v = UInt8(raw); return (v, v, v, 255)
        case .IA4: let i = UInt8((raw & 0xF) * 0x11), a = UInt8((raw >> 4) * 0x11); return (i, i, i, a)
        case .IA8: let i = UInt8(raw & 0xFF), a = UInt8(raw >> 8); return (i, i, i, a)
        default:   return (0, 0, 0, 255)
        }
    }

    private func color16(_ raw: Int, _ fmt: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        switch fmt {
        case 0, 0x43: let i = UInt8(raw & 0xFF), a = UInt8(raw >> 8); return (i, i, i, a) // IA8
        case 1, 0x44: return rgb565(raw) // RGB565
        default: // RGB5A3
            if raw & 0x8000 != 0 { return (UInt8((raw>>10)&0x1F)*8, UInt8((raw>>5)&0x1F)*8, UInt8(raw&0x1F)*8, 255) }
            else { return (UInt8((raw>>8)&0xF)*0x11, UInt8((raw>>4)&0xF)*0x11, UInt8(raw&0xF)*0x11, UInt8((raw>>12)&7)*0x20) }
        }
    }

    private func padUp(_ val: Int, _ align: Int) -> Int { var v = val; while v % align != 0 { v += 1 }; return v }
    private func paddedSize(_ w: Int, _ h: Int, _ fmt: GXTextureFormat) -> Int { padUp(w, fmt.blockWidth) * padUp(h, fmt.blockHeight) }

    // MARK: - Encoder

    /// Encode a GoDImage back to GTX binary using the original texture metadata.
    public func encode(image: GoDImage, metadata: GXTextureMetadata) -> GoDData? {
        let w = metadata.width, h = metadata.height
        let fmt = metadata.format
        guard w > 0 && h > 0 else { return nil }
        guard image.width == w && image.height == h else { return nil }

        let rgba = image.pixels.rawBytes
        guard rgba.count == w * h * 4 else { return nil }

        let pw = padUp(w, fmt.blockWidth), ph = padUp(h, fmt.blockHeight)
        let bw = fmt.blockWidth, bh = fmt.blockHeight
        let ppb = bw * bh, bpr = pw / bw

        // Reorder scanline → block order, with padding for non-aligned dimensions
        let totalPixels = pw * ph
        var blockPixels = [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)](repeating: (0, 0, 0, 0), count: totalPixels)
        for y in 0..<h {
            for x in 0..<w {
                let src = (y * w + x) * 4
                let bi = (y / bh) * bpr + (x / bw)
                let ii = (y % bh) * bw + (x % bw)
                blockPixels[bi * ppb + ii] = (rgba[src], rgba[src+1], rgba[src+2], rgba[src+3])
            }
        }

        var texBytes: [UInt8]
        switch fmt {
        case .RGBA32: texBytes = encodeRGBA32(blockPixels, ppb: ppb)
        case .CMPR:   texBytes = encodeCMPR(blockPixels, ppb: ppb, width: w, height: h)
        default:      texBytes = encodeFlat(blockPixels, fmt)
        }

        var palBytes = [UInt8]()
        if fmt.isIndexed {
            let palFmt = metadata.paletteFormat ?? .RGB5A3
            var palette = [(UInt8, UInt8, UInt8, UInt8)]()
            var indexMap = [UInt32: Int]()

            var indices = [Int]()
            for p in blockPixels {
                let key = UInt32(p.r) << 24 | UInt32(p.g) << 16 | UInt32(p.b) << 8 | UInt32(p.a)
                if let idx = indexMap[key] {
                    indices.append(idx)
                } else if palette.count < fmt.paletteEntryCount {
                    let idx = palette.count
                    indexMap[key] = idx
                    palette.append(p)
                    indices.append(idx)
                } else {
                    indices.append(0)
                }
            }

            while palette.count < fmt.paletteEntryCount {
                palette.append((0, 0, 0, 0))
            }
            for c in palette {
                let raw = encodeColor16(c, palFmt)
                palBytes.append(UInt8(raw >> 8))
                palBytes.append(UInt8(raw & 0xFF))
            }

            texBytes = encodeIndices(indices, fmt)
        }

        // Build GTX binary: 0x80 header + texture data + palette data
        let headerSize = 0x80
        let texLen = texBytes.count
        let palOff = fmt.isIndexed ? headerSize + texLen : 0
        var output = [UInt8](repeating: 0, count: headerSize + texLen + palBytes.count)

        output[0] = UInt8(w >> 8); output[1] = UInt8(w & 0xFF)
        output[2] = UInt8(h >> 8); output[3] = UInt8(h & 0xFF)
        output[4] = UInt8(fmt.bitsPerPixel)
        // Always 1, not `isIndexed`. Every retail texture measured carries 1
        // here — 22 in the Colo/XD DOLs and 2480 across PBR's archives, of
        // which 1022 are not indexed — so whatever the field means, it isn't
        // "has a palette". Deriving it from the format was the one byte
        // between a non-indexed texture and a byte-identical rebuild.
        output[5] = 1
        output[0x0B] = UInt8(fmt.rawValue)
        output[0x0F] = UInt8(metadata.paletteFormat?.rawValue ?? 0)
        // Texture offset at 0x28 (big-endian UInt32 = 0x80)
        output[0x2B] = UInt8(headerSize)
        // Palette offset at 0x48
        if palOff > 0 {
            output[0x48] = UInt8(palOff >> 24); output[0x49] = UInt8((palOff >> 16) & 0xFF)
            output[0x4A] = UInt8((palOff >> 8) & 0xFF); output[0x4B] = UInt8(palOff & 0xFF)
        }

        output.replaceSubrange(headerSize..<headerSize + texLen, with: texBytes)
        if !palBytes.isEmpty {
            output.replaceSubrange(palOff..<palOff + palBytes.count, with: palBytes)
        }

        return GoDData(byteStream: output, byteOrder: .big)
    }

    // MARK: - Flat format encoding (I4, I8, IA4, IA8, RGB565, RGB5A3)

    private func encodeFlat(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)], _ fmt: GXTextureFormat) -> [UInt8] {
        switch fmt.bitsPerPixel {
        case 4:
            var bytes = [UInt8]()
            for i in stride(from: 0, to: pixels.count, by: 2) {
                let hi = encodePixel4(pixels[i], fmt)
                let lo = i + 1 < pixels.count ? encodePixel4(pixels[i + 1], fmt) : 0
                bytes.append(UInt8(hi << 4 | lo))
            }
            return bytes
        case 8:
            return pixels.map { encodePixel8($0, fmt) }
        case 16:
            var bytes = [UInt8]()
            for p in pixels {
                let raw = encodePixel16(p, fmt)
                bytes.append(UInt8(raw >> 8))
                bytes.append(UInt8(raw & 0xFF))
            }
            return bytes
        default:
            return []
        }
    }

    private func encodePixel4(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ fmt: GXTextureFormat) -> Int {
        switch fmt {
        case .I4: return (Int(p.r) + Int(p.g) + Int(p.b)) / (3 * 0x11)
        default: return 0
        }
    }

    private func encodePixel8(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ fmt: GXTextureFormat) -> UInt8 {
        switch fmt {
        case .I8: return UInt8((Int(p.r) + Int(p.g) + Int(p.b)) / 3)
        case .IA4:
            let i = (Int(p.r) + Int(p.g) + Int(p.b)) / (3 * 0x11)
            let a = Int(p.a) / 0x11
            return UInt8((a << 4) | i)
        default: return 0
        }
    }

    private func encodePixel16(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ fmt: GXTextureFormat) -> Int {
        switch fmt {
        case .IA8:
            let i = (Int(p.r) + Int(p.g) + Int(p.b)) / 3
            return (Int(p.a) << 8) | i
        case .RGB565:
            return (Int(p.r) / 8) << 11 | (Int(p.g) / 4) << 5 | (Int(p.b) / 8)
        case .RGB5A3:
            if p.a == 255 {
                return 0x8000 | (Int(p.r) / 8) << 10 | (Int(p.g) / 8) << 5 | (Int(p.b) / 8)
            } else {
                return (Int(p.a) / 0x20) << 12 | (Int(p.r) / 0x11) << 8 | (Int(p.g) / 0x11) << 4 | (Int(p.b) / 0x11)
            }
        default: return 0
        }
    }

    private func encodeColor16(_ p: (UInt8, UInt8, UInt8, UInt8), _ fmt: GXPaletteFormat) -> Int {
        switch fmt {
        case .IA8:
            let i = (Int(p.0) + Int(p.1) + Int(p.2)) / 3
            return (Int(p.3) << 8) | i
        case .RGB565:
            return (Int(p.0) / 8) << 11 | (Int(p.1) / 4) << 5 | (Int(p.2) / 8)
        case .RGB5A3, .RGB5A3_3:
            if p.3 == 255 {
                return 0x8000 | (Int(p.0) / 8) << 10 | (Int(p.1) / 8) << 5 | (Int(p.2) / 8)
            } else {
                return (Int(p.3) / 0x20) << 12 | (Int(p.0) / 0x11) << 8 | (Int(p.1) / 0x11) << 4 | (Int(p.2) / 0x11)
            }
        }
    }

    // MARK: - Indexed format encoding

    private func encodeIndices(_ indices: [Int], _ fmt: GXTextureFormat) -> [UInt8] {
        switch fmt.bitsPerPixel {
        case 4:
            var bytes = [UInt8]()
            for i in stride(from: 0, to: indices.count, by: 2) {
                let hi = indices[i]
                let lo = i + 1 < indices.count ? indices[i + 1] : 0
                bytes.append(UInt8((hi << 4) | lo))
            }
            return bytes
        case 8:
            return indices.map { UInt8($0) }
        case 16:
            var bytes = [UInt8]()
            for idx in indices {
                let v = fmt == .C14X2 ? idx << 2 : idx
                bytes.append(UInt8(v >> 8))
                bytes.append(UInt8(v & 0xFF))
            }
            return bytes
        default:
            return []
        }
    }

    // MARK: - RGBA32 encoding (split AR/GB blocks)

    private func encodeRGBA32(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)], ppb: Int) -> [UInt8] {
        var bytes = [UInt8]()
        let blockCount = pixels.count / ppb
        for i in 0..<blockCount {
            let blockStart = i * ppb
            // AR pairs first, then GB pairs
            for j in 0..<16 {
                let p = blockStart + j < pixels.count ? pixels[blockStart + j] : (r: UInt8(0), g: UInt8(0), b: UInt8(0), a: UInt8(0))
                bytes.append(p.a)
                bytes.append(p.r)
            }
            for j in 0..<16 {
                let p = blockStart + j < pixels.count ? pixels[blockStart + j] : (r: UInt8(0), g: UInt8(0), b: UInt8(0), a: UInt8(0))
                bytes.append(p.g)
                bytes.append(p.b)
            }
        }
        return bytes
    }

    // MARK: - CMPR encoding (DXT1 compression)

    private func encodeCMPR(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)], ppb: Int,
                            width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8]()
        let blockCount = pixels.count / ppb // 8x8 macro blocks
        let blocksPerRow = padUp(width, 8) / 8

        for i in 0..<blockCount {
            let blockStart = i * ppb
            let blockLeft = (i % blocksPerRow) * 8, blockTop = (i / blocksPerRow) * 8

            // Rearrange 8x8 block into four 4x4 sub-blocks
            // Block pixel layout: 8 rows of 8 pixels each
            // Sub-blocks: top-left, top-right, bottom-left, bottom-right
            var subBlocks = [[(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]](repeating: [], count: 4)
            // Which of each sub-block's sixteen positions are inside the image. A
            // texture whose dimensions aren't multiples of 8 pads out to the
            // block grid, and nothing ever displays those pixels, so an edge
            // block only has to reproduce the ones that are.
            var subVisible = [UInt16](repeating: 0, count: 4)
            for row in 0..<8 {
                for col in 0..<8 {
                    let idx = blockStart + row * 8 + col
                    let p = idx < pixels.count ? pixels[idx] : (r: UInt8(0), g: UInt8(0), b: UInt8(0), a: UInt8(0))
                    let subIdx = (row >= 4 ? 2 : 0) + (col >= 4 ? 1 : 0)
                    if blockLeft + col < width && blockTop + row < height {
                        subVisible[subIdx] |= 1 << UInt16(subBlocks[subIdx].count)
                    }
                    subBlocks[subIdx].append(p)
                }
            }

            for (sub, visible) in zip(subBlocks, subVisible) {
                bytes.append(contentsOf: encodeDXT1SubBlock(sub, visible: visible))
            }
        }
        return bytes
    }

    /// Encode one 4x4 sub-block.
    ///
    /// Re-compressing a *decoded* DXT1 block cannot reproduce it, and the reason
    /// is structural rather than a matter of search quality: the two endpoints
    /// appear in the decoded pixels only where some pixel actually used index 0
    /// or 1, and the two interpolated entries are 1/3 and 2/3 points that do not
    /// land back on the 5/6/5 grid, so quantizing them loses the endpoints they
    /// came from. Measured over the 3,354,460 sub-blocks of the 1,437 real CMPR
    /// textures in the Colosseum, XD and Battle Revolution dumps, 36 % of blocks
    /// use exactly one palette index and another 22 % use neither endpoint.
    ///
    /// So the encoder inverts first and compresses only as a fallback: given the
    /// sixteen decoded pixels it solves for endpoints whose palette reproduces
    /// them exactly. That is pixel-lossless on every block that came from DXT1,
    /// and byte-identical on the 78 % whose endpoints the decoded pixels still
    /// determine. Compression is reached only for a genuinely edited image.
    private func encodeDXT1SubBlock(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                    visible: UInt16) -> [UInt8] {
        // A padded edge block is tried whole first: the games pad with
        // transparency themselves on 69 % of such blocks, so reproducing the
        // padding is what reproduces their bytes. Only when that fails do the
        // invisible positions become free, which is what lets a block whose
        // visible colors need the opaque four-color palette still come back
        // exactly.
        if let exact = invertDXT1SubBlock(pixels, visible: 0xFFFF) { return exact }
        if visible != 0xFFFF, let exact = invertDXT1SubBlock(pixels, visible: visible) { return exact }
        return compressDXT1SubBlock(pixels, visible: visible)
    }

    // MARK: - CMPR encoding: exact inversion

    /// The decoded levels each endpoint channel can take: red and blue are
    /// 5-bit and step by 8, green is 6-bit and steps by 4.
    private static let dxt1ChannelStep = [8, 4, 8]
    private static let dxt1ChannelMax  = [248, 252, 248]

    private func dxt1OnGrid(_ channel: Int, _ value: Int) -> Bool {
        value >= 0 && value <= Self.dxt1ChannelMax[channel]
            && value % Self.dxt1ChannelStep[channel] == 0
    }

    private func dxt1Pack(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (r / 8) << 11 | (g / 4) << 5 | (b / 8)
    }

    private func dxt1Bytes(_ endpoint0: Int, _ endpoint1: Int, _ indices: UInt32) -> [UInt8] {
        [UInt8(endpoint0 >> 8), UInt8(endpoint0 & 0xFF),
         UInt8(endpoint1 >> 8), UInt8(endpoint1 & 0xFF),
         UInt8(indices >> 24), UInt8((indices >> 16) & 0xFF),
         UInt8((indices >> 8) & 0xFF), UInt8(indices & 0xFF)]
    }

    /// The four colors a pair of endpoints addresses. `endpoint0 > endpoint1`
    /// selects the opaque four-color palette; otherwise index 3 is transparent.
    private func dxt1Palette(_ endpoint0: Int, _ endpoint1: Int) -> [(r: Int, g: Int, b: Int, a: Int)] {
        let c1 = decodeRGB565(endpoint0), c2 = decodeRGB565(endpoint1)
        if endpoint0 > endpoint1 {
            return [c1, c2,
                    (r: (2 * c1.r + c2.r) / 3, g: (2 * c1.g + c2.g) / 3, b: (2 * c1.b + c2.b) / 3, a: 255),
                    (r: (2 * c2.r + c1.r) / 3, g: (2 * c2.g + c1.g) / 3, b: (2 * c2.b + c1.b) / 3, a: 255)]
        }
        return [c1, c2,
                (r: (c1.r + c2.r) / 2, g: (c1.g + c2.g) / 2, b: (c1.b + c2.b) / 2, a: 255),
                (r: 0, g: 0, b: 0, a: 0)]
    }

    private func dxt1Reproduces(_ endpoint0: Int, _ endpoint1: Int, _ indices: UInt32,
                                _ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                visible: UInt16) -> Bool {
        let palette = dxt1Palette(endpoint0, endpoint1)
        for (position, pixel) in pixels.enumerated() {
            guard visible & (1 << UInt16(position)) != 0 else { continue }
            let entry = palette[Int((indices >> UInt32(2 * (15 - position))) & 3)]
            if Int(pixel.r) != entry.r || Int(pixel.g) != entry.g
                || Int(pixel.b) != entry.b || Int(pixel.a) != entry.a { return false }
        }
        return true
    }

    /// The distinct opaque colors of a sub-block, in first-appearance order,
    /// plus whether any pixel is transparent.
    private func dxt1DistinctColors(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                    visible: UInt16)
        -> (colors: [(r: Int, g: Int, b: Int)], hasTransparency: Bool) {
        var colors = [(r: Int, g: Int, b: Int)]()
        var hasTransparency = false
        for (position, pixel) in pixels.enumerated() {
            guard visible & (1 << UInt16(position)) != 0 else { continue }
            if pixel.a < 0x80 { hasTransparency = true; continue }
            let color = (r: Int(pixel.r), g: Int(pixel.g), b: Int(pixel.b))
            if !colors.contains(where: { $0 == color }) { colors.append(color) }
        }
        return (colors, hasTransparency)
    }

    private func dxt1Channel(_ color: (r: Int, g: Int, b: Int), _ channel: Int) -> Int {
        switch channel {
        case 0:  return color.r
        case 1:  return color.g
        default: return color.b
        }
    }

    /// Every injective mapping of `colorCount` colors onto `slots`.
    private func dxt1Assignments(colorCount: Int, slots: [Int]) -> [[Int]] {
        var result = [[Int]]()
        var current = [Int](repeating: 0, count: colorCount)
        var used = [Bool](repeating: false, count: slots.count)
        func extend(_ position: Int) {
            if position == colorCount { result.append(current); return }
            for (slotIndex, slot) in slots.enumerated() where !used[slotIndex] {
                used[slotIndex] = true
                current[position] = slot
                extend(position + 1)
                used[slotIndex] = false
            }
        }
        extend(0)
        return result
    }

    /// Candidate `(endpoint0, endpoint1)` levels for one channel, given the
    /// levels the block needs at the indices it uses. `interp2` and `interp3`
    /// invert the palette's own arithmetic: a truncating `(2a + b) / 3` pins
    /// `2a + b` to a three-wide window, and the grid step is wider than that, so
    /// one known endpoint plus one interpolated color determines the other
    /// endpoint outright. Returns nil when nothing constrains the pair at all.
    private func dxt1ChannelCandidates(channel: Int, known0: Int?, known1: Int?,
                                       interp2: Int?, interp3: Int?,
                                       fourColor: Bool) -> [(a: Int, b: Int)]? {
        let step = Self.dxt1ChannelStep[channel], maximum = Self.dxt1ChannelMax[channel]

        func partners(of a: Int) -> [Int] {
            var low = 0, high = maximum
            if fourColor {
                if let interp2 {
                    low = max(low, 3 * interp2 - 2 * a)
                    high = min(high, 3 * interp2 + 2 - 2 * a)
                }
                if let interp3 {
                    let lowest = 3 * interp3 - a
                    low = max(low, lowest <= 0 ? 0 : (lowest + 1) / 2)
                    high = min(high, (3 * interp3 + 2 - a) / 2)
                }
            } else if let interp2 {
                low = max(low, 2 * interp2 - a)
                high = min(high, 2 * interp2 + 1 - a)
            }
            guard low <= high else { return [] }
            var candidates = [Int]()
            var value = ((low + step - 1) / step) * step
            while value <= high { candidates.append(value); value += step }
            return candidates
        }

        if let known0, let known1 { return [(a: known0, b: known1)] }
        if let known0 { return partners(of: known0).map { (a: known0, b: $0) } }
        if let known1 {
            return stride(from: 0, through: maximum, by: step)
                .filter { partners(of: $0).contains(known1) }
                .map { (a: $0, b: known1) }
        }
        guard interp2 != nil || interp3 != nil else { return nil }
        return stride(from: 0, through: maximum, by: step).flatMap { a in
            partners(of: a).map { (a: a, b: $0) }
        }
    }

    /// Pick one `(a, b)` pair per channel so the packed endpoints carry the
    /// ordering the mode needs. Red sits in the high bits, so the comparison is
    /// settled by the most significant channel in which the endpoints differ:
    /// hold every channel above it to a pair that is equal, make that one carry
    /// the inequality, and leave the rest free.
    private func dxt1Combine(_ perChannel: [[(a: Int, b: Int)]], fourColor: Bool,
                             indices: UInt32,
                             _ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                             visible: UInt16) -> [UInt8]? {
        var equal = [[(a: Int, b: Int)]](repeating: [], count: 3)
        var ordered = [[(a: Int, b: Int)]](repeating: [], count: 3)
        for channel in 0..<3 {
            let step = Self.dxt1ChannelStep[channel]
            for pair in perChannel[channel] {
                let value0 = pair.a / step, value1 = pair.b / step
                if value0 == value1 { equal[channel].append(pair) }
                else if (value0 > value1) == fourColor { ordered[channel].append(pair) }
            }
        }
        var budget = 512
        for decisive in 0..<3 {
            if (0..<decisive).contains(where: { equal[$0].isEmpty }) { break }
            if ordered[decisive].isEmpty { continue }
            let lists = (0..<3).map { channel -> [(a: Int, b: Int)] in
                if channel < decisive { return equal[channel] }
                if channel == decisive { return ordered[channel] }
                return perChannel[channel]
            }
            for red in lists[0] {
                for green in lists[1] {
                    for blue in lists[2] {
                        if budget <= 0 { return nil }
                        budget -= 1
                        let endpoint0 = dxt1Pack(red.a, green.a, blue.a)
                        let endpoint1 = dxt1Pack(red.b, green.b, blue.b)
                        if dxt1Reproduces(endpoint0, endpoint1, indices, pixels, visible: visible) {
                            return dxt1Bytes(endpoint0, endpoint1, indices)
                        }
                    }
                }
            }
        }
        // Both endpoints equal: a three-color block whose only color is its own
        // endpoint, which is how a flat block that happens to sit on the grid
        // can be written.
        guard !fourColor, (0..<3).allSatisfy({ !equal[$0].isEmpty }) else { return nil }
        let flat = dxt1Pack(equal[0][0].a, equal[1][0].a, equal[2][0].a)
        guard dxt1Reproduces(flat, flat, indices, pixels, visible: visible) else { return nil }
        return dxt1Bytes(flat, flat, indices)
    }

    /// Solve one (assignment, mode) pair, or nil if it cannot reproduce the block.
    private func dxt1Solve(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                           colors: [(r: Int, g: Int, b: Int)], assignment: [Int],
                           fourColor: Bool, visible: UInt16) -> [UInt8]? {
        var perChannel = [[(a: Int, b: Int)]]()
        for channel in 0..<3 {
            var known0: Int?, known1: Int?, interp2: Int?, interp3: Int?
            for (position, color) in colors.enumerated() {
                let level = dxt1Channel(color, channel)
                switch assignment[position] {
                case 0:
                    // An endpoint is a stored 5/6/5 value, so a color claiming
                    // that slot has to sit on the grid.
                    guard dxt1OnGrid(channel, level) else { return nil }
                    known0 = level
                case 1:
                    guard dxt1OnGrid(channel, level) else { return nil }
                    known1 = level
                case 2:  interp2 = level
                default: interp3 = level
                }
            }
            guard let candidates = dxt1ChannelCandidates(channel: channel, known0: known0,
                                                         known1: known1, interp2: interp2,
                                                         interp3: interp3, fourColor: fourColor),
                  !candidates.isEmpty else { return nil }
            perChannel.append(candidates)
        }
        var indices: UInt32 = 0
        for (position, pixel) in pixels.enumerated() {
            indices <<= 2
            // An invisible position is free: index 0 keeps it out of the way of
            // the solve, and nothing reads it back.
            guard visible & (1 << UInt16(position)) != 0 else { continue }
            if pixel.a < 0x80 { indices |= 3; continue }
            let color = (r: Int(pixel.r), g: Int(pixel.g), b: Int(pixel.b))
            guard let match = colors.firstIndex(where: { $0 == color }) else { return nil }
            indices |= UInt32(assignment[match])
        }
        return dxt1Combine(perChannel, fourColor: fourColor, indices: indices, pixels, visible: visible)
    }

    /// Recover a DXT1 sub-block whose palette reproduces `pixels` exactly, or
    /// nil when no such block exists.
    private func invertDXT1SubBlock(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                    visible: UInt16) -> [UInt8]? {
        let (colors, hasTransparency) = dxt1DistinctColors(pixels, visible: visible)
        if colors.isEmpty {
            // Wholly transparent. The games write zero endpoints with every
            // index 3 in 71 % of such blocks; the rest keep leftover source
            // color in endpoints no decoded pixel can recover.
            return hasTransparency ? dxt1Bytes(0, 0, 0xFFFFFFFF) : nil
        }
        guard colors.count <= 4 else { return nil }

        // One opaque color on the grid is the degenerate case, and the games'
        // compressor has a convention for it: the color at index 0 with a second
        // endpoint one step above it in red, which reads as three-color. Where
        // red is already at its maximum the step moves to blue, and for white,
        // where neither can move, the color goes to index 1 above a zero
        // endpoint 0. Measured across the three games' CMPR textures: 90-99 %
        // per game of the 178,010 blocks of the first shape follow the red step,
        // and 99 % of the 67,180 of the second the latter.
        if colors.count == 1, !hasTransparency,
           (0..<3).allSatisfy({ dxt1OnGrid($0, dxt1Channel(colors[0], $0)) }) {
            let packed = dxt1Pack(colors[0].r, colors[0].g, colors[0].b)
            if (packed >> 11) & 0x1F < 31 { return dxt1Bytes(packed, packed + 0x0800, 0) }
            if packed & 0x1F < 31 { return dxt1Bytes(packed, packed + 1, 0) }
            if packed > 0 { return dxt1Bytes(0, packed, 0x55555555) }
        }

        // Endpoints-only three-color first: a block needing no interpolated
        // entry is written with the lower endpoint first on 98 % of real blocks,
        // where a compressor would reach for four-color and emit the endpoints
        // the other way round.
        let passes: [(fourColor: Bool, slots: [Int])] =
            [(false, [0, 1]), (true, [0, 1, 2, 3]), (false, [0, 1, 2])]
        for pass in passes {
            if hasTransparency && pass.fourColor { continue }
            if colors.count > pass.slots.count { continue }
            for assignment in dxt1Assignments(colorCount: colors.count, slots: pass.slots) {
                // Covered by the first pass already.
                if !pass.fourColor && pass.slots.count == 3 && assignment.allSatisfy({ $0 < 2 }) { continue }
                if let bytes = dxt1Solve(pixels, colors: colors, assignment: assignment,
                                         fourColor: pass.fourColor, visible: visible) { return bytes }
            }
        }
        return nil
    }

    // MARK: - CMPR encoding: lossy fallback

    /// Compress a block the inversion could not reconstruct — an edited image.
    private func compressDXT1SubBlock(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                      visible: UInt16) -> [UInt8] {
        var uniqueColors = [Int]()
        for (position, p) in pixels.enumerated()
        where visible & (1 << UInt16(position)) != 0 && p.a >= 0x80 {
            let rgb = encodePixel16(p, .RGB565)
            if !uniqueColors.contains(rgb) { uniqueColors.append(rgb) }
        }

        if uniqueColors.isEmpty {
            return dxt1Bytes(0, 0, 0xFFFFFFFF)
        }

        // The two colors furthest apart are the endpoints: every interpolated
        // entry lies between them in each channel, so the widest pair is the
        // pair that spans them.
        var bestC0 = uniqueColors[0], bestC1 = uniqueColors[0]
        if uniqueColors.count > 1 {
            var greatestRange = 0
            for c0 in uniqueColors {
                for c1 in uniqueColors {
                    let d = colorDistance565(c0, c1)
                    if d > greatestRange { greatestRange = d; bestC0 = c0; bestC1 = c1 }
                }
            }
        }

        // Which way round the endpoints go chooses the mode, so try both and
        // keep the one that fits the pixels better. Deciding it from the
        // presence of transparency alone forces four-color on every opaque
        // block, and a block whose colors are an endpoint pair's *midpoint*
        // then has to settle for a 1/3 point instead.
        let low = min(bestC0, bestC1), high = max(bestC0, bestC1)
        var best: (error: Int, endpoint0: Int, endpoint1: Int, indices: UInt32)?
        for (endpoint0, endpoint1) in (low == high ? [(low, high)] : [(high, low), (low, high)]) {
            guard let fit = fitDXT1Indices(pixels, endpoint0, endpoint1, visible: visible) else { continue }
            if best == nil || fit.error < best!.error {
                best = (fit.error, endpoint0, endpoint1, fit.indices)
            }
        }
        guard let chosen = best else {
            // Transparency with a single color: three-color is the only mode
            // that can express it, and equal endpoints are three-color.
            let fit = fitDXT1Indices(pixels, low, high, visible: visible) ?? (indices: 0, error: 0)
            return dxt1Bytes(low, high, fit.indices)
        }
        return dxt1Bytes(chosen.endpoint0, chosen.endpoint1, chosen.indices)
    }

    /// Index every pixel against one endpoint pair, or nil if the pair cannot
    /// carry the block's transparency.
    private func fitDXT1Indices(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)],
                                _ endpoint0: Int, _ endpoint1: Int,
                                visible: UInt16) -> (indices: UInt32, error: Int)? {
        let palette = dxt1Palette(endpoint0, endpoint1)
        let threeColor = !(endpoint0 > endpoint1)
        var indices: UInt32 = 0
        var error = 0
        for (position, p) in pixels.enumerated() {
            indices <<= 2
            guard visible & (1 << UInt16(position)) != 0 else { continue }
            if p.a < 0x80 {
                guard threeColor else { return nil }
                indices |= 3
                continue
            }
            // In three-color mode index 3 is transparent, so an opaque pixel
            // must never be given it however near black it is.
            var bestIndex = 0, minDistance = Int.max
            for candidate in 0..<(threeColor ? 3 : 4) {
                let entry = palette[candidate]
                let d = abs(Int(p.r) - entry.r) + abs(Int(p.g) - entry.g) + abs(Int(p.b) - entry.b)
                if d < minDistance { minDistance = d; bestIndex = candidate }
            }
            indices |= UInt32(bestIndex)
            error += minDistance
        }
        return (indices, error)
    }

    private func decodeRGB565(_ raw: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        (r: ((raw >> 11) & 0x1F) * 8, g: ((raw >> 5) & 0x3F) * 4, b: (raw & 0x1F) * 8, a: 255)
    }

    private func colorDistance565(_ c0: Int, _ c1: Int) -> Int {
        let a = decodeRGB565(c0), b = decodeRGB565(c1)
        return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }
}
