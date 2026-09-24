import Foundation
import PNG

/// An RGBA8888 image with width, height, and raw pixel data.
public struct GoDImage {
    public let width: Int
    public let height: Int
    /// Raw RGBA8888 pixel data (width * height * 4 bytes)
    public let pixels: GoDData

    public init(width: Int, height: Int, pixels: GoDData) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Encode this image to PNG format
    public func pngData() -> GoDData? {
        let rgba = pixels.rawBytes
        guard rgba.count == width * height * 4 else { return nil }

        let pngPixels: [PNG.RGBA<UInt8>] = (0..<(width * height)).map { i in
            let o = i * 4
            return .init(rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3])
        }

        let image = PNG.Data.Rectangular(
            packing: pngPixels,
            size: (width, height),
            layout: .init(format: .rgba8(palette: [], fill: nil))
        )

        var stream = PNGWriteStream()
        do {
            try image.compress(stream: &stream, level: 0)
        } catch {
            return nil
        }

        return GoDData(byteStream: stream.bytes, byteOrder: .big)
    }

    /// Decode a PNG file into an image
    public static func fromPNG(_ data: GoDData) -> GoDImage? {
        var stream = PNGReadStream(data: data.rawBytes)

        guard let image = try? PNG.Data.Rectangular.decompress(stream: &stream) else {
            return nil
        }

        let decoded: [PNG.RGBA<UInt8>] = image.unpack(as: PNG.RGBA<UInt8>.self)
        let (w, h) = image.size

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for (i, pixel) in decoded.enumerated() {
            let o = i * 4
            rgba[o] = pixel.r
            rgba[o + 1] = pixel.g
            rgba[o + 2] = pixel.b
            rgba[o + 3] = pixel.a
        }

        return GoDImage(
            width: w,
            height: h,
            pixels: GoDData(byteStream: rgba, byteOrder: .big)
        )
    }
}

// MARK: - PNG Byte Streams

private struct PNGWriteStream: PNG.Bytestream.Destination {
    var bytes = [UInt8]()

    mutating func write(_ data: [UInt8]) -> Void? {
        bytes.append(contentsOf: data)
        return ()
    }
}

private struct PNGReadStream: PNG.Bytestream.Source {
    let data: [UInt8]
    var position = 0

    init(data: [UInt8]) {
        self.data = data
    }

    mutating func read(count: Int) -> [UInt8]? {
        guard position + count <= data.count else { return nil }
        let result = Array(data[position..<(position + count)])
        position += count
        return result
    }
}

// MARK: - Indexed images

/// A paletted image, kept as indices plus a palette rather than as
/// color.
///
/// Flattening a paletted image to RGBA loses which index carried which
/// color and collapses duplicate palette entries, so re-encoding one
/// rebuilds a different palette for identical pixels. Where an exact
/// round trip matters — a GameCube memory-card icon, whose palette is
/// shared between frames and checksummed by the game — the indices and
/// the palette order are the thing to preserve, and PNG's own indexed
/// format preserves both.
public struct GoDIndexedImage {
    public let width: Int
    public let height: Int
    /// One palette index per pixel, row-major.
    public let indices: [UInt8]
    /// Palette entries as RGBA, four bytes each.
    public let palette: [UInt8]

    public init(width: Int, height: Int, indices: [UInt8], palette: [UInt8]) {
        self.width = width
        self.height = height
        self.indices = indices
        self.palette = palette
    }

    public var paletteEntryCount: Int { palette.count / 4 }

    /// Encode as an indexed (color type 3) PNG.
    public func pngData() -> GoDData? {
        guard width > 0, height > 0 else { return nil }
        guard indices.count == width * height else { return nil }
        guard palette.count % 4 == 0, !palette.isEmpty, paletteEntryCount <= 256 else { return nil }

        let entries: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] = (0..<paletteEntryCount).map {
            let offset = $0 * 4
            return (palette[offset], palette[offset + 1], palette[offset + 2], palette[offset + 3])
        }

        let image = PNG.Image(
            packing: indices,
            size: (width, height),
            layout: .init(format: .indexed8(palette: entries, fill: nil)),
            indexer: { _ in { Int($0) } }
        )

        var stream = PNGWriteStream()
        do {
            try image.compress(stream: &stream, level: 0)
        } catch {
            return nil
        }
        return GoDData(byteStream: stream.bytes, byteOrder: .big)
    }

    /// Decode an indexed PNG back to indices and palette. Returns `nil`
    /// for a PNG that isn't indexed, since flattened color could not be
    /// re-indexed without inventing a palette.
    public static func fromPNG(_ data: GoDData) -> GoDIndexedImage? {
        var stream = PNGReadStream(data: data.rawBytes)
        guard let image = try? PNG.Image.decompress(stream: &stream) else { return nil }

        let entries: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]
        switch image.layout.format {
        case let .indexed1(palette, _),
             let .indexed2(palette, _),
             let .indexed4(palette, _),
             let .indexed8(palette, _):
            entries = palette
        default:
            return nil
        }

        let (width, height) = image.size
        let indices = image.unpack(as: UInt8.self, deindexer: { _ in { UInt8(truncatingIfNeeded: $0) } })
        guard indices.count == width * height else { return nil }

        var palette = [UInt8]()
        palette.reserveCapacity(entries.count * 4)
        for entry in entries {
            palette.append(entry.r)
            palette.append(entry.g)
            palette.append(entry.b)
            palette.append(entry.a)
        }

        return GoDIndexedImage(width: width, height: height, indices: indices, palette: palette)
    }
}
