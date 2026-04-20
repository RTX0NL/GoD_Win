//
//  ATXFile.swift
//
//  High-level ATX (animated texture) representation. Exposes each sprite
//  in the inner texture sheet as an individual PNG frame, so the outputs
//  layout is edit-friendly: you can add or remove frames, rename them,
//  replace their pixels, and the rebuild will pack everything into a new
//  sheet and emit a fresh binary.
//
//  Filenames incorporate a user-visible base name (e.g. "absol") so when
//  many ATX files share an output folder, their artifacts don't collide.
//  The default name is "atx"; set `name` before reading `outputs` or
//  construct via the convenience init(binary:name:) to choose a stem.
//
//  Output layout (all in one folder, no nesting):
//
//      <name>.atx.json
//      <name>_frame_000.png
//      <name>_frame_001.png
//      ...
//
//  File survey of 836 XD poke_dance ATX files: every frame is a single
//  sprite rect (count=1), the 16 trailing bytes of each 28-byte record
//  are always zero, the trailing section after the inner texture is
//  always empty, and 92% of files use the same (xOffset, yOffset) on
//  every frame. The JSON stores offsets at the top level with
//  per-frame overrides for the 8% that differ.
//

import Foundation
import GoDFoundation
import GTX

public struct ATXFile: FileFormat {
    public static let formatName = "atx"

    /// Base name for the emitted artifacts. Set this before reading
    /// `outputs` if you want the filenames to reflect the source file's
    /// name (e.g. "absol" → "absol.atx.json", "absol_frame_000.png").
    /// init(outputs:) recovers it from the JSON key.
    public var name: String = "atx"

    /// Screen-space anchor shared by every frame (Genius-Sonority-specific:
    /// typically something like (-32, -64) to center a 64×64 sprite on the
    /// bottom-middle of the character's position). Individual frames may
    /// override via `frameOverrides`.
    public var xOffset: Int16
    public var yOffset: Int16

    /// Per-frame offset overrides, indexed by frame filename. Empty for
    /// the 92% of files where every frame shares the same anchor.
    public var frameOverrides: [File: FrameOverride]

    /// Decoded sprite frames, in order. The PNG sidecar for each lives at
    /// `<name>_frame_NNN.png`.
    public var framePixels: [GoDImage]

    public var textureFormat: GXTextureFormat
    public var paletteFormat: GXPaletteFormat?
    public var animations: [Animation]

    public init(
        name: String = "atx",
        textureFormat: GXTextureFormat,
        paletteFormat: GXPaletteFormat?,
        xOffset: Int16,
        yOffset: Int16,
        frameOverrides: [File: FrameOverride] = [:],
        framePixels: [GoDImage],
        animations: [Animation]
    ) {
        self.name = name
        self.textureFormat = textureFormat
        self.paletteFormat = paletteFormat
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.frameOverrides = frameOverrides
        self.framePixels = framePixels
        self.animations = animations
    }

    public struct FrameOverride: Codable, Equatable {
        public var xOffset: Int16?
        public var yOffset: Int16?
        public init(xOffset: Int16? = nil, yOffset: Int16? = nil) {
            self.xOffset = xOffset
            self.yOffset = yOffset
        }
    }

    public struct AnimationStep: Codable, Equatable {
        /// When set, wait this many ticks before advancing (bit 30).
        public var timing: UInt8?
        /// When set, switch to this frame file (bit 31).
        public var frame: File?
        /// When set, overrides the displayed sprite's width (bit 29).
        public var rectWidth: UInt8?
        /// When set, overrides the displayed sprite's height (bit 29).
        public var rectHeight: UInt8?
        /// When set, this step ends the animation by looping back to the
        /// byte position in the stream identified by `loopTarget` (bit 28).
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

    // MARK: - Derived artifact filenames

    /// Name of the PNG for the given frame index, e.g. `absol_frame_002.png`.
    public func framePNGName(index: Int) -> File {
        File("\(name)_frame_\(String(format: "%03d", index)).png")
    }

    /// Regex-light matcher for frame PNG filenames belonging to this file.
    private static func parseFrameIndex(_ path: String, prefix: String) -> Int? {
        guard path.hasPrefix(prefix), path.hasSuffix(".png") else { return nil }
        let middle = path.dropFirst(prefix.count).dropLast(".png".count)
        return Int(middle)
    }

