import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX

final class GSWTests: XCTestCase {

    // MARK: - Synthesized round-trip

    /// Builds an embedded-texture block (GTX-format) for a 4×4 C8 indexed texture.
    private func makeEmbeddedTextureBlock() -> [UInt8] {
        let texW = 4, texH = 4
        let texBodySize = 32
        let palByteSize = 256 * 2
        var inner = [UInt8](repeating: 0, count: 0x80 + texBodySize + palByteSize)  // 0x280
        inner[0x01] = UInt8(texW)
        inner[0x03] = UInt8(texH)
        inner[0x04] = 8                     // BPP
        inner[0x05] = 1                     // indexed flag — (BPP, indexed) = 0x0801
        inner[0x0B] = UInt8(GXTextureFormat.C8.rawValue)
        inner[0x0F] = UInt8(GXPaletteFormat.RGB5A3_3.rawValue)
        inner[0x2B] = 0x80                  // texture pointer
        let palOff: UInt32 = UInt32(0x80 + texBodySize)
        inner[0x48] = UInt8((palOff >> 24) & 0xFF)
        inner[0x49] = UInt8((palOff >> 16) & 0xFF)
        inner[0x4A] = UInt8((palOff >> 8) & 0xFF)
        inner[0x4B] = UInt8(palOff & 0xFF)
        return inner
    }

    /// Builds a tag payload that wraps an embedded texture (id = `id`):
    /// `[12 bytes filler][marker][0x1C bytes filler][texture block][trailing filler]`.
    /// The texture must begin at marker_offset + 0x20.
    private func makeTexturePayload(id: Int) -> [UInt8] {
        let preMarker: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        let marker: [UInt8] = [0x03, 0x00, 0x00, UInt8(id)]
        let postMarker = [UInt8](repeating: 0xEE, count: 0x1C)
        let trailing: [UInt8] = [0x99, 0x88, 0x77, 0x66]
        return preMarker + marker + postMarker + makeEmbeddedTextureBlock() + trailing
    }

