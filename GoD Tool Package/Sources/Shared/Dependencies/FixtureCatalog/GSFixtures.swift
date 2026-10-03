//
//  GSFixtures.swift
//
//  Genius Sonority format fixtures: GTX, ATX, GSW, GSFont, ISF, THP.
//  Each is a deterministic path-exercising model whose reader-canonicalised
//  serialization is frozen as the golden.
//

import Foundation
import GoDFoundation
import GeniusSonority
import GTX

// MARK: - GTX

public enum GTXFixtures {
    public static let name = "gtx_rgba32"

    /// A 4×4 RGBA32 image with a deterministic gradient (every channel and
    /// a range of values, so the codec path isn't exercised on a constant).
    public static func model() -> GTXFile {
        var rgba: [UInt8] = []
        rgba.reserveCapacity(16 * 4)
        for i in 0..<16 {
            let r = UInt8(truncatingIfNeeded: i &* 16)
            let g = UInt8(truncatingIfNeeded: 255 &- i &* 12)
            let b = UInt8(truncatingIfNeeded: i &* 7)
            rgba.append(contentsOf: [r, g, b, 0xFF])
        }
        return GTXFile(
            image: GoDImage(width: 4, height: 4,
                            pixels: GoDData(byteStream: rgba, byteOrder: .big)),
            format: .RGBA32,
            paletteFormat: nil,
            name: name
        )
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

// MARK: - ATX

public enum ATXFixtures {
    public static let name = "atx_sample"

    private static func frame(seed: UInt32) -> GoDImage {
        GoDImage(width: 4, height: 4,
                 pixels: GoDData(byteStream: deterministicBytes(4 * 4 * 4, seed: seed),
                                 byteOrder: .big))
    }

    /// Two RGBA32 frames (lossless → deterministic repack) and one
    /// two-step animation.
    public static func model() -> ATXFile {
        let anim = ATXFile.Animation(steps: [
            ATXFile.AnimationStep(timing: 4, frame: File("\(name)_frame_000.png")),
            ATXFile.AnimationStep(timing: 6, frame: File("\(name)_frame_001.png")),
        ])
        return ATXFile(
            name: name,
            textureFormat: .RGBA32,
            paletteFormat: nil,
            xOffset: -32,
            yOffset: -64,
            framePixels: [frame(seed: 0x00F0_0000), frame(seed: 0x00F1_0000)],
            animations: [anim]
        )
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

// MARK: - GSW

public enum GSWFixtures {
    public static let name = "gsw_sample"

    /// Texture-free GSW: the header + opaque tag stream round-trip
    /// byte-identically. Small random payloads can't contain a texture
    /// header, so the file stays texture-free.
    public static func model() -> GSWFile {
        let tags = [
            GSWTag(code: 0x04, payload: Data(deterministicBytes(4, seed: 0x0000_0004))),
            GSWTag(code: 0x1A, payload: Data(deterministicBytes(8, seed: 0x0000_001A))),
        ]
        let tagDataSize = tags.reduce(0) { $0 + 8 + $1.payload.count }

        let header = GSWHeader(
            version: 7,
            canvasWidthTwips: 0x1000,
            canvasHeightTwips: 0x0C00,
            tagDataSize: UInt32(tagDataSize),
            unknown_0x0C: 0,
            frameRate: 0x3200,
            unknown_0x10: 0x2580,
            unknown_0x14: 0,
            spriteDepthCount: 1,
            characterCount: 0,
            padding_0x1C: Data(count: 16),
            unknown_0x2C: 0
        )
        var gsw = GSWFile(header: header, tags: tags, images: [])
        gsw.name = name
        return gsw
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

// MARK: - GSFont

public enum GSFontFixtures {
    public static let name = "fnt_sample"

    private static func glyph(code: UInt16, adv: UInt8, height: UInt8, seed: UInt32) -> GSFont.Glyph {
        let bytesPerRow = (Int(adv) + 1) / 2         // 4bpp, packed
        var bitmap = deterministicBytes(bytesPerRow * Int(height), seed: seed)
        // Odd-width rows have an unused low padding nibble in the last byte;
        // real fonts keep it 0 and the atlas can't represent it, so zero it
        // here to keep the atlas round-trip byte-exact.
        if Int(adv) % 2 == 1 {
            for row in 0..<Int(height) {
                bitmap[row * bytesPerRow + bytesPerRow - 1] &= 0xF0
            }
        }
        return GSFont.Glyph(code: code, advanceWidth: adv, height: height, flags: 0, bitmap: bitmap)
    }

    /// A primary block chained (via `nextFont`) to a smaller secondary
    /// block, exercising the multi-block font chain.
    public static func model() -> GSFont {
        let secondary = GSFont(
            fontId: 1, glyphWidth: 18, glyphHeight: 18,
            glyphs: [glyph(code: 0x43, adv: 9, height: 18, seed: 0x0043_0000)],
            nextFont: nil, blockPadding: []
        )
        var primary = GSFont(
            fontId: 0, glyphWidth: 22, glyphHeight: 22,
            glyphs: [
                glyph(code: 0x41, adv: 10, height: 22, seed: 0x0041_0000),
                glyph(code: 0x42, adv: 10, height: 22, seed: 0x0042_0000),
            ],
            nextFont: secondary, blockPadding: []
        )
        primary.name = name
        return primary
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

// MARK: - ISF

public enum ISFFixtures {
    public static let name = "isf_sample"

    /// A short stereo tone (two channels, distinct frequencies) so the
    /// interleave + per-channel coefficient paths are exercised.
    public static func model() -> ISFFile {
        let sampleCount = 256
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount * 2)
        for i in 0..<sampleCount {
            let t = Double(i)
            let left = 3000.0 * sin(2.0 * Double.pi * 5.0 * t / 64.0)
            let right = 2000.0 * sin(2.0 * Double.pi * 3.0 * t / 64.0)
            samples.append(Int16(left))
            samples.append(Int16(right))
        }
        return ISFFile(
            name: name,
            sampleRate: 8000,
            channelCount: 2,
            // The one creation date every real ISH carries, so the golden
            // manifest exercises the ISO spelling rather than `0x00000000`.
            creationDate: 0x2004_0109,
            samples: samples
        )
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

/// A looping stream, so the golden pair actually carries the three control
/// words. `isf_sample` has the non-looping defaults — loop flag clear,
/// loop start at nibble 2 — which is why it could not catch the writer
/// zeroing the stream end at 0x28.
public enum ISFLoopFixtures {
    public static let name = "isf_loop_sample"

    public static func model() -> ISFFile {
        var isf = ISFFixtures.model()
        isf.name = name
        // Deliberately mid-frame and all three distinct, mirroring the
        // shape of a real BGM: a short intro, then the loop body.
        isf.loop = ISFFile.Loop(enabled: true, startNibble: 131, endNibble: 4095)
        isf.streamEndNibble = 4093
        return isf
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}

// MARK: - THP

public enum THPFixtures {
    public static let name = "thp_sample"

    /// A THH header (≥ 0x30 bytes) with the frame-offset fields at 0x28 and
    /// 0x2C, so the pointer-fixup path is exercised on both concat and
    /// split. The first-frame field (0x28) is the offset of frame 0 into
    /// the THD, which is 0 (frame data begins at the start of the THD) —
    /// after the concat fixup it becomes the THH size, which
    /// `splitCombined` reads back to recover the split point.
    private static func makeTHH() -> GoDData {
        var b = deterministicBytes(0x40, seed: 0x7448_0000)  // "tH.."
        // firstFrameOffset = 0x00, lastFrameOffset = 0x40 (into THD)
        b[0x28] = 0x00; b[0x29] = 0x00; b[0x2A] = 0x00; b[0x2B] = 0x00
        b[0x2C] = 0x00; b[0x2D] = 0x00; b[0x2E] = 0x00; b[0x2F] = 0x40
        return GoDData(byteStream: b, byteOrder: .big)
    }

    public static func model() throws -> THPFile {
        let thd = GoDData(byteStream: deterministicBytes(0x80, seed: 0x7444_0000),
                          byteOrder: .big)
        return try THPFile(thh: makeTHH(), thd: thd, name: name)
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.colosseum)
    }
}