    // MARK: - Binary

    public init(binary: GoDData) throws {
        try self.init(binary: binary, name: "atx")
    }

    public init(binary: GoDData, name: String) throws {
        let decoder = GXTextureDecoder()
        guard let decoded = decoder.decodeATX(data: binary) else {
            throw ATXFile.invalidFileError
        }
        let meta = decoded.metadata
        let sheet = decoded.image

        // Parsing of the frame table is bounded by the max frameDelta
        // referenced in animations — the frame-table footer is zero-padded
        // slack that sometimes looks like valid header entries.
        let maxReferencedIndex = meta.animations
            .flatMap { $0.frames.compactMap { $0.frameDelta } }
            .map { Int($0) }
            .max() ?? -1
        let frameCount = maxReferencedIndex + 1

        let spriteRects = try ATXFile.parseFrameTable(meta.frameTable, expectedCount: frameCount)

        // Default offset: the mode across all frames. Most files have the
        // same value for every frame; record per-frame overrides for the
        // ones that don't match the default.
        let (defaultXY, overrides) = ATXFile.pickDefaultOffsets(
            spriteRects: spriteRects,
            name: name
        )

        var pixels = [GoDImage]()
        pixels.reserveCapacity(spriteRects.count)
        for rect in spriteRects {
            pixels.append(ATXFile.crop(sheet, rect: rect))
        }

        // Rewrite animation frameDelta → frame filename reference.
        let animations: [Animation] = meta.animations.map { wireAnim in
            Animation(steps: wireAnim.frames.map { wf -> AnimationStep in
                var frameFile: File? = nil
                if let idx = wf.frameDelta.map({ Int($0) }), idx >= 0, idx < frameCount {
                    let prefix = "\(name)_frame_"
                    frameFile = File("\(prefix)\(String(format: "%03d", idx)).png")
                }
                return AnimationStep(
                    timing: wf.timing,
                    frame: frameFile,
                    rectWidth: wf.rectWidth,
                    rectHeight: wf.rectHeight,
                    loopTarget: wf.loopTarget
                )
            })
        }

        self.init(
            name: name,
            textureFormat: meta.texture.format,
            paletteFormat: meta.texture.paletteFormat,
            xOffset: defaultXY.x,
            yOffset: defaultXY.y,
            frameOverrides: overrides,
            framePixels: pixels,
            animations: animations
        )
    }

