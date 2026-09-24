import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX
import TestSupport

/// GSW-specific format behavior beyond the protocol members: tag stream
/// walk, texture detection, truncation handling. Each test exercises a
/// single decode step on a hand-crafted or real sample.
final class GSWTests: XCTestCase {

    // MARK: - Synthetic helpers

    private func makeEmbeddedTextureBlock() -> [UInt8] {
        let texBodySize = 32
        let palByteSize = 256 * 2
        var inner = [UInt8](repeating: 0, count: 0x80 + texBodySize + palByteSize)
        inner[0x01] = 4   // width
        inner[0x03] = 4   // height
        inner[0x04] = 8   // BPP
        inner[0x05] = 1   // indexed flag
        inner[0x0B] = UInt8(GXTextureFormat.C8.rawValue)
        inner[0x0F] = UInt8(GXPaletteFormat.RGB5A3_3.rawValue)
        inner[0x2B] = 0x80
        let palOff: UInt32 = UInt32(0x80 + texBodySize)
        inner[0x48] = UInt8((palOff >> 24) & 0xFF)
        inner[0x49] = UInt8((palOff >> 16) & 0xFF)
        inner[0x4A] = UInt8((palOff >> 8) & 0xFF)
        inner[0x4B] = UInt8(palOff & 0xFF)
        return inner
    }

