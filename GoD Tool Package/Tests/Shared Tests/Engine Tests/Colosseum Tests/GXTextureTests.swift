import XCTest
import GoDFoundation
import GTX
import TestSupport

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
        XCTAssertEqual(meta?.format, .RGBA32)
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
        inner[5] = 1                             // 1 on every retail texture
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
        XCTAssertEqual(meta.texture.format, .RGBA32)

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
        let path = SampleCorpus.xdGameFile("poke_dance/airmd.atx")
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
        XCTAssertEqual(meta.texture.format, .C8)

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

    // MARK: - Pure GTX decode → encode → decode roundtrip

    /// One representative real-sample path per pixel format. The test skips any
    /// format whose sample isn't available on this machine.
    private static let roundTripSamples: [(format: GXTextureFormat, path: String)] = {
        let samples: [(format: GXTextureFormat, path: String)] = [
        (.C4,     "field_common/uv_str_root_csr.gtx"),
        (.C8,     "battle_disk_doc_fr/uv_str_disk_01.gtx"),
        (.I4,     "fight_common/uv_btl_panel_hyper_00.gtx"),
        (.I8,     "wzx_kamikudaku_damage/kamikudaku_damage_0_7.wzx.dat.gtx"),
        (.RGB565, "pkx_patcheel/face.gtx"),
        (.RGBA32, "world_map/menu_038.gtx"),
        (.RGB5A3, "title/menu_018.gtx"),
        (.CMPR,   "world_map/mapsnap007.gtx"),
        ]
        return samples.map { (format: $0.format, path: SampleCorpus.xdGameFile($0.path)) }
    }()

    /// Load a sample file, decode it, and return the decoded image plus metadata.
    private func loadAndDecode(_ path: String, expect format: GXTextureFormat) throws -> (GoDImage, GXTextureMetadata) {
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("sample for format \(format) not available: \(path)")
        }
        let data = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let decoder = GXTextureDecoder()
        guard let meta = decoder.parseHeader(data: data) else {
            XCTFail("parseHeader failed for \(path)"); throw XCTSkip("header parse failed")
        }
        XCTAssertEqual(meta.format, format, "sample at \(path) has unexpected format")
        guard let image = decoder.decode(data: data) else {
            XCTFail("decode failed for \(path)"); throw XCTSkip("decode failed")
        }
        XCTAssertEqual(image.width, meta.width)
        XCTAssertEqual(image.height, meta.height)
        XCTAssertEqual(image.pixels.rawBytes.count, meta.width * meta.height * 4)
        return (image, meta)
    }

    /// decode → encode → decode should produce pixel-identical output for every
    /// format, CMPR included — see `testRoundTripCMPR`.
    private func assertPixelStableRoundTrip(_ format: GXTextureFormat) throws {
        guard let sample = Self.roundTripSamples.first(where: { $0.format == format }) else {
            throw XCTSkip("no sample registered for \(format)")
        }
        let (image, meta) = try loadAndDecode(sample.path, expect: format)

        let decoder = GXTextureDecoder()
        guard let reEncoded = decoder.encode(image: image, metadata: meta) else {
            XCTFail("encode returned nil for \(format)"); return
        }
        guard let reDecoded = decoder.decode(data: reEncoded) else {
            XCTFail("re-decode returned nil for \(format)"); return
        }

        XCTAssertEqual(reDecoded.width, image.width)
        XCTAssertEqual(reDecoded.height, image.height)
        XCTAssertEqual(
            reDecoded.pixels.rawBytes, image.pixels.rawBytes,
            "\(format) should decode → encode → decode to pixel-identical output"
        )
    }

    /// `+0x05` is 1 on every retail texture, whatever the format: 4314
    /// standalone `.gtx` files across the Colosseum, XD and Battle Revolution
    /// dumps carry 1 there, indexed and direct alike, and the DOL-embedded
    /// ones agree. (The only zeros anywhere are in headers the legacy tool
    /// synthesized around textures it pulled out of DAT/PKX/WZX models, which
    /// are not retail bytes.) Deriving it from the format — the encoder used
    /// to write `isIndexed ? 1 : 0` — was the one byte standing between every
    /// non-indexed texture and a byte-identical rebuild.
    func testEncodedHeaderMarksByteFiveForEveryFormat() throws {
        let decoder = GXTextureDecoder()
        for format in [GXTextureFormat.C4, .C8, .I4, .I8, .IA4, .IA8,
                       .RGB565, .RGBA32, .RGB5A3, .CMPR] {
            let image = GoDImage(
                width: 8,
                height: 8,
                pixels: GoDData(byteStream: [UInt8](repeating: 0x7F, count: 8 * 8 * 4), byteOrder: .big)
            )
            let metadata = GXTextureMetadata(
                width: 8,
                height: 8,
                format: format,
                paletteFormat: format.isIndexed ? .RGB5A3 : nil
            )
            guard let encoded = decoder.encode(image: image, metadata: metadata) else {
                XCTFail("encode returned nil for \(format)"); continue
            }
            XCTAssertEqual(encoded.rawBytes[5], 1, "\(format) should write 1 at +0x05")
            XCTAssertEqual(encoded.rawBytes[0x4C], 0, "\(format) should leave +0x4C zero")
        }
    }

    func testRoundTripC4()     throws { try assertPixelStableRoundTrip(.C4) }
    func testRoundTripC8()     throws { try assertPixelStableRoundTrip(.C8) }
    func testRoundTripI4()     throws { try assertPixelStableRoundTrip(.I4) }
    func testRoundTripI8()     throws { try assertPixelStableRoundTrip(.I8) }
    func testRoundTripRGB565() throws { try assertPixelStableRoundTrip(.RGB565) }
    func testRoundTripRGBA32() throws { try assertPixelStableRoundTrip(.RGBA32) }
    func testRoundTripRGB5A3() throws { try assertPixelStableRoundTrip(.RGB5A3) }

    /// CMPR used to be the one format whose round trip was only checked
    /// structurally, because re-compressing a decoded DXT1 block cannot
    /// reproduce it. The encoder inverts a block before it compresses one now
    /// (see `GXTexture.encodeDXT1SubBlock`), so a texture that came out of the
    /// game survives decode → encode → decode with every pixel in place, and
    /// this is held to the same assertion as the lossless formats.
    func testRoundTripCMPR() throws { try assertPixelStableRoundTrip(.CMPR) }
}