    /// Encodes a tag (code, payload) as a (u32 BE code, u32 BE size, payload) record.
    private func encodeTag(code: UInt32, payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count)
        var out: [UInt8] = []
        out.append(contentsOf: [UInt8(code >> 24), UInt8((code >> 16) & 0xFF),
                                UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)])
        out.append(contentsOf: [UInt8(size >> 24), UInt8((size >> 16) & 0xFF),
                                UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        out.append(contentsOf: payload)
        return out
    }

    /// Builds a minimal GSW with a 0x30 header and a tag stream of three tags:
    /// a small "ShowFrame" (code 0, empty), a tag containing one embedded texture,
    /// and a 4-byte trailing tag. Mirrors the structural shape of real samples.
    private func makeSyntheticGSW() -> [UInt8] {
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0, payload: []))
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        stream.append(contentsOf: encodeTag(code: 1, payload: [0xDE, 0xAD, 0xBE, 0xEF]))

        var header = [UInt8](repeating: 0, count: 0x30)
        header[0x03] = 7                            // version = 7
        header[0x05] = 60                            // canvas width
        header[0x07] = 100                           // canvas height
        // tagDataSize: we set it to stream length here to match a plausible value
        let tds = UInt32(stream.count)
        header[0x08] = UInt8((tds >> 24) & 0xFF)
        header[0x09] = UInt8((tds >> 16) & 0xFF)
        header[0x0A] = UInt8((tds >> 8) & 0xFF)
        header[0x0B] = UInt8(tds & 0xFF)
        header[0x0E] = 0x32                          // frame rate
        header[0x12] = 0x25; header[0x13] = 0x80     // unknown_0x10 = 0x2580
        header[0x19] = 1                             // spriteDepthCount = 1
        header[0x1B] = 2                             // characterCount = 2
        return header + stream
    }

    func testGSWParsesStructuredFields() throws {
        let raw = makeSyntheticGSW()
        let data = GoDData(byteStream: raw, byteOrder: .big)
        let (file, images) = try GSWParser.parse(data: data)

        XCTAssertEqual(file.header.version, 7)
        XCTAssertEqual(file.header.canvasWidthTwips, 60)
        XCTAssertEqual(file.header.canvasHeightTwips, 100)
        XCTAssertEqual(file.header.frameRate, 0x3200)
        XCTAssertEqual(file.header.unknown_0x10, 0x2580)
        XCTAssertEqual(file.header.spriteDepthCount, 1)
        XCTAssertEqual(file.header.characterCount, 2)
        XCTAssertEqual(file.header.unknown_0x2C, 0)

        // Three tags: ShowFrame (code 0, empty), texture-bearing (code 0x16),
        // and a small trailing (code 1, 4 bytes).
        XCTAssertEqual(file.tags.count, 3)
        XCTAssertEqual(file.tags[0].code, 0)
        XCTAssertEqual(file.tags[0].payload.count, 0)
        XCTAssertTrue(file.tags[0].textures.isEmpty)
        XCTAssertEqual(file.tags[1].code, 0x16)
        XCTAssertEqual(file.tags[1].textures.count, 1)
        XCTAssertEqual(file.tags[2].code, 1)
        XCTAssertEqual(file.tags[2].payload.count, 4)
        XCTAssertTrue(file.tags[2].textures.isEmpty)

        let ref = file.tags[1].textures[0]
        XCTAssertEqual(ref.id, 1)
        XCTAssertEqual(ref.format, .C8)
        XCTAssertEqual(ref.width, 4)
        XCTAssertEqual(ref.height, 4)
        XCTAssertEqual(ref.pngPath, "./textures/texture_001.png")
        // Marker is at payload offset 12 (after the 12-byte preMarker filler)
        XCTAssertEqual(ref.payloadOffset, 12)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].width, 4)
        XCTAssertEqual(images[0].height, 4)
    }

    /// Real samples have non-contiguous texture ids (e.g. [1, 3, 5]). The
    /// parser must skip missing ids rather than break on first miss.
    func testGSWSkipsMissingTextureIds() throws {
        // Two tags, each containing a different texture id (1 and 3, no 2).
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 3)))

        var header = [UInt8](repeating: 0, count: 0x30)
        header[0x03] = 7
        header[0x05] = 60
        header[0x07] = 100
        let tds = UInt32(stream.count)
        header[0x08] = UInt8((tds >> 24) & 0xFF)
        header[0x09] = UInt8((tds >> 16) & 0xFF)
        header[0x0A] = UInt8((tds >> 8) & 0xFF)
        header[0x0B] = UInt8(tds & 0xFF)
        header[0x0E] = 0x32
        header[0x12] = 0x25; header[0x13] = 0x80
        header[0x19] = 5                             // spriteDepthCount = 5 (covers ids 1..5)
        header[0x1B] = 5

        let data = GoDData(byteStream: header + stream, byteOrder: .big)
        let (file, images) = try GSWParser.parse(data: data)

        let refs = file.allTextureRefs
        XCTAssertEqual(refs.count, 2, "should find ids 1 and 3, skipping 2/4/5")
        XCTAssertEqual(refs.map(\.id), [1, 3])
        XCTAssertEqual(images.count, 2)
        // Each texture lives in a separate tag
        XCTAssertEqual(file.tags[0].textures.first?.id, 1)
        XCTAssertEqual(file.tags[1].textures.first?.id, 3)
    }

    func testGSWRoundTripsByteIdentical() throws {
        let raw = makeSyntheticGSW()
        let data = GoDData(byteStream: raw, byteOrder: .big)
        let (file, images) = try GSWParser.parse(data: data)
        let reEncoded = try GSWParser.serialize(file: file, images: images)
        XCTAssertEqual(reEncoded.rawBytes, raw, "GSW round-trip should be byte-identical")
    }

    func testGSWRejectsTruncatedHeader() {
        let truncated = [UInt8](repeating: 0, count: 0x10)
        let data = GoDData(byteStream: truncated, byteOrder: .big)
        XCTAssertThrowsError(try GSWParser.parse(data: data))
    }

    // MARK: - Real-sample integration tests (skip if not present)

    func testGSWRoundTripsSmallRealSample() throws {
        try roundTripRealSample(
            path: "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/battle_disk_ge/battle_disk_ge 0012.gsw",
            expectedTextureCount: 1
        )
    }

    func testGSWRoundTripsMediumRealSample() throws {
        // Survey showed ids = [1, 3, 5] — non-contiguous, exercises skip-missing
        try roundTripRealSample(
            path: "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/bingo_menu_it/bingo_menu_it 0009.gsw",
            expectedTextureCount: 3
        )
    }

    func testGSWRoundTripsLargeRealSample() throws {
        // Survey showed 21 textures spread across both tag stream + data section
        try roundTripRealSample(
            path: "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/title/title_start_00.gsw",
            expectedTextureCount: 21
        )
    }

    private func roundTripRealSample(path: String, expectedTextureCount: Int) throws {
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("Sample GSW not present at \(path)")
        }
        let original = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let (file, images) = try GSWParser.parse(data: original)

        XCTAssertEqual(file.header.version, 7, "version 7 expected for XD samples")
        XCTAssertEqual(file.header.frameRate, 0x3200)
        XCTAssertEqual(file.header.unknown_0x10, 0x2580)
        XCTAssertGreaterThan(file.tags.count, 0, "tag stream must parse to 1+ tags")
        // Verify every tag code is in the dispatch table's range.
        for tag in file.tags {
            XCTAssertLessThanOrEqual(tag.code, GSWParser.maxTagCode,
                                     "tag code 0x\(String(tag.code, radix: 16)) > 0x30")
        }
        // Verify every tag's serialized size sums to file size minus header.
        let totalTagBytes = file.tags.reduce(0) { $0 + 8 + $1.payload.count }
        XCTAssertEqual(GSWParser.headerSize + totalTagBytes, original.length,
                       "tag stream walk must reach EOF exactly")

        XCTAssertEqual(file.allTextureRefs.count, expectedTextureCount)

        let reEncoded = try GSWParser.serialize(file: file, images: images)
        let reBytes = reEncoded.rawBytes
        let originalBytes = original.rawBytes

        XCTAssertEqual(reBytes.count, originalBytes.count, "file size must round-trip")

        // Compute texture-region byte ranges (file-absolute) for diffing.
        // For each tag with textures, its payload starts at a known absolute
        // offset; texture lives at payload_start + payloadOffset + 0x20.
        var textureRanges = [Range<Int>]()
        var pos = GSWParser.headerSize
        for tag in file.tags {
            let payloadStart = pos + 8
            for ref in tag.textures {
                let absStart = payloadStart + ref.payloadOffset + 0x20
                textureRanges.append(absStart..<(absStart + ref.blockSize))
            }
            pos = payloadStart + Int(tag.payload.count)
        }
        textureRanges.sort { $0.lowerBound < $1.lowerBound }

        if textureRanges.isEmpty {
            XCTAssertEqual(reBytes, originalBytes, "no-texture file should round-trip identically")
        } else {
            // Header + every non-texture region must round-trip identically.
            // Texture bytes may differ because the GTX encoder rebuilds palettes.
            XCTAssertEqual(Array(reBytes[0..<0x30]), Array(originalBytes[0..<0x30]),
                           "header bytes must round-trip")
            var cursor = 0x30
            for range in textureRanges {
                if cursor < range.lowerBound {
                    XCTAssertEqual(
                        Array(reBytes[cursor..<range.lowerBound]),
                        Array(originalBytes[cursor..<range.lowerBound]),
                        "non-texture region [\(cursor), \(range.lowerBound)) must match"
                    )
                }
                cursor = range.upperBound
            }
            if cursor < reBytes.count {
                XCTAssertEqual(
                    Array(reBytes[cursor..<reBytes.count]),
                    Array(originalBytes[cursor..<originalBytes.count]),
                    "trailing region must match"
                )
            }
        }
    }
}
