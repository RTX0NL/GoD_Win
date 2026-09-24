//
//  GXTiledPixels.swift
//
//  Raw access to GameCube tiled pixel data, with no GTX header in front
//  of it.
//
//  `GXTextureDecoder`'s existing entry points start by parsing a GTX
//  header, which is a Genius Sonority wrapper. The pixel encoding inside
//  is not: it is the console's own GX tiling, and other containers store
//  it bare. Memory-card banners and icons are the case this was added
//  for — their geometry comes from the save's directory entry rather
//  than from any header, so the caller already knows the width, height,
//  format and palette and only needs the codec.
//
//  Indices are exposed separately from colors on purpose. Decoding a
//  paletted image straight to RGBA loses which index carried which
//  color and collapses duplicate palette entries, so re-encoding it
//  rebuilds a different palette for identical pixels. Callers that need
//  an exact round trip work in indices and carry the palette alongside.
//

import Foundation
import GoDFoundation

/// One palette entry, or one decoded pixel.
public struct GXColor: Equatable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public extension GXTextureDecoder {

    // MARK: - Geometry

    /// Byte length of `width` × `height` pixels in `format`, including the
    /// padding rows and columns tiling adds when the dimensions aren't a
    /// whole number of blocks.
    static func tiledByteCount(width: Int, height: Int, format: GXTextureFormat) -> Int {
        let paddedWidth = roundUp(width, to: format.blockWidth)
        let paddedHeight = roundUp(height, to: format.blockHeight)
        return paddedWidth * paddedHeight * format.bitsPerPixel / 8
    }

    private static func roundUp(_ value: Int, to multiple: Int) -> Int {
        guard multiple > 0 else { return value }
        let remainder = value % multiple
        return remainder == 0 ? value : value + (multiple - remainder)
    }

