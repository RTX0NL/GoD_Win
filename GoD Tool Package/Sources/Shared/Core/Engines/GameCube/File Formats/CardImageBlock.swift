//
//  CardImageBlock.swift
//
//  The banner and animated icon a GameCube save carries, derived from
//  the save's own directory entry.
//
//  This is generic to the console, not to any game. A `.gci`'s 0x40
//  directory entry says where the image block starts, what format the
//  banner is in, and what format and speed each of up to eight icon
//  frames has. Every size follows from those fields plus fixed
//  dimensions, so the whole block can be located and decoded for any
//  GameCube title without knowing which one it is.
//
//  See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.
//

import Foundation
import GoDFoundation
import GTX

public struct CardImageBlock {

    // MARK: - Fixed dimensions

    public static let bannerWidth = 96
    public static let bannerHeight = 32
    public static let iconWidth = 32
    public static let iconHeight = 32
    public static let paletteEntryCount = 256
    public static let paletteByteCount = paletteEntryCount * 2
    public static let maximumFrameCount = 8

    /// `imageOffset` when the save carries no banner or icon at all.
    public static let noImageOffset: UInt32 = 0xFFFFFFFF

    // MARK: - Field values

    public enum BannerFormat: Int, Codable, CaseIterable {
        case none = 0
        case ci8 = 1
        case rgb5a3 = 2
        /// The field is two bits wide, so `3` is representable. Nintendo's
        /// own tooling treats it as "no banner", same as `0`.
        case none3 = 3

        public var byteCount: Int {
            switch self {
            case .none, .none3: return 0
            case .ci8: return bannerWidth * bannerHeight + CardImageBlock.paletteByteCount
            case .rgb5a3: return bannerWidth * bannerHeight * 2
            }
        }

        private var bannerWidth: Int { CardImageBlock.bannerWidth }
        private var bannerHeight: Int { CardImageBlock.bannerHeight }

        public var isPresent: Bool {
            switch self {
            case .none, .none3: return false
            case .ci8, .rgb5a3: return true
            }
        }
    }

    public enum IconFormat: Int, Codable, CaseIterable {
        case none = 0
        case ci8SharedPalette = 1
        case rgb5a3 = 2
        case ci8UniquePalette = 3

        /// Bytes this frame occupies, its own palette included. A
        /// shared-palette frame contributes only pixels; the one shared
        /// palette is accounted for separately, after every frame.
        public var byteCount: Int {
            let pixels = CardImageBlock.iconWidth * CardImageBlock.iconHeight
            switch self {
            case .none: return 0
            case .ci8SharedPalette: return pixels
            case .rgb5a3: return pixels * 2
            case .ci8UniquePalette: return pixels + CardImageBlock.paletteByteCount
            }
        }

        public var isPaletted: Bool {
            self == .ci8SharedPalette || self == .ci8UniquePalette
        }
    }

    /// How long a frame stays on screen, in video frames.
    public enum AnimationSpeed: Int, Codable, CaseIterable {
        case none = 0
        case fast = 1
        case middle = 2
        case slow = 3

        public var videoFrames: Int {
            switch self {
            case .none: return 0
            case .fast: return 4
            case .middle: return 8
            case .slow: return 12
            }
        }
    }

    public enum AnimationOrder: String, Codable, CaseIterable {
        case loop
        case pingPong
    }

    // MARK: - Decoded content

    /// A decoded banner or icon frame. A paletted image keeps its indices
    /// and its palette rather than being flattened to color, because
    /// flattening is what makes a re-encode inexact.
    public enum Image {
        case direct(GoDImage)
        case paletted(indices: [UInt8], palette: [GXColor])

        public var isPaletted: Bool {
            switch self {
            case .direct: return false
            case .paletted: return true
            }
        }

        public var palette: [GXColor]? {
            switch self {
            case .direct: return nil
            case let .paletted(_, palette): return palette
            }
        }
    }

