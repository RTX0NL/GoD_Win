import XCTest
import GoDFoundation
import GTX

final class GXTextureTests: XCTestCase {

    func testParseHeader() {
        var header = [UInt8](repeating: 0, count: 0x80)
        header[0] = 0x00; header[1] = 0x04
        header[2] = 0x00; header[3] = 0x04
        header[4] = 32
        header[0x0B] = 0x45
        header[0x28] = 0; header[0x29] = 0; header[0x2A] = 0; header[0x2B] = 0x80

        let data = GoDData(byteStream: header, byteOrder: .big)
        let decoder = GXTextureDecoder()
        let meta = decoder.parseHeader(data: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.width, 4)
        XCTAssertEqual(meta?.height, 4)
        XCTAssertEqual(meta?.format, .rgba32)
    }

    func testSimpleRGB() {
        var d = [UInt8](repeating: 0, count: 0xA0)
        d[1] = 4; d[3] = 4; d[4] = 16; d[0x0B] = 0x44; d[0x2B] = 0x80
        let data = GoDData(byteStream: d, byteOrder: .big)
        let decoder = GXTextureDecoder()
        let result = decoder.decode(data: data)
        XCTAssertNotNil(result)
    }

    /// Builds a minimal poke_dance-style ATX wrapper: 16-byte header + offset table +
    /// keyframe data + frame-rect table + inner GTX texture (4×4 RGBA32).
    /// Mirrors the layout we observe in real airmd.atx-style files.
    private func makeSyntheticATX() -> [UInt8] {
        // Inner texture: 4×4 RGBA32, header(0x80) + tex(64 bytes) = 0x80 + 0x40 = 0xC0
        var inner = [UInt8](repeating: 0, count: 0xC0)
        inner[0] = 0; inner[1] = 4              // width
        inner[2] = 0; inner[3] = 4              // height
        inner[4] = 32                            // bpp
        inner[0x0B] = 0x45                       // format = RGBA32
        inner[0x2B] = 0x80                       // texture pointer (offset 0x80)

        // Two animations, mirroring real samples:
        //   anim 0 (single-frame loop): flags=0x0B, timing=5, delta=0, jump=3 → loopTarget=0
        //   anim 1 (two frames + loop):
        //     frame 1: flags=0x03 (timing+delta), timing=7, delta=0
        //     frame 2: flags=0x0F (all four), timing=7, rectW=2, rectH=3, delta=1, jump=8 → loopTarget=0
        //              (exercises the bit-29 rect path that real samples don't cover)
        //   plus 1 byte of zero padding before the frameTable, like real files
        let keyframes: [UInt8] = [
            0x0B, 0x05, 0x00, 0x03,                  // anim 0 @ stream offset 0
            0x03, 0x07, 0x00,                        // anim 1 frame 1 @ stream offset 4
            0x0F, 0x07, 0x02, 0x03, 0x01, 0x08,      // anim 1 frame 2 @ stream offset 7
            0x00                                      // padding before frameTable
        ]
        let frameTable: [UInt8] = [
            0x00, 0x01, 0x00, 0x10, 0x00, 0x01, 0x00, 0x18,
            0x00, 0x40, 0x00, 0x40, 0xff, 0xe0, 0xff, 0xc0
        ]

        let animationCount = 2
        let offsetTableEnd = 0x10 + animationCount * 2                // 0x14
        let keyframeStart = offsetTableEnd                            // 0x14
        let frameTableOffset = keyframeStart + keyframes.count        // 0x14 + 0x0E = 0x22
        let innerTextureOffset = frameTableOffset + frameTable.count  // 0x22 + 0x10 = 0x32
        let innerTextureSize = inner.count                            // 0xC0

        var bytes = [UInt8]()
        for v in [UInt32(animationCount), UInt32(frameTableOffset), UInt32(innerTextureSize), UInt32(innerTextureOffset)] {
            bytes.append(UInt8((v >> 24) & 0xFF))
            bytes.append(UInt8((v >> 16) & 0xFF))
            bytes.append(UInt8((v >>  8) & 0xFF))
            bytes.append(UInt8(v & 0xFF))
        }
        let animOffsets: [UInt16] = [UInt16(keyframeStart), UInt16(keyframeStart + 4)]
        for off in animOffsets {
            bytes.append(UInt8((off >> 8) & 0xFF))
            bytes.append(UInt8(off & 0xFF))
        }
        bytes.append(contentsOf: keyframes)
        bytes.append(contentsOf: frameTable)
        bytes.append(contentsOf: inner)
        return bytes
    }

    func testATXParsesStructuredFields() {
        let raw = makeSyntheticATX()
        let data = GoDData(byteStream: raw, byteOrder: .big)
        let decoder = GXTextureDecoder()

        guard let (image, meta) = decoder.decodeATX(data: data) else {
            XCTFail("decodeATX returned nil"); return
        }

        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)
        XCTAssertEqual(meta.animationCount, 2)
        XCTAssertEqual(meta.frameTableOffset, 0x22)
        XCTAssertEqual(meta.innerTextureSize, 0xC0)
        XCTAssertEqual(meta.innerTextureOffset, 0x32)
        XCTAssertEqual(meta.frameTable.count, 16)
        XCTAssertEqual(meta.trailing.count, 0)
        XCTAssertEqual(meta.texture.format, .rgba32)

