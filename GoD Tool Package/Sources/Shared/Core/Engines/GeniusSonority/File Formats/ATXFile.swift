//
//  ATXFile.swift
//
//  High-level ATX (animated texture) representation. Exposes each sprite
//  in the inner texture sheet as an individual PNG frame, so the outputs
//  layout is edit-friendly: you can add or remove frames, rename them,
//  replace their pixels, and the rebuild will pack everything into a new
//  sheet and emit a fresh binary.
//
//  File survey (836 XD poke_dance ATX files): every frame is a single
//  sprite rect (count=1), the 16 trailing bytes of each 28-byte record
//  are always zero, and the trailing section after the inner texture is
//  always empty. Those facts let us drop a lot of declarative metadata
//  and compute it on rebuild.
//

import Foundation
import GoDFoundation
import GTX

public struct ATXFile: FileFormat {
    public static let formatName = "atx"
    public static let animationJSON = File("animation.json")

    /// One sprite frame in the ATX's frame table. Rebuild packs these into
    /// a fresh inner texture sheet (vertical strip) so the on-disc
    /// dimensions are whatever the frames dictate.
    public struct Frame {
        /// PNG filename (relative to the JSON file). Kept as `File` so the
        /// on-disc outputs dict key and the JSON reference agree.
        public var image: File
        public var xOffset: Int16
        public var yOffset: Int16
        /// Decoded pixels. Not persisted in JSON; reconstructed from the
        /// matching PNG artifact on init(outputs:).
        public var pixels: GoDImage

        public init(image: File, xOffset: Int16, yOffset: Int16, pixels: GoDImage) {
            self.image = image
            self.xOffset = xOffset
            self.yOffset = yOffset
            self.pixels = pixels
        }
    }

    /// One step in an animation's keyframe stream.
    public struct AnimationStep: Codable, Equatable {
        /// When set, wait this many ticks before advancing (bit 30).
        public var timing: UInt8?
        /// When set, switch to this frame file (bit 31). Indexes into the
        /// `frames` array at resolve time.
        public var frame: File?
        /// When set, overrides the displayed sprite's width (bit 29).
        public var rectWidth: UInt8?
        /// When set, overrides the displayed sprite's height (bit 29).
        public var rectHeight: UInt8?
        /// When set, this step ends the animation by looping back to the
        /// byte position in the stream identified by `loopTarget`
        /// (bit 28). Zero restarts the stream from the beginning.
        public var loopTarget: Int?

        public init(
            timing: UInt8? = nil,
            frame: File? = nil,
            rectWidth: UInt8? = nil,
            rectHeight: UInt8? = nil,
            loopTarget: Int? = nil
        ) {
            self.timing = timing
            self.frame = frame
            self.rectWidth = rectWidth
            self.rectHeight = rectHeight
            self.loopTarget = loopTarget
        }
    }

    public struct Animation: Codable, Equatable {
        public var steps: [AnimationStep]
        public init(steps: [AnimationStep]) { self.steps = steps }
    }

    public var textureFormat: GXTextureFormat
    public var paletteFormat: GXPaletteFormat?
    public var frames: [Frame]
    public var animations: [Animation]

    public init(
        textureFormat: GXTextureFormat,
        paletteFormat: GXPaletteFormat?,
        frames: [Frame],
        animations: [Animation]
    ) {
        self.textureFormat = textureFormat
        self.paletteFormat = paletteFormat
        self.frames = frames
        self.animations = animations
    }

    // MARK: - Binary