    /// Maps each scanline pixel position to its index in tiled order.
    /// Positions that fall in the tiling's padding have no scanline
    /// counterpart and are absent from the result.
    private static func tiledPositions(width: Int, height: Int, format: GXTextureFormat) -> [Int] {
        let blockWidth = format.blockWidth, blockHeight = format.blockHeight
        let paddedWidth = roundUp(width, to: blockWidth)
        let pixelsPerBlock = blockWidth * blockHeight
        let blocksPerRow = paddedWidth / blockWidth
        var positions = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let block = (y / blockHeight) * blocksPerRow + (x / blockWidth)
                let within = (y % blockHeight) * blockWidth + (x % blockWidth)
                positions[y * width + x] = block * pixelsPerBlock + within
            }
        }
        return positions
    }

    // MARK: - Palettes

    /// Decode a 16-bit palette. `entries` is the entry count, not a byte
    /// length — a CI8 palette is 256 entries and 512 bytes.
    func decodePalette(
        data: GoDData,
        offset: Int,
        entries: Int,
        format: GXPaletteFormat
    ) -> [GXColor]? {
        guard entries >= 0, offset >= 0, offset + entries * 2 <= data.length else { return nil }
        data.setByteOrder(.big)
        return (0..<entries).map { index in
            let raw: UInt16 = data.readSafely(atAddress: offset + index * 2)
            let (r, g, b, a) = paletteColor(Int(raw), format)
            return GXColor(r: r, g: g, b: b, a: a)
        }
    }

    /// Re-encode palette entries to their 16-bit form.
    func encodePalette(_ colors: [GXColor], format: GXPaletteFormat) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(colors.count * 2)
        for color in colors {
            let raw = encodeColor(color, format)
            bytes.append(UInt8(truncatingIfNeeded: raw >> 8))
            bytes.append(UInt8(truncatingIfNeeded: raw))
        }
        return bytes
    }

    // MARK: - Direct-color images

    /// Decode tiled direct-color pixels to a scanline-order image.
    func decodeTiledDirect(
        data: GoDData,
        offset: Int,
        width: Int,
        height: Int,
        format: GXTextureFormat
    ) -> GoDImage? {
        guard !format.isIndexed, width > 0, height > 0, offset >= 0 else { return nil }
        guard format.bitsPerPixel == 16 else { return nil }
        let length = Self.tiledByteCount(width: width, height: height, format: format)
        guard offset + length <= data.length else { return nil }

        data.setByteOrder(.big)
        let positions = Self.tiledPositions(width: width, height: height, format: format)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for (scanline, tiled) in positions.enumerated() {
            let raw: UInt16 = data.readSafely(atAddress: offset + tiled * 2)
            let (r, g, b, a) = directColor(Int(raw), format)
            let destination = scanline * 4
            rgba[destination] = r
            rgba[destination + 1] = g
            rgba[destination + 2] = b
            rgba[destination + 3] = a
        }
        return GoDImage(
            width: width,
            height: height,
            pixels: GoDData(byteStream: rgba, byteOrder: .big)
        )
    }

    /// Encode a scanline-order image back to tiled direct-color pixels.
    func encodeTiledDirect(image: GoDImage, format: GXTextureFormat) -> [UInt8]? {
        guard !format.isIndexed, format.bitsPerPixel == 16 else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let rgba = image.pixels.rawBytes
        guard rgba.count == width * height * 4 else { return nil }

        let length = Self.tiledByteCount(width: width, height: height, format: format)
        var bytes = [UInt8](repeating: 0, count: length)
        let positions = Self.tiledPositions(width: width, height: height, format: format)
        for (scanline, tiled) in positions.enumerated() {
            let source = scanline * 4
            let color = GXColor(
                r: rgba[source], g: rgba[source + 1],
                b: rgba[source + 2], a: rgba[source + 3]
            )
            let raw = encodeDirectColor(color, format)
            bytes[tiled * 2] = UInt8(truncatingIfNeeded: raw >> 8)
            bytes[tiled * 2 + 1] = UInt8(truncatingIfNeeded: raw)
        }
        return bytes
    }

    // MARK: - Paletted images

    /// Decode tiled 8-bit paletted pixels to scanline-order palette
    /// indices. The palette is the caller's to supply and is not applied
    /// here, so nothing about the original indexing is lost.
    func decodeTiledIndices(
        data: GoDData,
        offset: Int,
        width: Int,
        height: Int,
        format: GXTextureFormat
    ) -> [UInt8]? {
        guard format.isIndexed, format.bitsPerPixel == 8 else { return nil }
        guard width > 0, height > 0, offset >= 0 else { return nil }
        let length = Self.tiledByteCount(width: width, height: height, format: format)
        guard offset + length <= data.length else { return nil }

        let positions = Self.tiledPositions(width: width, height: height, format: format)
        return positions.map { data.readSafely(atAddress: offset + $0) as UInt8 }
    }

    /// Encode scanline-order palette indices back to tiled bytes.
    func encodeTiledIndices(
        _ indices: [UInt8],
        width: Int,
        height: Int,
        format: GXTextureFormat
    ) -> [UInt8]? {
        guard format.isIndexed, format.bitsPerPixel == 8 else { return nil }
        guard width > 0, height > 0, indices.count == width * height else { return nil }

        let length = Self.tiledByteCount(width: width, height: height, format: format)
        var bytes = [UInt8](repeating: 0, count: length)
        let positions = Self.tiledPositions(width: width, height: height, format: format)
        for (scanline, tiled) in positions.enumerated() {
            bytes[tiled] = indices[scanline]
        }
        return bytes
    }

    // MARK: - Single-pixel conversions

    /// A 16-bit palette entry as RGBA.
    private func paletteColor(_ raw: Int, _ format: GXPaletteFormat) -> (UInt8, UInt8, UInt8, UInt8) {
        switch format {
        case .IA8:
            let intensity = UInt8(raw & 0xFF), alpha = UInt8((raw >> 8) & 0xFF)
            return (intensity, intensity, intensity, alpha)
        case .RGB565:
            return decodeRGB565Color(raw)
        case .RGB5A3, .RGB5A3_3:
            return decodeRGB5A3Color(raw)
        }
    }

    /// A 16-bit direct-color pixel as RGBA.
    private func directColor(_ raw: Int, _ format: GXTextureFormat) -> (UInt8, UInt8, UInt8, UInt8) {
        switch format {
        case .IA8:
            let intensity = UInt8(raw & 0xFF), alpha = UInt8((raw >> 8) & 0xFF)
            return (intensity, intensity, intensity, alpha)
        case .RGB565:
            return decodeRGB565Color(raw)
        default:
            return decodeRGB5A3Color(raw)
        }
    }

    private func decodeRGB565Color(_ raw: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        (UInt8((raw >> 11) & 0x1F) * 8, UInt8((raw >> 5) & 0x3F) * 4, UInt8(raw & 0x1F) * 8, 255)
    }

    private func decodeRGB5A3Color(_ raw: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        if raw & 0x8000 != 0 {
            return (UInt8((raw >> 10) & 0x1F) * 8, UInt8((raw >> 5) & 0x1F) * 8, UInt8(raw & 0x1F) * 8, 255)
        }
        return (
            UInt8((raw >> 8) & 0xF) * 0x11,
            UInt8((raw >> 4) & 0xF) * 0x11,
            UInt8(raw & 0xF) * 0x11,
            UInt8((raw >> 12) & 7) * 0x20
        )
    }

    private func encodeColor(_ color: GXColor, _ format: GXPaletteFormat) -> Int {
        switch format {
        case .IA8:
            let intensity = (Int(color.r) + Int(color.g) + Int(color.b)) / 3
            return (Int(color.a) << 8) | intensity
        case .RGB565:
            return encodeRGB565Color(color)
        case .RGB5A3, .RGB5A3_3:
            return encodeRGB5A3Color(color)
        }
    }

    private func encodeDirectColor(_ color: GXColor, _ format: GXTextureFormat) -> Int {
        switch format {
        case .IA8:
            let intensity = (Int(color.r) + Int(color.g) + Int(color.b)) / 3
            return (Int(color.a) << 8) | intensity
        case .RGB565:
            return encodeRGB565Color(color)
        default:
            return encodeRGB5A3Color(color)
        }
    }

    private func encodeRGB565Color(_ color: GXColor) -> Int {
        (Int(color.r) / 8) << 11 | (Int(color.g) / 4) << 5 | (Int(color.b) / 8)
    }

    /// RGB5A3 is exactly invertible in both branches: each channel is
    /// widened by a factor this divides back out, and only the opaque
    /// branch yields alpha 255, so the branch choice round-trips too.
    private func encodeRGB5A3Color(_ color: GXColor) -> Int {
        if color.a == 255 {
            return 0x8000 | (Int(color.r) / 8) << 10 | (Int(color.g) / 8) << 5 | (Int(color.b) / 8)
        }
        return (Int(color.a) / 0x20) << 12
            | (Int(color.r) / 0x11) << 8
            | (Int(color.g) / 0x11) << 4
            | (Int(color.b) / 0x11)
    }
}