        XCTAssertEqual(meta.animations.count, 2)
        XCTAssertEqual(meta.animations[0].offset, 0x14)
        XCTAssertEqual(meta.animations[0].frames, [
            ATXFrame(timing: 5, frameDelta: 0, loopTarget: 0)
        ])
        XCTAssertEqual(meta.animations[1].offset, 0x18)
        XCTAssertEqual(meta.animations[1].frames, [
            ATXFrame(timing: 7, frameDelta: 0),
            ATXFrame(timing: 7, rectWidth: 2, rectHeight: 3, frameDelta: 1, loopTarget: 0)
        ])
    }

    func testATXRoundTripsByteIdentical() {
        let raw = makeSyntheticATX()
        let data = GoDData(byteStream: raw, byteOrder: .big)
        let decoder = GXTextureDecoder()

        guard let (image, meta) = decoder.decodeATX(data: data) else {
            XCTFail("decodeATX returned nil"); return
        }
        guard let reEncoded = decoder.encodeATX(image: image, metadata: meta) else {
            XCTFail("encodeATX returned nil"); return
        }
        XCTAssertEqual(reEncoded.rawBytes, raw, "ATX round-trip should be byte-identical")
    }

    /// Conditional integration test against a real poke_dance ATX sample.
    /// Skips silently if the legacy GoD tool dump isn't present on this machine.
    func testATXRoundTripsRealSample() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/airmd.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("poke_dance sample not available on this machine")
        }
        let original = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let decoder = GXTextureDecoder()
        guard let (image, meta) = decoder.decodeATX(data: original) else {
            XCTFail("decodeATX returned nil for real sample"); return
        }
        // Validate header fields match the values we observed across all XD samples.
        XCTAssertEqual(meta.animationCount, 2)
        XCTAssertEqual(meta.frameTableOffset, 0x28)
        XCTAssertEqual(meta.innerTextureSize, 0x3280)
        XCTAssertEqual(meta.innerTextureOffset, 0xA0)
        XCTAssertEqual(meta.texture.width, 64)
        XCTAssertEqual(meta.texture.height, 192)
        XCTAssertEqual(meta.texture.format, .c8)

        // Validate parsed keyframe streams. Predicted from disassembly trace:
        //   anim 0 @ 0x14: single-frame loop (timing=0x0A, no delta change, loop to 0)
        //   anim 1 @ 0x19: 4 frames at timing=7, deltas 0,1,2,1, looping to 0
        XCTAssertEqual(meta.animations.count, 2)
        XCTAssertEqual(meta.animations[0].offset, 0x14)
        XCTAssertEqual(meta.animations[0].frames, [
            ATXFrame(timing: 0x0A, frameDelta: 0x00, loopTarget: 0)
        ])
        XCTAssertEqual(meta.animations[1].offset, 0x19)
        XCTAssertEqual(meta.animations[1].frames, [
            ATXFrame(timing: 0x07, frameDelta: 0x00),
            ATXFrame(timing: 0x07, frameDelta: 0x01),
            ATXFrame(timing: 0x07, frameDelta: 0x02),
            ATXFrame(timing: 0x07, frameDelta: 0x01, loopTarget: 0)
        ])

        guard let reEncoded = decoder.encodeATX(image: image, metadata: meta) else {
            XCTFail("encodeATX returned nil"); return
        }
        // The wrapper + inner-header bytes must match exactly. The texture body
        // and palette may differ because the encoder rebuilds the palette from the
        // decoded PNG (a separate validation concern for GTX, not ATX).
        let originalBytes = original.rawBytes
        let reBytes = reEncoded.rawBytes
        XCTAssertEqual(reBytes.count, originalBytes.count, "Total file size must round-trip")
        XCTAssertEqual(
            Array(reBytes[0..<(meta.innerTextureOffset + 0x80)]),
            Array(originalBytes[0..<(meta.innerTextureOffset + 0x80)]),
            "Wrapper + inner GTX header must round-trip byte-identically"
        )
    }

    func testATXRejectsNonWrappedFile() {
        // A plain GTX-style header at offset 0 should not be misparsed as ATX.
        var d = [UInt8](repeating: 0, count: 0xA0)
        d[1] = 4; d[3] = 4; d[4] = 16; d[0x0B] = 0x44; d[0x2B] = 0x80
        let data = GoDData(byteStream: d, byteOrder: .big)
        let decoder = GXTextureDecoder()
        XCTAssertNil(decoder.decodeATX(data: data),
                     "Plain GTX-shaped data should fail ATX header sanity checks")
    }
}