    public init(binary: GoDData) throws {
        let decoder = GXTextureDecoder()
        guard let decoded = decoder.decodeATX(data: binary) else {
            throw ATXFile.invalidFileError
        }
        let meta = decoded.metadata
        let sheet = decoded.image

        // Parse the frame table into sprite rect records. We treat count=1
        // as the contract — the asm supports count>1 compositing but no
        // observed XD file uses it, and splitting multi-sprite frames into
        // separate PNGs would lose the composition.
        //
        // The frame-table header is followed by zero-padded slack, and that
        // slack sometimes happens to look like valid (count=1) entries.
        // Cap the parse at the highest frame index any animation references.
        let maxReferencedIndex = meta.animations
            .flatMap { $0.frames.compactMap { $0.frameDelta } }
            .map { Int($0) }
            .max() ?? -1
        let frameCount = maxReferencedIndex + 1
        let spriteRects = try ATXFile.parseFrameTable(meta.frameTable, expectedCount: frameCount)

        // Crop each sprite rect out of the sheet into its own GoDImage.
        var frames: [Frame] = []
        frames.reserveCapacity(spriteRects.count)
        for (i, rect) in spriteRects.enumerated() {
            let pixels = ATXFile.crop(sheet, rect: rect)
            let fileName = "frame_\(String(format: "%03d", i)).png"
            frames.append(Frame(
                image: File(fileName),
                xOffset: rect.xOffset,
                yOffset: rect.yOffset,
                pixels: pixels
            ))
        }

        // Convert animations: replace `frameDelta` (index) with a filename.
        // The engine reads frameDelta as the absolute frame index (not an
        // increment) — verified in drawAndUpdate.s where it's stored
        // directly to CAnt+0x28 and used as `frameTable[frameDelta*4]`.
        let animations = meta.animations.map { animation -> Animation in
            Animation(steps: animation.frames.map { frame -> AnimationStep in
                let filename = frame.frameDelta.flatMap { idx -> File? in
                    let i = Int(idx)
                    guard i >= 0, i < frames.count else { return nil }
                    return frames[i].image
                }
                return AnimationStep(
                    timing: frame.timing,
                    frame: filename,
                    rectWidth: frame.rectWidth,
                    rectHeight: frame.rectHeight,
                    loopTarget: frame.loopTarget
                )
            })
        }

        self.init(
            textureFormat: meta.texture.format,
            paletteFormat: meta.texture.paletteFormat,
            frames: frames,
            animations: animations
        )
    }

    public var binaryData: GoDData {
        get throws {
            // 1. Pack all frame sprites into a fresh sheet image (vertical
            //    strip layout — matches the observed 64×(N*64) pattern for
            //    poke_dance files).
            let packed = try ATXFile.packFrames(frames)

            // 2. Build the frame table bytes: N header entries (count=1,
            //    relativeOffset), then N 28-byte records (s,t,w,h,xoff,yoff,
            //    + 16 zero bytes).
            let frameTableBytes = ATXFile.buildFrameTable(
                rects: packed.rects,
                xyOffsets: frames.map { ($0.xOffset, $0.yOffset) }
            )

            // 3. Translate animations back into the low-level ATXAnimation
            //    stream. AnimationStep.frame (filename) → frameDelta index.
            let filenameToIndex: [File: Int] = Dictionary(
                uniqueKeysWithValues: frames.enumerated().map { ($1.image, $0) }
            )
            var wireAnimations = [ATXAnimation]()
            var cursor = 0x10 + animations.count * 2
            for animation in animations {
                var wireFrames = [ATXFrame]()
                wireFrames.reserveCapacity(animation.steps.count)
                for step in animation.steps {
                    var frameDelta: UInt8? = nil
                    if let filename = step.frame {
                        guard let idx = filenameToIndex[filename] else {
                            throw FileFormatErrors.failedToEncode(
                                format: ATXFile.formatName,
                                target: "unknown frame reference '\(filename.path)'"
                            )
                        }
                        frameDelta = UInt8(clamping: idx)
                    }
                    wireFrames.append(ATXFrame(
                        timing: step.timing,
                        rectWidth: step.rectWidth,
                        rectHeight: step.rectHeight,
                        frameDelta: frameDelta,
                        loopTarget: step.loopTarget
                    ))
                }
                let animationStreamStart = cursor
                for frame in wireFrames { cursor += frame.byteLength }
                wireAnimations.append(ATXAnimation(
                    offset: animationStreamStart,
                    frames: wireFrames
                ))
            }
            let frameTableOffset = cursor
            let innerTextureOffset = frameTableOffset + frameTableBytes.count

            // 4. Build the inner GTX texture from the packed sheet.
            let gxMetadata = GXTextureMetadata(
                width: packed.image.width,
                height: packed.image.height,
                format: textureFormat,
                paletteFormat: paletteFormat
            )
            let decoder = GXTextureDecoder()
            guard let inner = decoder.encode(image: packed.image, metadata: gxMetadata) else {
                throw ATXFile.failedToEncodeError(target: "inner GTX texture")
            }

            let metadata = ATXMetadata(
                texture: gxMetadata,
                frameTableOffset: frameTableOffset,
                innerTextureSize: inner.length,
                innerTextureOffset: innerTextureOffset,
                animations: wireAnimations,
                frameTable: Data(frameTableBytes),
                trailing: Data()
            )

            // Pre-pack the ATXMetadata.frameTable already contains the final
            // bytes, so encodeATX just concatenates. The inner sheet goes
            // through `encode` again inside encodeATX — pass a placeholder
            // image that decodes from `packed.image` losslessly by using the
            // same encode path.
            guard let out = decoder.encodeATX(image: packed.image, metadata: metadata) else {
                throw ATXFile.failedToEncodeError(target: "atx")
            }
            return out
        }
    }