    private func makeTexturePayload(id: Int) -> [UInt8] {
        let preMarker: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44,
                                  0x55, 0x66, 0x77, 0x88]
        let marker: [UInt8] = [0x03, 0x00, 0x00, UInt8(id)]
        let postMarker = [UInt8](repeating: 0xEE, count: 0x1C)
        let trailing: [UInt8] = [0x99, 0x88, 0x77, 0x66]
        return preMarker + marker + postMarker + makeEmbeddedTextureBlock() + trailing
    }

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

    private func makeHeader(streamSize: Int, spriteDepth: UInt8, chars: UInt8) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 0x30)
        h[0x03] = 7
        h[0x05] = 60
        h[0x07] = 100
        let tds = UInt32(streamSize)
        h[0x08] = UInt8((tds >> 24) & 0xFF); h[0x09] = UInt8((tds >> 16) & 0xFF)
        h[0x0A] = UInt8((tds >> 8) & 0xFF);  h[0x0B] = UInt8(tds & 0xFF)
        h[0x0E] = 0x32
        h[0x12] = 0x25; h[0x13] = 0x80
        h[0x19] = spriteDepth
        h[0x1B] = chars
        return h
    }

    // MARK: - Parse-step assertions

    /// A three-tag stream parses into three structured tags with the
    /// expected codes and payload sizes.
    func testParseIntoThreeTagsWithExpectedCodesAndPayloads() throws {
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0, payload: []))
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        stream.append(contentsOf: encodeTag(code: 1, payload: [0xDE, 0xAD, 0xBE, 0xEF]))
        let raw = makeHeader(streamSize: stream.count, spriteDepth: 1, chars: 2) + stream
        let (file, _) = try GSWParser.parse(data: GoDData(byteStream: raw, byteOrder: .big))

        XCTAssertEqual(file.tags.count, 3)
        XCTAssertEqual(file.tags[0].code, 0)
        XCTAssertEqual(file.tags[0].payload.count, 0)
        XCTAssertEqual(file.tags[1].code, 0x16)
        XCTAssertEqual(file.tags[2].code, 1)
        XCTAssertEqual(file.tags[2].payload.count, 4)
    }

    /// Embedded textures in a tag payload are discovered and exposed as
    /// GSWTextureRef entries with their on-disc metadata.
    func testEmbeddedTextureRefHasExpectedFields() throws {
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        let raw = makeHeader(streamSize: stream.count, spriteDepth: 1, chars: 1) + stream
        let (file, images) = try GSWParser.parse(data: GoDData(byteStream: raw, byteOrder: .big))

        let ref = try XCTUnwrap(file.tags[0].textures.first)
        XCTAssertEqual(ref.id, 1)
        XCTAssertEqual(ref.format, .C8)
        XCTAssertEqual(ref.width, 4)
        XCTAssertEqual(ref.height, 4)
        XCTAssertEqual(ref.payloadOffset, 12, "marker sits past 12 bytes of pre-filler")
        XCTAssertEqual(images.count, 1)
    }

    /// Real samples have non-contiguous texture IDs; the parser should
    /// skip missing IDs rather than bail on the first miss.
    func testSkipsMissingTextureIds() throws {
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 3)))
        let raw = makeHeader(streamSize: stream.count, spriteDepth: 5, chars: 5) + stream
        let (file, images) = try GSWParser.parse(data: GoDData(byteStream: raw, byteOrder: .big))

        XCTAssertEqual(file.allTextureRefs.map(\.id), [1, 3])
        XCTAssertEqual(images.count, 2)
    }

    /// Rejects a truncated header before any tag parsing happens.
    func testRejectsTruncatedHeader() {
        let truncated = [UInt8](repeating: 0, count: 0x10)
        XCTAssertThrowsError(try GSWParser.parse(data: GoDData(byteStream: truncated, byteOrder: .big)))
    }

    // MARK: - Real-sample parse assertions

    /// Real XD GSWs use version 7, a known frame rate, and 0x2580 at
    /// header offset 0x10. Each field is asserted independently.
    func testRealSmallSample_headerFieldsMatchKnownValues() throws {
        let path = SampleCorpus.xdGameFile("battle_disk_ge/battle_disk_ge 0012.gsw")
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("battle_disk_ge 0012.gsw not available")
        }
        let (file, _) = try GSWParser.parse(data: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        XCTAssertEqual(file.header.version, 7)
        XCTAssertEqual(file.header.frameRate, 0x3200)
        XCTAssertEqual(file.header.unknown_0x10, 0x2580)
        XCTAssertEqual(file.allTextureRefs.count, 1, "small sample has 1 embedded texture")
    }

    /// Medium sample has 3 textures with non-contiguous IDs.
    func testRealMediumSample_has3Textures() throws {
        let path = SampleCorpus.xdGameFile("bingo_menu_it/bingo_menu_it 0009.gsw")
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("bingo_menu_it 0009.gsw not available")
        }
        let (file, _) = try GSWParser.parse(data: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        XCTAssertEqual(file.allTextureRefs.count, 3)
    }

    /// Large sample has 21 textures.
    func testRealLargeSample_has21Textures() throws {
        let path = SampleCorpus.xdGameFile("title/title_start_00.gsw")
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("title_start_00.gsw not available")
        }
        let (file, _) = try GSWParser.parse(data: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        XCTAssertEqual(file.allTextureRefs.count, 21)
    }

    /// The tag walker must land exactly at EOF. Validates the sum of
    /// per-tag lengths matches filesize−header.
    func testTagStreamReachesEOFExactly() throws {
        let path = SampleCorpus.xdGameFile("battle_disk_ge/battle_disk_ge 0012.gsw")
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("GSW sample not available")
        }
        let bytes = [UInt8](raw)
        let (file, _) = try GSWParser.parse(data: GoDData(byteStream: bytes, byteOrder: .big))
        let tagStreamBytes = file.tags.reduce(0) { $0 + 8 + $1.payload.count }
        XCTAssertEqual(GSWParser.headerSize + tagStreamBytes, bytes.count)
    }
    /// PNG artifact names come from the ref id, so duplicate ids would make
    /// two textures share a file — the dump keeping only the last and the
    /// build loading it for both. No real GSW does this (73 files surveyed,
    /// all unique), so it can only arrive from hand-authored input, and it
    /// has to fail rather than silently drop a texture.
    func testDuplicateTextureRefIDsAreRejected() throws {
        // Two texture tags with distinct ids, then forced to collide.
        // Same shape as `testSkipsMissingTextureIds`, which is the fixture
        // known to yield two refs.
        var stream = [UInt8]()
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 1)))
        stream.append(contentsOf: encodeTag(code: 0x16, payload: makeTexturePayload(id: 3)))
        let raw = makeHeader(streamSize: stream.count, spriteDepth: 5, chars: 5) + stream

        var gsw = try GSWFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "sample")
        XCTAssertEqual(gsw.allTextureRefs.map(\.id), [1, 3])
        XCTAssertNoThrow(try gsw.outputs, "distinct ids must be fine")

        gsw.tags[1].textures[0].id = gsw.tags[0].textures[0].id
        XCTAssertThrowsError(try gsw.outputs) { error in
            XCTAssertTrue("\(error)".contains("duplicate texture ref ids"), "\(error)")
        }
    }

}
