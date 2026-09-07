//
//  GoDData+GreyscalePNG.swift
//  GoDFoundation
//
//  Greyscale PNG encode/decode, for artifacts whose pixels carry a single
//  intensity channel — font atlases, principally.
//
//  `GoDImage.pngData()` writes RGBA8, which is right for textures but wrong
//  for a font: a glyph is 4bpp intensity, so three of the four channels would
//  be an exact copy of the first and the fourth a constant. That compresses
//  away, but it also invites an editor to hand back genuinely coloured pixels
//  and leaves the reader guessing which channel meant something. A greyscale
//  file states the intent in the format itself.
//
//  Decoding deliberately accepts *any* PNG flavour and reports what it found,
//  because an image editor will happily save back RGB, RGBA or 16-bit. The
//  caller decides whether to accept the drift — see `GreyscaleImage.isFaithful`.
//

import Foundation
import PNG

/// A single-channel 8-bit image.
public struct GreyscaleImage {
    public let width: Int
    public let height: Int
    /// One byte per pixel, row-major.
    public let pixels: [UInt8]

    /// True when every source pixel was already a neutral grey — that is, the
    /// file really was greyscale (or an RGB image whose channels agreed).
    /// False means an editor introduced colour, and the values below are the
    /// luminance it collapsed to.
    public let wasNeutral: Bool

    public init(width: Int, height: Int, pixels: [UInt8], wasNeutral: Bool = true) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.wasNeutral = wasNeutral
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return pixels[y * width + x]
    }

    /// Encode as an 8-bit greyscale PNG.
    public func pngData() -> GoDData? {
        // The scalar-packing overload treats a `[UInt8]` as greyscale
        // samples directly, which is exactly what these pixels are.
        let image = PNG.Image(
            packing: pixels,
            size: (width, height),
            layout: .init(format: .v8(fill: nil, key: nil))
        )
        var stream = GreyscalePNGWriteStream()
        do {
            // Level 6, not 9. These sheets are mostly empty so they compress
            // an order of magnitude either way, and level 9 made encoding the
            // largest atlas (11,800 glyphs) dominate the test suite's runtime
            // for a few percent of size.
            try image.compress(stream: &stream, level: 6)
        } catch {
            return nil
        }
        return GoDData(byteStream: stream.bytes, byteOrder: .big)
    }

    /// Decode a PNG of any flavour into a single channel.
    ///
    /// Colour is collapsed to luminance rather than rejected: refusing an RGB
    /// file would mean an atlas became unloadable because someone's editor
    /// defaulted to colour, which is a worse outcome than a warning. Whether
    /// the source was neutral is reported so the caller can say so.
    public static func fromPNG(_ data: GoDData) -> GreyscaleImage? {
        var stream = GreyscalePNGReadStream(data: data.rawBytes)
        guard let image = try? PNG.Image.decompress(stream: &stream) else {
            return nil
        }
        let (w, h) = image.size
        let rgba: [PNG.RGBA<UInt8>] = image.unpack(as: PNG.RGBA<UInt8>.self)
        var out = [UInt8](repeating: 0, count: w * h)
        var neutral = true
        for (i, p) in rgba.enumerated() {
            if p.r != p.g || p.g != p.b { neutral = false }
            // Rec. 601 luma, which for a neutral pixel is exactly the value.
            out[i] = p.r == p.g && p.g == p.b
                ? p.r
                : UInt8(min(255, (299 * Int(p.r) + 587 * Int(p.g) + 114 * Int(p.b)) / 1000))
        }
        return GreyscaleImage(width: w, height: h, pixels: out, wasNeutral: neutral)
    }
}

private struct GreyscalePNGWriteStream: PNG.Bytestream.Destination {
    var bytes = [UInt8]()
    mutating func write(_ data: [UInt8]) -> Void? {
        bytes.append(contentsOf: data)
        return ()
    }
}

private struct GreyscalePNGReadStream: PNG.Bytestream.Source {
    let data: [UInt8]
    var offset = 0
    init(data: [UInt8]) { self.data = data }
    mutating func read(count: Int) -> [UInt8]? {
        guard offset + count <= data.count else { return nil }
        defer { offset += count }
        return Array(data[offset ..< offset + count])
    }
}