    public struct Frame {
        /// Which of the eight 2-bit field positions this frame came from.
        /// Live frames are not necessarily contiguous — Luigi's Mansion
        /// uses slots 0, 3 and 7 — so the slot has to be preserved.
        public let slot: Int
        public let format: IconFormat
        public let speed: AnimationSpeed
        public let image: Image

        public init(slot: Int, format: IconFormat, speed: AnimationSpeed, image: Image) {
            self.slot = slot
            self.format = format
            self.speed = speed
            self.image = image
        }
    }

    // MARK: - Layout

    /// One addressable run inside the image block.
    public struct Piece {
        public enum Kind: Equatable {
            case banner
            case frame(slot: Int)
            case sharedPalette
        }

        public let kind: Kind
        public let offset: Int
        public let length: Int

        public var end: Int { offset + length }
    }

    /// Where the image block sits and what it is made of, derived from
    /// the directory entry alone.
    public struct Layout {
        public let offset: Int
        public let pieces: [Piece]
        public let bannerFormat: BannerFormat
        public let animationOrder: AnimationOrder
        /// Per-slot format and speed, all eight positions, dead ones included.
        public let slots: [(format: IconFormat, speed: AnimationSpeed)]
        public let sharedPaletteOffset: Int?

        /// One past the last byte of the block.
        public var end: Int { pieces.map(\.end).max() ?? offset }
        public var length: Int { end - offset }
        public var liveSlots: [Int] {
            pieces.compactMap { piece in
                if case let .frame(slot) = piece.kind { return slot }
                return nil
            }
        }
    }

    /// Derive the block's layout from a directory entry. Returns `nil`
    /// when the save declares no images.
    ///
    /// Frames are walked the way libogc's `__card_updateiconoffsets`
    /// does: a slot with no format or no speed contributes nothing and is
    /// skipped, and the walk continues to the end. Dolphin instead stops
    /// at the first zero speed. The two agree unless the speed field has
    /// a hole in it, which no real save has; `frameWalkIsAmbiguous`
    /// reports that case so a caller can warn.
    public static func layout(header: GCIFile.Header) -> Layout? {
        guard header.imageOffset != noImageOffset else { return nil }
        let start = Int(header.imageOffset)
        guard start >= 0 else { return nil }

        let bannerFormat = BannerFormat(rawValue: Int(header.bannerAndIconFlags & 0b11)) ?? .none
        let order: AnimationOrder = (header.bannerAndIconFlags & 0b100) != 0 ? .pingPong : .loop

        var pieces: [Piece] = []
        var cursor = start

        if bannerFormat.isPresent {
            pieces.append(.init(kind: .banner, offset: cursor, length: bannerFormat.byteCount))
            cursor += bannerFormat.byteCount
        }

        var slots: [(format: IconFormat, speed: AnimationSpeed)] = []
        var hasSharedPalette = false
        for slot in 0..<maximumFrameCount {
            let format = IconFormat(rawValue: Int((header.iconFmt >> (2 * slot)) & 0b11)) ?? .none
            let speed = AnimationSpeed(rawValue: Int((header.animSpeed >> (2 * slot)) & 0b11)) ?? .none
            slots.append((format, speed))
            guard format != .none, speed != .none else { continue }
            pieces.append(.init(kind: .frame(slot: slot), offset: cursor, length: format.byteCount))
            cursor += format.byteCount
            if format == .ci8SharedPalette { hasSharedPalette = true }
        }

        var sharedPaletteOffset: Int?
        if hasSharedPalette {
            sharedPaletteOffset = cursor
            pieces.append(.init(kind: .sharedPalette, offset: cursor, length: paletteByteCount))
            cursor += paletteByteCount
        }

        guard !pieces.isEmpty else { return nil }
        return Layout(
            offset: start,
            pieces: pieces,
            bannerFormat: bannerFormat,
            animationOrder: order,
            slots: slots,
            sharedPaletteOffset: sharedPaletteOffset
        )
    }