    // MARK: - Outputs / JSON

    public init(outputs: [File: GoDData]) throws {
        guard let jsonData = outputs[ATXFile.animationJSON] else {
            throw ATXFile.missingOutputError(key: ATXFile.animationJSON.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw ATXFile.invalidFileError
        }

        // Resolve each frame definition to (PNG bytes → GoDImage).
        var frames: [Frame] = []
        frames.reserveCapacity(dto.frames.count)
        for frameDTO in dto.frames {
            let imageKey = File(frameDTO.image)
            guard let pngData = outputs[imageKey] else {
                throw ATXFile.missingOutputError(key: frameDTO.image)
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw ATXFile.invalidFileError
            }
            frames.append(Frame(
                image: imageKey,
                xOffset: frameDTO.xOffset,
                yOffset: frameDTO.yOffset,
                pixels: image
            ))
        }

        let animations = dto.animations.map { Animation(steps: $0.steps) }

        self.init(
            textureFormat: dto.textureFormat,
            paletteFormat: dto.paletteFormat,
            frames: frames,
            animations: animations
        )
    }

    public var outputs: [File: GoDData] {
        get throws {
            let dto = DTO(
                textureFormat: textureFormat,
                paletteFormat: paletteFormat,
                frames: frames.map {
                    FrameDTO(image: $0.image.path, xOffset: $0.xOffset, yOffset: $0.yOffset)
                },
                animations: animations.map { AnimationDTO(steps: $0.steps) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)

            var artifacts: [File: GoDData] = [
                ATXFile.animationJSON: GoDData(data: jsonData, byteOrder: .big)
            ]
            for frame in frames {
                guard let png = frame.pixels.pngData() else {
                    throw ATXFile.failedToEncodeError(target: "PNG for \(frame.image.path)")
                }
                artifacts[frame.image] = png
            }
            return artifacts
        }
    }

    // MARK: - DTOs

    private struct DTO: Codable {
        let textureFormat: GXTextureFormat
        let paletteFormat: GXPaletteFormat?
        let frames: [FrameDTO]
        let animations: [AnimationDTO]
    }

    private struct FrameDTO: Codable {
        let image: String
        let xOffset: Int16
        let yOffset: Int16
    }

    private struct AnimationDTO: Codable {
        let steps: [AnimationStep]
    }

    // MARK: - Frame-table parsing

    /// One decoded sprite-rect record. We assume `count == 1` per the file
    /// survey; multi-sprite frames would need composite handling.
    struct SpriteRect {
        let s: UInt16
        let t: UInt16
        let width: UInt16
        let height: UInt16
        let xOffset: Int16
        let yOffset: Int16
    }

    /// Parses the first `expectedCount` header entries from `raw` and returns
    /// the sprite rects they reference. The bound is provided externally
    /// (derived from animation references) because the frame-table footer is
    /// zero-padded slack that occasionally happens to look like a valid
    /// header entry.
    private static func parseFrameTable(_ raw: Data, expectedCount: Int) throws -> [SpriteRect] {
        let bytes = [UInt8](raw)
        var rects: [SpriteRect] = []
        guard expectedCount > 0 else { return rects }
        for idx in 0..<expectedCount {
            let headerStart = idx * 4
            guard headerStart + 4 <= bytes.count else {
                throw FileFormatErrors.failedToEncode(
                    format: formatName,
                    target: "frame table header truncated at index \(idx)"
                )
            }
            let count = UInt16(bytes[headerStart]) << 8 | UInt16(bytes[headerStart + 1])
            let relOff = UInt16(bytes[headerStart + 2]) << 8 | UInt16(bytes[headerStart + 3])
            if count != 1 {
                throw FileFormatErrors.failedToEncode(
                    format: formatName,
                    target: "multi-sprite frames (count=\(count)) not yet supported"
                )
            }
            guard Int(relOff) + 28 <= bytes.count else {
                throw FileFormatErrors.failedToEncode(
                    format: formatName,
                    target: "frame \(idx) record offset 0x\(String(relOff, radix: 16)) out of bounds"
                )
            }
            let recordStart = Int(relOff)
            let s = UInt16(bytes[recordStart]) << 8 | UInt16(bytes[recordStart + 1])
            let t = UInt16(bytes[recordStart + 2]) << 8 | UInt16(bytes[recordStart + 3])
            let w = UInt16(bytes[recordStart + 4]) << 8 | UInt16(bytes[recordStart + 5])
            let h = UInt16(bytes[recordStart + 6]) << 8 | UInt16(bytes[recordStart + 7])
            let xRaw = UInt16(bytes[recordStart + 8]) << 8 | UInt16(bytes[recordStart + 9])
            let yRaw = UInt16(bytes[recordStart + 10]) << 8 | UInt16(bytes[recordStart + 11])
            rects.append(SpriteRect(
                s: s, t: t, width: w, height: h,
                xOffset: Int16(bitPattern: xRaw),
                yOffset: Int16(bitPattern: yRaw)
            ))
        }
        return rects
    }

    /// Crops a sprite rect out of the sheet image. Assumes RGBA8888 pixels.
    private static func crop(_ sheet: GoDImage, rect: SpriteRect) -> GoDImage {
        let srcW = sheet.width
        let srcBytes = sheet.pixels.rawBytes
        let w = Int(rect.width), h = Int(rect.height)
        let s = Int(rect.s), t = Int(rect.t)

        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let srcY = t + y
            guard srcY < sheet.height else { break }
            for x in 0..<w {
                let srcX = s + x
                guard srcX < srcW else { break }
                let src = (srcY * srcW + srcX) * 4
                let dst = (y * w + x) * 4
                out[dst]     = srcBytes[src]
                out[dst + 1] = srcBytes[src + 1]
                out[dst + 2] = srcBytes[src + 2]
                out[dst + 3] = srcBytes[src + 3]
            }
        }
        return GoDImage(
            width: w,
            height: h,
            pixels: GoDData(byteStream: out, byteOrder: .big)
        )
    }

    // MARK: - Rebuild

    /// Simple vertical-strip packer. Matches the observed layout for every
    /// poke_dance ATX (64×192 sheet = three 64×64 sprites stacked).
    private static func packFrames(_ frames: [Frame]) throws -> (image: GoDImage, rects: [SpriteRect]) {
        guard !frames.isEmpty else {
            throw FileFormatErrors.failedToEncode(format: formatName, target: "no frames to pack")
        }
        let sheetW = frames.map { $0.pixels.width }.max() ?? 0
        let sheetH = frames.map { $0.pixels.height }.reduce(0, +)
        guard sheetW > 0 && sheetH > 0 else {
            throw FileFormatErrors.failedToEncode(format: formatName, target: "zero-size sheet")
        }

        var sheetPixels = [UInt8](repeating: 0, count: sheetW * sheetH * 4)
        var rects: [SpriteRect] = []
        rects.reserveCapacity(frames.count)
        var yCursor = 0
        for frame in frames {
            let w = frame.pixels.width
            let h = frame.pixels.height
            let src = frame.pixels.pixels.rawBytes
            for y in 0..<h {
                let dstRow = (yCursor + y) * sheetW * 4
                let srcRow = y * w * 4
                for x in 0..<w {
                    sheetPixels[dstRow + x*4]     = src[srcRow + x*4]
                    sheetPixels[dstRow + x*4 + 1] = src[srcRow + x*4 + 1]
                    sheetPixels[dstRow + x*4 + 2] = src[srcRow + x*4 + 2]
                    sheetPixels[dstRow + x*4 + 3] = src[srcRow + x*4 + 3]
                }
            }
            rects.append(SpriteRect(
                s: 0,
                t: UInt16(yCursor),
                width: UInt16(w),
                height: UInt16(h),
                xOffset: frame.xOffset,
                yOffset: frame.yOffset
            ))
            yCursor += h
        }

        let sheet = GoDImage(
            width: sheetW,
            height: sheetH,
            pixels: GoDData(byteStream: sheetPixels, byteOrder: .big)
        )
        return (sheet, rects)
    }

    /// Lays out header entries (count=1 each, sequential relOffs) + 28-byte
    /// records in one contiguous blob.
    private static func buildFrameTable(rects: [SpriteRect], xyOffsets: [(Int16, Int16)]) -> [UInt8] {
        let n = rects.count
        let headerSize = n * 4
        let recordsStart = headerSize
        var out = [UInt8](repeating: 0, count: headerSize + n * 28)
        for (i, rect) in rects.enumerated() {
            let relOff = recordsStart + i * 28
            // Header entry
            out[i*4 + 0] = 0x00                         // count hi
            out[i*4 + 1] = 0x01                         // count lo = 1
            out[i*4 + 2] = UInt8((relOff >> 8) & 0xFF)
            out[i*4 + 3] = UInt8(relOff & 0xFF)
            // Record body (first 12 bytes; remaining 16 already zero)
            let r = relOff
            let (xOff, yOff) = xyOffsets[i]
            let xOffU = UInt16(bitPattern: xOff)
            let yOffU = UInt16(bitPattern: yOff)
            out[r +  0] = UInt8((rect.s       >> 8) & 0xFF); out[r +  1] = UInt8(rect.s & 0xFF)
            out[r +  2] = UInt8((rect.t       >> 8) & 0xFF); out[r +  3] = UInt8(rect.t & 0xFF)
            out[r +  4] = UInt8((rect.width   >> 8) & 0xFF); out[r +  5] = UInt8(rect.width & 0xFF)
            out[r +  6] = UInt8((rect.height  >> 8) & 0xFF); out[r +  7] = UInt8(rect.height & 0xFF)
            out[r +  8] = UInt8((xOffU        >> 8) & 0xFF); out[r +  9] = UInt8(xOffU & 0xFF)
            out[r + 10] = UInt8((yOffU        >> 8) & 0xFF); out[r + 11] = UInt8(yOffU & 0xFF)
        }
        return out
    }
}
