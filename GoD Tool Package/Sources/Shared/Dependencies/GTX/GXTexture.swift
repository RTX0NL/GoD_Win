import GoDFoundation

/// Metadata for a GX texture, stored in the FSYS registry for re-encoding on import
public struct GXTextureMetadata: Codable, Equatable {
    public let width: Int
    public let height: Int
    public let format: GXTextureFormat
    public let paletteFormat: GXPaletteFormat?
    public let frameCount: Int?

    public init(width: Int, height: Int, format: GXTextureFormat, paletteFormat: GXPaletteFormat? = nil, frameCount: Int? = nil) {
        self.width = width
        self.height = height
        self.format = format
        self.paletteFormat = paletteFormat
        self.frameCount = frameCount
    }
}

/// GS palette format IDs
public enum GXPaletteFormat: Int, Codable, CaseIterable {
    case ia8 = 0, rgb565 = 1, rgb5a3 = 2, rgb5a3_standalone = 3

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

/// GS texture format IDs
public enum GXTextureFormat: Int, CaseIterable, Codable, Equatable {
    case c4 = 0x00, c8 = 0x01, c14x2 = 0x30
    case i4 = 0x40, ia4 = 0x41, i8 = 0x42, ia8 = 0x43
    case rgb565 = 0x44, rgba32 = 0x45, rgb5a3 = 0x90, cmpr = 0xB0

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
        case .i4, .c4, .cmpr: return 8
        case .ia4, .i8, .c8: return 8
        case .ia8, .rgb565, .rgb5a3, .rgba32, .c14x2: return 4
        }
    }

    public var blockHeight: Int {
        switch self {
        case .i4, .c4, .cmpr: return 8
        case .ia4, .i8, .c8: return 4
        case .ia8, .rgb565, .rgb5a3, .rgba32, .c14x2: return 4
        }
    }

    public var bitsPerPixel: Int {
        switch self {
        case .i4, .c4, .cmpr: return 4
        case .ia4, .i8, .c8: return 8
        case .ia8, .rgb565, .rgb5a3, .c14x2: return 16
        case .rgba32: return 32
        }
    }

    public var isIndexed: Bool {
        switch self { case .c4, .c8, .c14x2: return true; default: return false }
    }

    public var paletteEntryCount: Int {
        switch self { case .c4: return 16; case .c8: return 256; case .c14x2: return 16384; default: return 0 }
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

    public func parseATXHeader(data: GoDData) -> GXTextureMetadata? {
        guard let first = parseHeader(data: data) else { return nil }
        let fmt = first.format
        let texSize = paddedSize(first.width, first.height, fmt) * fmt.bitsPerPixel / 8
        let palSize = fmt.isIndexed ? fmt.paletteEntryCount * 2 : 0
        let texOff: UInt32 = data.readSafely(atAddress: 0x28)
        let palOff: UInt32 = data.readSafely(atAddress: 0x48)
        let frameSize = palSize > 0 && palOff > 0 ? Int(palOff) + palSize : Int(texOff) + texSize
        guard frameSize > 0 else { return nil }
        return GXTextureMetadata(width: first.width, height: first.height, format: fmt,
                                 paletteFormat: first.paletteFormat, frameCount: max(1, data.length / frameSize))
    }

    /// Decode a single GTX frame to a GoDImage
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

        // Read palette
        var palette = [(UInt8, UInt8, UInt8, UInt8)]()
        if fmt.isIndexed && palOff > 0 {
            let palStart = headerOffset + Int(palOff)
            let palFmt = meta.paletteFormat?.rawValue ?? 0
            for i in 0..<fmt.paletteEntryCount {
                let off = palStart + i * 2
                guard off + 2 <= data.length else { break }
                let raw: UInt16 = data.readSafely(atAddress: off)
                palette.append(colour16(Int(raw), palFmt))
            }
        }

        // Decode pixels in block order
        let blockPixels: [(UInt8, UInt8, UInt8, UInt8)]
        switch fmt {
        case .rgba32: blockPixels = decodeRGBA32(data, texStart, texLen)
        case .cmpr:   blockPixels = decodeCMPR(data, texStart, texLen)
        default:      blockPixels = decodeFlat(data, texStart, texLen, fmt, palette)
        }

        // Reorder block order → scanline order
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
                    px.append(colourVal(hi, fmt)); px.append(colourVal(lo, fmt))
                }
            }
        case 8:
            for i in 0..<len {
                let v: UInt8 = data.readSafely(atAddress: start + i)
                if fmt.isIndexed { px.append(Int(v) < palette.count ? palette[Int(v)] : (0,0,0,0)) }
                else { px.append(colourVal(Int(v), fmt)) }
            }
        case 16:
            for i in 0..<(len/2) {
                let v: UInt16 = data.readSafely(atAddress: start + i*2)
                if fmt.isIndexed {
                    let idx = fmt == .c14x2 ? Int(v >> 2) : Int(v)
                    px.append(idx < palette.count ? palette[idx] : (0,0,0,0))
                } else { px.append(colour16(Int(v), fmt.rawValue)) }
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

    // MARK: - Colour helpers

    private func rgb565(_ raw: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        (UInt8((raw>>11)&0x1F)*8, UInt8((raw>>5)&0x3F)*4, UInt8(raw&0x1F)*8, 255)
    }

    private func colourVal(_ raw: Int, _ fmt: GXTextureFormat) -> (UInt8, UInt8, UInt8, UInt8) {
        switch fmt {
        case .i4:  let v = UInt8(raw * 0x11); return (v, v, v, 255)
        case .i8:  let v = UInt8(raw); return (v, v, v, 255)
        case .ia4: let i = UInt8((raw & 0xF) * 0x11), a = UInt8((raw >> 4) * 0x11); return (i, i, i, a)
        case .ia8: let i = UInt8(raw & 0xFF), a = UInt8(raw >> 8); return (i, i, i, a)
        default:   return (0, 0, 0, 255)
        }
    }

    private func colour16(_ raw: Int, _ fmt: Int) -> (UInt8, UInt8, UInt8, UInt8) {
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

        // Encode pixels to bytes
        var texBytes: [UInt8]
        switch fmt {
        case .rgba32: texBytes = encodeRGBA32(blockPixels, ppb: ppb)
        case .cmpr:   texBytes = encodeCMPR(blockPixels, ppb: ppb)
        default:      texBytes = encodeFlat(blockPixels, fmt)
        }

        // Build palette for indexed formats
        var palBytes = [UInt8]()
        if fmt.isIndexed {
            let palFmt = metadata.paletteFormat ?? .rgb5a3
            var palette = [(UInt8, UInt8, UInt8, UInt8)]()
            var indexMap = [UInt32: Int]()

            // Build palette and remap indices
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

            // Encode palette
            while palette.count < fmt.paletteEntryCount {
                palette.append((0, 0, 0, 0))
            }
            for c in palette {
                let raw = encodeColour16(c, palFmt)
                palBytes.append(UInt8(raw >> 8))
                palBytes.append(UInt8(raw & 0xFF))
            }

            // Encode indices
            texBytes = encodeIndices(indices, fmt)
        }

        // Build GTX binary: 0x80 header + texture data + palette data
        let headerSize = 0x80
        let texLen = texBytes.count
        let palOff = fmt.isIndexed ? headerSize + texLen : 0
        var output = [UInt8](repeating: 0, count: headerSize + texLen + palBytes.count)

        // Header
        output[0] = UInt8(w >> 8); output[1] = UInt8(w & 0xFF)
        output[2] = UInt8(h >> 8); output[3] = UInt8(h & 0xFF)
        output[4] = UInt8(fmt.bitsPerPixel)
        output[5] = fmt.isIndexed ? 1 : 0
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
        case .i4: return (Int(p.r) + Int(p.g) + Int(p.b)) / (3 * 0x11)
        default: return 0
        }
    }

    private func encodePixel8(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ fmt: GXTextureFormat) -> UInt8 {
        switch fmt {
        case .i8: return UInt8((Int(p.r) + Int(p.g) + Int(p.b)) / 3)
        case .ia4:
            let i = (Int(p.r) + Int(p.g) + Int(p.b)) / (3 * 0x11)
            let a = Int(p.a) / 0x11
            return UInt8((a << 4) | i)
        default: return 0
        }
    }

    private func encodePixel16(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ fmt: GXTextureFormat) -> Int {
        switch fmt {
        case .ia8:
            let i = (Int(p.r) + Int(p.g) + Int(p.b)) / 3
            return (Int(p.a) << 8) | i
        case .rgb565:
            return (Int(p.r) / 8) << 11 | (Int(p.g) / 4) << 5 | (Int(p.b) / 8)
        case .rgb5a3:
            if p.a == 255 {
                return 0x8000 | (Int(p.r) / 8) << 10 | (Int(p.g) / 8) << 5 | (Int(p.b) / 8)
            } else {
                return (Int(p.a) / 0x20) << 12 | (Int(p.r) / 0x11) << 8 | (Int(p.g) / 0x11) << 4 | (Int(p.b) / 0x11)
            }
        default: return 0
        }
    }

    private func encodeColour16(_ p: (UInt8, UInt8, UInt8, UInt8), _ fmt: GXPaletteFormat) -> Int {
        switch fmt {
        case .ia8:
            let i = (Int(p.0) + Int(p.1) + Int(p.2)) / 3
            return (Int(p.3) << 8) | i
        case .rgb565:
            return (Int(p.0) / 8) << 11 | (Int(p.1) / 4) << 5 | (Int(p.2) / 8)
        case .rgb5a3, .rgb5a3_standalone:
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
                let v = fmt == .c14x2 ? idx << 2 : idx
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

    private func encodeCMPR(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)], ppb: Int) -> [UInt8] {
        var bytes = [UInt8]()
        let blockCount = pixels.count / ppb // 8x8 macro blocks

        for i in 0..<blockCount {
            let blockStart = i * ppb

            // Rearrange 8x8 block into four 4x4 sub-blocks
            // Block pixel layout: 8 rows of 8 pixels each
            // Sub-blocks: top-left, top-right, bottom-left, bottom-right
            var subBlocks = [[(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]](repeating: [], count: 4)
            for row in 0..<8 {
                for col in 0..<8 {
                    let idx = blockStart + row * 8 + col
                    let p = idx < pixels.count ? pixels[idx] : (r: UInt8(0), g: UInt8(0), b: UInt8(0), a: UInt8(0))
                    let subIdx = (row >= 4 ? 2 : 0) + (col >= 4 ? 1 : 0)
                    subBlocks[subIdx].append(p)
                }
            }

            // Encode each 4x4 sub-block as DXT1
            for sub in subBlocks {
                bytes.append(contentsOf: encodeDXT1SubBlock(sub))
            }
        }
        return bytes
    }

    private func encodeDXT1SubBlock(_ pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) -> [UInt8] {
        var hasTransparency = false
        var uniqueColours = [Int]()

        for p in pixels {
            if p.a < 0x80 {
                hasTransparency = true
            } else {
                let rgb = encodePixel16(p, .rgb565)
                if !uniqueColours.contains(rgb) { uniqueColours.append(rgb) }
            }
        }

        if uniqueColours.isEmpty {
            return [0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]
        }

        // Find the two colours with the greatest range
        var bestC0 = uniqueColours[0], bestC1 = uniqueColours[0]
        if uniqueColours.count > 1 {
            var greatestRange = 0
            for c0 in uniqueColours {
                for c1 in uniqueColours {
                    let d = colourDistance565(c0, c1)
                    if d > greatestRange { greatestRange = d; bestC0 = c0; bestC1 = c1 }
                }
            }
        }

        let hex1: Int, hex2: Int
        if hasTransparency {
            hex1 = min(bestC0, bestC1); hex2 = max(bestC0, bestC1)
        } else {
            hex1 = max(bestC0, bestC1); hex2 = min(bestC0, bestC1)
        }

        // Build interpolated palette
        let c1 = decodeRGB565(hex1), c2 = decodeRGB565(hex2)
        var pal = [c1, c2, (r: 0, g: 0, b: 0, a: 0), (r: 0, g: 0, b: 0, a: 0)]
        if hex1 > hex2 {
            pal[2] = (r: (2*c1.r + c2.r) / 3, g: (2*c1.g + c2.g) / 3, b: (2*c1.b + c2.b) / 3, a: 255)
            pal[3] = (r: (2*c2.r + c1.r) / 3, g: (2*c2.g + c1.g) / 3, b: (2*c2.b + c1.b) / 3, a: 255)
        } else {
            pal[2] = (r: (c1.r + c2.r) / 2, g: (c1.g + c2.g) / 2, b: (c1.b + c2.b) / 2, a: 255)
            pal[3] = (r: 0, g: 0, b: 0, a: 0)
        }

        // Find closest palette index for each pixel
        var indexBits: UInt32 = 0
        for p in pixels {
            indexBits <<= 2
            if p.a < 0x80 {
                indexBits |= 3
            } else {
                var bestIdx = 0, minDist = Int.max
                for j in 0..<pal.count {
                    let d = abs(Int(p.r) - pal[j].r) + abs(Int(p.g) - pal[j].g) + abs(Int(p.b) - pal[j].b)
                    if d < minDist { minDist = d; bestIdx = j }
                }
                indexBits |= UInt32(bestIdx)
            }
        }

        var result = [UInt8]()
        result.append(UInt8(hex1 >> 8)); result.append(UInt8(hex1 & 0xFF))
        result.append(UInt8(hex2 >> 8)); result.append(UInt8(hex2 & 0xFF))
        result.append(UInt8(indexBits >> 24)); result.append(UInt8((indexBits >> 16) & 0xFF))
        result.append(UInt8((indexBits >> 8) & 0xFF)); result.append(UInt8(indexBits & 0xFF))
        return result
    }

    private func decodeRGB565(_ raw: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        (r: ((raw >> 11) & 0x1F) * 8, g: ((raw >> 5) & 0x3F) * 4, b: (raw & 0x1F) * 8, a: 255)
    }

    private func colourDistance565(_ c0: Int, _ c1: Int) -> Int {
        let a = decodeRGB565(c0), b = decodeRGB565(c1)
        return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }
}