    /// True when Dolphin's frame walk would find fewer frames than
    /// libogc's — a live frame sits after a slot whose speed is zero.
    /// Such a save is malformed; no real one in the corpus is.
    public static func frameWalkIsAmbiguous(header: GCIFile.Header) -> Bool {
        var sawDeadSlot = false
        for slot in 0..<maximumFrameCount {
            let format = Int((header.iconFmt >> (2 * slot)) & 0b11)
            let speed = Int((header.animSpeed >> (2 * slot)) & 0b11)
            if speed == 0 {
                sawDeadSlot = true
            } else if sawDeadSlot && format != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Contents

    public let layout: Layout
    public let banner: Image?
    public let frames: [Frame]
    public let sharedPalette: [GXColor]?

    public init(layout: Layout, banner: Image?, frames: [Frame], sharedPalette: [GXColor]?) {
        self.layout = layout
        self.banner = banner
        self.frames = frames
        self.sharedPalette = sharedPalette
    }

    public var bannerFormat: BannerFormat { layout.bannerFormat }
    public var animationOrder: AnimationOrder { layout.animationOrder }

    // MARK: - Decoding

    /// Decode the image block out of a save body.
    public static func decode(body: GoDData, header: GCIFile.Header) throws -> CardImageBlock? {
        guard let layout = layout(header: header) else { return nil }
        guard layout.end <= body.length else {
            throw CardImageBlockError.blockOutOfBounds(end: layout.end, bodyLength: body.length, .init())
        }

        let decoder = GXTextureDecoder()

        var sharedPalette: [GXColor]?
        if let offset = layout.sharedPaletteOffset {
            guard let palette = decoder.decodePalette(
                data: body, offset: offset, entries: paletteEntryCount, format: .RGB5A3
            ) else {
                throw CardImageBlockError.paletteDecodeFailed(offset: offset, .init())
            }
            sharedPalette = palette
        }

        var banner: Image?
        var frames: [Frame] = []

        for piece in layout.pieces {
            switch piece.kind {
            case .banner:
                banner = try decodeImage(
                    body: body,
                    offset: piece.offset,
                    width: bannerWidth,
                    height: bannerHeight,
                    paletted: layout.bannerFormat == .ci8,
                    inlinePalette: layout.bannerFormat == .ci8,
                    sharedPalette: nil,
                    decoder: decoder
                )
            case let .frame(slot):
                let (format, speed) = layout.slots[slot]
                let image = try decodeImage(
                    body: body,
                    offset: piece.offset,
                    width: iconWidth,
                    height: iconHeight,
                    paletted: format.isPaletted,
                    inlinePalette: format == .ci8UniquePalette,
                    sharedPalette: format == .ci8SharedPalette ? sharedPalette : nil,
                    decoder: decoder
                )
                frames.append(Frame(slot: slot, format: format, speed: speed, image: image))
            case .sharedPalette:
                break
            }
        }

        return CardImageBlock(
            layout: layout,
            banner: banner,
            frames: frames,
            sharedPalette: sharedPalette
        )
    }

    /// Decodes one banner or frame. A paletted image's palette is either
    /// stored inline right after its pixels or supplied from the block's
    /// shared one.
    private static func decodeImage(
        body: GoDData,
        offset: Int,
        width: Int,
        height: Int,
        paletted: Bool,
        inlinePalette: Bool,
        sharedPalette: [GXColor]?,
        decoder: GXTextureDecoder
    ) throws -> Image {
        guard paletted else {
            guard let image = decoder.decodeTiledDirect(
                data: body, offset: offset, width: width, height: height, format: .RGB5A3
            ) else {
                throw CardImageBlockError.imageDecodeFailed(offset: offset, .init())
            }
            return .direct(image)
        }

        guard let indices = decoder.decodeTiledIndices(
            data: body, offset: offset, width: width, height: height, format: .C8
        ) else {
            throw CardImageBlockError.imageDecodeFailed(offset: offset, .init())
        }

        let palette: [GXColor]
        if inlinePalette {
            let paletteOffset = offset + width * height
            guard let inline = decoder.decodePalette(
                data: body, offset: paletteOffset, entries: paletteEntryCount, format: .RGB5A3
            ) else {
                throw CardImageBlockError.paletteDecodeFailed(offset: paletteOffset, .init())
            }
            palette = inline
        } else if let shared = sharedPalette {
            palette = shared
        } else {
            throw CardImageBlockError.missingSharedPalette(offset: offset, .init())
        }

        return .paletted(indices: indices, palette: palette)
    }

    // MARK: - Encoding

    /// Re-encode the block to the bytes it occupies in the body.
    ///
    /// Shared-palette frames are checked against the block's one shared
    /// palette first. A frame whose palette drifted — most likely an
    /// edited PNG that rebuilt its own — is an error rather than a
    /// silently-picked winner, because whichever copy were chosen would
    /// recolor the other frames.
    public func encoded() throws -> GoDData {
        let encoder = GXTextureDecoder()
        var bytes = [UInt8](repeating: 0, count: layout.length)

        for frame in frames where frame.format == .ci8SharedPalette {
            guard let palette = frame.image.palette else { continue }
            guard let shared = sharedPalette else {
                throw CardImageBlockError.missingSharedPalette(offset: layout.offset, .init())
            }
            guard palette == shared else {
                throw CardImageBlockError.sharedPaletteMismatch(slot: frame.slot, .init())
            }
        }

        for piece in layout.pieces {
            let encoded: [UInt8]
            switch piece.kind {
            case .banner:
                guard let banner else {
                    throw CardImageBlockError.missingBanner(.init())
                }
                encoded = try encodeImage(
                    banner,
                    width: Self.bannerWidth,
                    height: Self.bannerHeight,
                    inlinePalette: layout.bannerFormat == .ci8,
                    encoder: encoder
                )
            case let .frame(slot):
                guard let frame = frames.first(where: { $0.slot == slot }) else {
                    throw CardImageBlockError.missingFrame(slot: slot, .init())
                }
                encoded = try encodeImage(
                    frame.image,
                    width: Self.iconWidth,
                    height: Self.iconHeight,
                    inlinePalette: frame.format == .ci8UniquePalette,
                    encoder: encoder
                )
            case .sharedPalette:
                guard let sharedPalette else {
                    throw CardImageBlockError.missingSharedPalette(offset: piece.offset, .init())
                }
                encoded = encoder.encodePalette(sharedPalette, format: .RGB5A3)
            }

            guard encoded.count == piece.length else {
                throw CardImageBlockError.encodedLengthMismatch(
                    expected: piece.length, actual: encoded.count, .init()
                )
            }
            let start = piece.offset - layout.offset
            bytes.replaceSubrange(start..<(start + encoded.count), with: encoded)
        }

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func encodeImage(
        _ image: Image,
        width: Int,
        height: Int,
        inlinePalette: Bool,
        encoder: GXTextureDecoder
    ) throws -> [UInt8] {
        switch image {
        case let .direct(decoded):
            guard decoded.width == width, decoded.height == height else {
                throw CardImageBlockError.imageSizeMismatch(
                    expected: "\(width)x\(height)",
                    actual: "\(decoded.width)x\(decoded.height)", .init()
                )
            }
            guard let bytes = encoder.encodeTiledDirect(image: decoded, format: .RGB5A3) else {
                throw CardImageBlockError.imageEncodeFailed(.init())
            }
            return bytes

        case let .paletted(indices, palette):
            guard indices.count == width * height else {
                throw CardImageBlockError.imageSizeMismatch(
                    expected: "\(width * height) indices",
                    actual: "\(indices.count)", .init()
                )
            }
            guard let pixels = encoder.encodeTiledIndices(
                indices, width: width, height: height, format: .C8
            ) else {
                throw CardImageBlockError.imageEncodeFailed(.init())
            }
            guard inlinePalette else { return pixels }
            return pixels + encoder.encodePalette(palette, format: .RGB5A3)
        }
    }
}

/// The image-field enums are `Int`-raw because that is what the
/// directory entry stores, but they serialize as their case names: a
/// manifest is read by people, and `"format": 1` says nothing while
/// `"format": "ci8SharedPalette"` says what the frame is.
protocol CardFieldEnum: RawRepresentable, CaseIterable, Codable where RawValue == Int {}

extension CardFieldEnum {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let match = Self.allCases.first(where: { "\($0)" == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown value '\(name)'"
            )
        }
        self = match
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(self)")
    }
}

extension CardImageBlock.BannerFormat: CardFieldEnum {}
extension CardImageBlock.IconFormat: CardFieldEnum {}
extension CardImageBlock.AnimationSpeed: CardFieldEnum {}

public enum CardImageBlockError: Error, CustomStringConvertible {
    case blockOutOfBounds(end: Int, bodyLength: Int, ErrorTrace)
    case imageDecodeFailed(offset: Int, ErrorTrace)
    case paletteDecodeFailed(offset: Int, ErrorTrace)
    case missingSharedPalette(offset: Int, ErrorTrace)
    case sharedPaletteMismatch(slot: Int, ErrorTrace)
    case missingBanner(ErrorTrace)
    case missingFrame(slot: Int, ErrorTrace)
    case imageEncodeFailed(ErrorTrace)
    case imageSizeMismatch(expected: String, actual: String, ErrorTrace)
    case encodedLengthMismatch(expected: Int, actual: Int, ErrorTrace)
    case pngNotIndexed(ErrorTrace)
    case pngDecodeFailed(ErrorTrace)
    case pngEncodeFailed(filename: String, ErrorTrace)
    case paletteTooLarge(entries: Int, maximum: Int, ErrorTrace)
    case missingArtifact(filename: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .blockOutOfBounds(end, bodyLength, trace):
            return "Card image block ends at \(end) but the save body is only \(bodyLength) bytes\n\(trace)"
        case let .imageDecodeFailed(offset, trace):
            return "Failed to decode card image at \(offset)\n\(trace)"
        case let .paletteDecodeFailed(offset, trace):
            return "Failed to decode card palette at \(offset)\n\(trace)"
        case let .missingSharedPalette(offset, trace):
            return "Card image at \(offset) needs the shared palette, which is absent\n\(trace)"
        case let .sharedPaletteMismatch(slot, trace):
            return """
                Icon frame \(slot) carries a different palette from the other \
                shared-palette frames. Every shared-palette frame has to agree, \
                since only one palette is stored.
                \(trace)
                """
        case let .missingBanner(trace):
            return "Card image block declares a banner but none was supplied\n\(trace)"
        case let .missingFrame(slot, trace):
            return "Card image block declares icon frame \(slot) but none was supplied\n\(trace)"
        case let .imageEncodeFailed(trace):
            return "Failed to encode a card image\n\(trace)"
        case let .imageSizeMismatch(expected, actual, trace):
            return "Card image should be \(expected) but is \(actual)\n\(trace)"
        case let .encodedLengthMismatch(expected, actual, trace):
            return "Re-encoded card image piece is \(actual) bytes, expected \(expected)\n\(trace)"
        case let .pngNotIndexed(trace):
            return """
                This card image is paletted, so its PNG has to be an indexed \
                one. An RGBA PNG can't say which index held which color, and \
                re-indexing it would rebuild a different palette.
                \(trace)
                """
        case let .pngDecodeFailed(trace):
            return "Failed to decode a card image PNG\n\(trace)"
        case let .pngEncodeFailed(filename, trace):
            return "Failed to encode card image '\(filename)' as PNG\n\(trace)"
        case let .paletteTooLarge(entries, maximum, trace):
            return "Card image palette has \(entries) entries, at most \(maximum) fit\n\(trace)"
        case let .missingArtifact(filename, trace):
            return "Card image artifact '\(filename)' is missing\n\(trace)"
        }
    }
}