    public var binaryData: GoDData {
        get throws {
            guard !framePixels.isEmpty else {
                throw FileFormatErrors.failedToEncode(
                    format: ATXFile.formatName,
                    target: "at least one frame is required"
                )
            }

            // 1. Pack frame pixels into a fresh sheet.
            let packed = try ATXFile.packFrames(framePixels)

            // 2. Compute per-frame (xOffset, yOffset) using defaults + overrides.
            var xyOffsets: [(Int16, Int16)] = []
            xyOffsets.reserveCapacity(framePixels.count)
            for i in 0..<framePixels.count {
                let key = framePNGName(index: i)
                if let ov = frameOverrides[key] {
                    xyOffsets.append((ov.xOffset ?? xOffset, ov.yOffset ?? yOffset))
                } else {
                    xyOffsets.append((xOffset, yOffset))
                }
            }

            // 3. Build the frame-table bytes.
            let frameTableBytes = ATXFile.buildFrameTable(
                rects: packed.rects,
                xyOffsets: xyOffsets
            )

            // 4. Translate animations → ATXAnimation wire form. Resolve
            //    each step's `frame` filename back to the frame index.
            let filenameToIndex: [File: Int] = Dictionary(
                uniqueKeysWithValues: (0..<framePixels.count).map {
                    (framePNGName(index: $0), $0)
                }
            )
            var wireAnimations = [ATXAnimation]()
            var cursor = 0x10 + animations.count * 2
            for animation in animations {
                var wireFrames = [ATXFrame]()
                wireFrames.reserveCapacity(animation.steps.count)
                for step in animation.steps {
                    var frameDelta: UInt8? = nil
                    if let f = step.frame {
                        guard let idx = filenameToIndex[f] else {
                            throw FileFormatErrors.failedToEncode(
                                format: ATXFile.formatName,
                                target: "unknown frame reference '\(f.path)'"
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

            // 5. Build the inner GTX texture from the packed sheet.
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

            guard let out = decoder.encodeATX(image: packed.image, metadata: metadata) else {
                throw ATXFile.failedToEncodeError(target: "atx")
            }
            return out
        }
    }

    // MARK: - Outputs / JSON

    public init(outputs: [File: GoDData]) throws {
        // Recover the name stem from whichever *.atx.json key is present.
        let suffix = ".\(ATXFile.formatName).json"
        guard let jsonKey = outputs.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw ATXFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard !stem.isEmpty else {
            throw ATXFile.invalidFileError
        }

        let jsonData = outputs[jsonKey]!
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw ATXFile.invalidFileError
        }

        // Gather frame PNGs for this stem. Sorted alphabetically — zero-
        // padded indices guarantee sort order = frame order.
        let framePrefix = "\(stem)_frame_"
        let frameKeys: [(index: Int, key: File)] = outputs.keys.compactMap { k in
            guard let idx = ATXFile.parseFrameIndex(k.path, prefix: framePrefix) else { return nil }
            return (idx, k)
        }.sorted { $0.index < $1.index }

        guard !frameKeys.isEmpty else {
            throw ATXFile.missingOutputError(key: "\(framePrefix)NNN.png")
        }

        var framePixels = [GoDImage]()
        framePixels.reserveCapacity(frameKeys.count)
        for (_, key) in frameKeys {
            guard let png = outputs[key] else {
                throw ATXFile.missingOutputError(key: key.path)
            }
            guard let image = GoDImage.fromPNG(png) else {
                throw ATXFile.invalidFileError
            }
            framePixels.append(image)
        }

        let overrides: [File: FrameOverride] = Dictionary(
            uniqueKeysWithValues: dto.frameOverrides.map { override in
                (File(override.frame), FrameOverride(
                    xOffset: override.xOffset,
                    yOffset: override.yOffset
                ))
            }
        )

        self.init(
            name: stem,
            textureFormat: dto.textureFormat,
            paletteFormat: dto.paletteFormat,
            xOffset: dto.xOffset,
            yOffset: dto.yOffset,
            frameOverrides: overrides,
            framePixels: framePixels,
            animations: dto.animations.map { Animation(steps: $0.steps) }
        )
    }

    public var outputs: [File: GoDData] {
        get throws {
            var overridesDTO = [FrameOverrideDTO]()
            for (file, ov) in frameOverrides.sorted(by: { $0.key.path < $1.key.path }) {
                overridesDTO.append(FrameOverrideDTO(
                    frame: file.path,
                    xOffset: ov.xOffset,
                    yOffset: ov.yOffset
                ))
            }

            let dto = DTO(
                textureFormat: textureFormat,
                paletteFormat: paletteFormat,
                xOffset: xOffset,
                yOffset: yOffset,
                frameOverrides: overridesDTO,
                animations: animations.map { AnimationDTO(steps: $0.steps) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)

            var artifacts: [File: GoDData] = [
                jsonFilename: GoDData(data: jsonData, byteOrder: .big)
            ]
            for (i, image) in framePixels.enumerated() {
                guard let png = image.pngData() else {
                    throw ATXFile.failedToEncodeError(target: "PNG for frame \(i)")
                }
                artifacts[framePNGName(index: i)] = png
            }
            return artifacts
        }
    }

    // MARK: - DTOs

    private struct DTO: Codable {
        let textureFormat: GXTextureFormat
        let paletteFormat: GXPaletteFormat?
        let xOffset: Int16
        let yOffset: Int16
        let frameOverrides: [FrameOverrideDTO]
        let animations: [AnimationDTO]
    }

    private struct FrameOverrideDTO: Codable {
        let frame: String
        let xOffset: Int16?
        let yOffset: Int16?
    }

    private struct AnimationDTO: Codable {
        let steps: [AnimationStep]
    }

    // MARK: - Frame-table parsing

    struct SpriteRect {
        let s: UInt16
        let t: UInt16
        let width: UInt16
        let height: UInt16
        let xOffset: Int16
        let yOffset: Int16
    }

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

    /// Picks the most common (xOffset, yOffset) across the sprite rects as
    /// the default, and records per-frame overrides for anything that
    /// differs.
    private static func pickDefaultOffsets(
        spriteRects: [SpriteRect],
        name: String
    ) -> (default: (x: Int16, y: Int16), overrides: [File: FrameOverride]) {
        if spriteRects.isEmpty { return ((0, 0), [:]) }
        // Encode (x, y) as Int32 for hashability.
        var histogram: [Int32: Int] = [:]
        func encode(_ x: Int16, _ y: Int16) -> Int32 {
            Int32(UInt16(bitPattern: x)) << 16 | Int32(UInt16(bitPattern: y))
        }
        func decode(_ v: Int32) -> (Int16, Int16) {
            (Int16(bitPattern: UInt16(truncatingIfNeeded: v >> 16)),
             Int16(bitPattern: UInt16(truncatingIfNeeded: v & 0xFFFF)))
        }
        for rect in spriteRects {
            histogram[encode(rect.xOffset, rect.yOffset), default: 0] += 1
        }
        let modeEncoded = histogram.max(by: { $0.value < $1.value })?.key ?? 0
        let (modeX, modeY) = decode(modeEncoded)

        var overrides: [File: FrameOverride] = [:]
        let prefix = "\(name)_frame_"
        for (i, rect) in spriteRects.enumerated() {
            if rect.xOffset == modeX && rect.yOffset == modeY { continue }
            let key = File("\(prefix)\(String(format: "%03d", i)).png")
            overrides[key] = FrameOverride(
                xOffset: rect.xOffset != modeX ? rect.xOffset : nil,
                yOffset: rect.yOffset != modeY ? rect.yOffset : nil
            )
        }
        return ((modeX, modeY), overrides)
    }

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

    private static func packFrames(_ frames: [GoDImage]) throws -> (image: GoDImage, rects: [SpriteRect]) {
        guard !frames.isEmpty else {
            throw FileFormatErrors.failedToEncode(format: formatName, target: "no frames to pack")
        }
        let sheetW = frames.map { $0.width }.max() ?? 0
        let sheetH = frames.map { $0.height }.reduce(0, +)
        guard sheetW > 0 && sheetH > 0 else {
            throw FileFormatErrors.failedToEncode(format: formatName, target: "zero-size sheet")
        }

        var sheetPixels = [UInt8](repeating: 0, count: sheetW * sheetH * 4)
        var rects: [SpriteRect] = []
        rects.reserveCapacity(frames.count)
        var yCursor = 0
        for frame in frames {
            let w = frame.width
            let h = frame.height
            let src = frame.pixels.rawBytes
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
                xOffset: 0,  // filled in by caller
                yOffset: 0
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

    /// Lays out N header entries (count=1 each) followed by N 28-byte records.
    private static func buildFrameTable(rects: [SpriteRect], xyOffsets: [(Int16, Int16)]) -> [UInt8] {
        let n = rects.count
        let headerSize = n * 4
        let recordsStart = headerSize
        var out = [UInt8](repeating: 0, count: headerSize + n * 28)
        for (i, rect) in rects.enumerated() {
            let relOff = recordsStart + i * 28
            out[i*4 + 0] = 0x00
            out[i*4 + 1] = 0x01
            out[i*4 + 2] = UInt8((relOff >> 8) & 0xFF)
            out[i*4 + 3] = UInt8(relOff & 0xFF)
            let r = relOff
            let (xOff, yOff) = xyOffsets[i]
            let xOffU = UInt16(bitPattern: xOff)
            let yOffU = UInt16(bitPattern: yOff)
            out[r +  0] = UInt8((rect.s      >> 8) & 0xFF); out[r +  1] = UInt8(rect.s & 0xFF)
            out[r +  2] = UInt8((rect.t      >> 8) & 0xFF); out[r +  3] = UInt8(rect.t & 0xFF)
            out[r +  4] = UInt8((rect.width  >> 8) & 0xFF); out[r +  5] = UInt8(rect.width & 0xFF)
            out[r +  6] = UInt8((rect.height >> 8) & 0xFF); out[r +  7] = UInt8(rect.height & 0xFF)
            out[r +  8] = UInt8((xOffU       >> 8) & 0xFF); out[r +  9] = UInt8(xOffU & 0xFF)
            out[r + 10] = UInt8((yOffU       >> 8) & 0xFF); out[r + 11] = UInt8(yOffU & 0xFF)
        }
        return out
    }
}
