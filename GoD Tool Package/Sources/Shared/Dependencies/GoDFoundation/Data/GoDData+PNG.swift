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
