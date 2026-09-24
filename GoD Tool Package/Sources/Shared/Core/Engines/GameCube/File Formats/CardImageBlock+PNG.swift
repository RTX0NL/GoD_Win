//
//  CardImageBlock+PNG.swift
//
//  Card banners and icon frames as PNG files.
//
//  Direct-color images become ordinary RGBA PNGs. Paletted ones become
//  *indexed* PNGs, which is the part that matters: an RGBA PNG would
//  lose which index carried which color and collapse duplicate palette
//  entries, so re-encoding it would rebuild a different palette for
//  identical pixels and the save would no longer match the bytes it came
//  from. An indexed PNG preserves the index map and the palette order,
//  so the round trip is exact.
//

import Foundation
import GoDFoundation
import GTX

public extension CardImageBlock.Image {

    /// Encode as a PNG file's bytes. Dimensions are the caller's because
    /// indices carry none of their own, and a banner is 96x32 while an
    /// icon frame is 32x32.
    func pngData(width: Int, height: Int) -> GoDData? {
        switch self {
        case let .direct(image):
            guard image.width == width, image.height == height else { return nil }
            return image.pngData()
        case let .paletted(indices, palette):
            guard indices.count == width * height else { return nil }
            var flattened = [UInt8]()
            flattened.reserveCapacity(palette.count * 4)
            for color in palette {
                flattened.append(color.r)
                flattened.append(color.g)
                flattened.append(color.b)
                flattened.append(color.a)
            }
            return GoDIndexedImage(
                width: width, height: height, indices: indices, palette: flattened
            ).pngData()
        }
    }

    /// Decode from a PNG file's bytes. `paletted` says which form the
    /// directory entry declares, so a PNG saved in the wrong color type
    /// is rejected rather than silently re-indexed.
    static func fromPNG(
        _ data: GoDData,
        paletted: Bool,
        width: Int,
        height: Int
    ) throws -> CardImageBlock.Image {
        if paletted {
            guard let indexed = GoDIndexedImage.fromPNG(data) else {
                throw CardImageBlockError.pngNotIndexed(.init())
            }
            guard indexed.width == width, indexed.height == height else {
                throw CardImageBlockError.imageSizeMismatch(
                    expected: "\(width)x\(height)",
                    actual: "\(indexed.width)x\(indexed.height)", .init()
                )
            }
            guard indexed.paletteEntryCount <= CardImageBlock.paletteEntryCount else {
                throw CardImageBlockError.paletteTooLarge(
                    entries: indexed.paletteEntryCount,
                    maximum: CardImageBlock.paletteEntryCount, .init()
                )
            }
            // The card always stores a full 256-entry palette. A PNG may
            // carry fewer if its trailing entries went unused, so pad
            // rather than reject: the unused tail is not observable.
            var palette = (0..<indexed.paletteEntryCount).map { index -> GXColor in
                let offset = index * 4
                return GXColor(
                    r: indexed.palette[offset],
                    g: indexed.palette[offset + 1],
                    b: indexed.palette[offset + 2],
                    a: indexed.palette[offset + 3]
                )
            }
            while palette.count < CardImageBlock.paletteEntryCount {
                palette.append(GXColor(r: 0, g: 0, b: 0, a: 0))
            }
            return .paletted(indices: indexed.indices, palette: palette)
        }

        guard let image = GoDImage.fromPNG(data) else {
            throw CardImageBlockError.pngDecodeFailed(.init())
        }
        guard image.width == width, image.height == height else {
            throw CardImageBlockError.imageSizeMismatch(
                expected: "\(width)x\(height)",
                actual: "\(image.width)x\(image.height)", .init()
            )
        }
        return .direct(image)
    }
}

public extension CardImageBlock {

    /// Filename a piece is written to inside the metadata folder.
    static func artifactFilename(for kind: Piece.Kind) -> String? {
        switch kind {
        case .banner: return "banner.png"
        case let .frame(slot): return "icon-\(slot).png"
        case .sharedPalette: return nil
        }
    }

    /// Dimensions of a piece, which the format fixes.
    static func dimensions(for kind: Piece.Kind) -> (width: Int, height: Int)? {
        switch kind {
        case .banner: return (bannerWidth, bannerHeight)
        case .frame: return (iconWidth, iconHeight)
        case .sharedPalette: return nil
        }
    }

    /// Rebuild a block from PNG bytes keyed by filename, keeping the
    /// layout and per-frame formats the directory entry declares.
    ///
    /// The shared palette is taken from the first shared-palette frame
    /// rather than stored separately, since PNG carries a palette with
    /// every indexed image. `encoded()` then checks the rest agree.
    static func fromArtifacts(
        layout: Layout,
        pngData: [String: GoDData]
    ) throws -> CardImageBlock {
        var banner: Image?
        var frames: [Frame] = []
        var sharedPalette: [GXColor]?

        for piece in layout.pieces {
            guard let filename = artifactFilename(for: piece.kind),
                  let dimensions = dimensions(for: piece.kind) else { continue }
            guard let data = pngData[filename] else {
                throw CardImageBlockError.missingArtifact(filename: filename, .init())
            }

            switch piece.kind {
            case .banner:
                banner = try Image.fromPNG(
                    data,
                    paletted: layout.bannerFormat == .ci8,
                    width: dimensions.width,
                    height: dimensions.height
                )
            case let .frame(slot):
                let (format, speed) = layout.slots[slot]
                let image = try Image.fromPNG(
                    data,
                    paletted: format.isPaletted,
                    width: dimensions.width,
                    height: dimensions.height
                )
                if format == .ci8SharedPalette, sharedPalette == nil {
                    sharedPalette = image.palette
                }
                frames.append(Frame(slot: slot, format: format, speed: speed, image: image))
            case .sharedPalette:
                break
            }
        }

        if layout.sharedPaletteOffset != nil, sharedPalette == nil {
            throw CardImageBlockError.missingSharedPalette(offset: layout.offset, .init())
        }

        return CardImageBlock(
            layout: layout, banner: banner, frames: frames, sharedPalette: sharedPalette
        )
    }

    /// Every piece as a PNG file, keyed by filename.
    func pngArtifacts() throws -> [String: GoDData] {
        var artifacts: [String: GoDData] = [:]
        if let banner,
           let filename = Self.artifactFilename(for: .banner),
           let size = Self.dimensions(for: .banner) {
            guard let data = banner.pngData(width: size.width, height: size.height) else {
                throw CardImageBlockError.pngEncodeFailed(filename: filename, .init())
            }
            artifacts[filename] = data
        }
        for frame in frames {
            let kind = Piece.Kind.frame(slot: frame.slot)
            guard let filename = Self.artifactFilename(for: kind),
                  let size = Self.dimensions(for: kind) else { continue }
            guard let data = frame.image.pngData(width: size.width, height: size.height) else {
                throw CardImageBlockError.pngEncodeFailed(filename: filename, .init())
            }
            artifacts[filename] = data
        }
        return artifacts
    }

    /// True when the block re-encodes to exactly the bytes it was read
    /// from. A dump checks this before trusting the PNGs as the source of
    /// truth; a block that fails has to keep its raw bytes instead.
    func verifies(against body: GoDData) -> Bool {
        guard layout.end <= body.length else { return false }
        guard let reencoded = try? encoded() else { return false }
        return reencoded.rawBytes == Array(body.rawBytes[layout.offset..<layout.end])
    }
}
