import XCTest
@testable import GameCube
@testable import GoDFoundation

final class GCIFileTests: XCTestCase {

    /// Build a synthetic but realistic Pokémon XD GCI: 0x40 DEntry +
    /// 0x56000-byte body (43 blocks). Body bytes are a deterministic
    /// pseudo-random sequence so any drift in roundtrip is visible.
    private func makeXDGCIBytes() -> GoDData {
        let blockCount = 0x2B  // 0x56000 / 0x2000
        let bodyLength = blockCount * GCIFile.blockSize
        var bytes = [UInt8](repeating: 0, count: GCIFile.headerSize + bodyLength)

        // Header bytes laid out by hand so the test asserts the exact
        // byte positions, not the parser's own conventions.
        // gamecode = "GXXE"
        bytes[0x00] = 0x47; bytes[0x01] = 0x58; bytes[0x02] = 0x58; bytes[0x03] = 0x45
        // makercode = "01"
        bytes[0x04] = 0x30; bytes[0x05] = 0x31
        // unused1
        bytes[0x06] = 0xFF
        // bannerAndIconFlags
        bytes[0x07] = 0x02
        // filename = "pokemon_storys" (14 chars), NUL-padded to 32
        let filename: [UInt8] = Array("pokemon_storys".utf8)
        for i in 0..<filename.count { bytes[0x08 + i] = filename[i] }
        // modtime = 0x12345678
        bytes[0x28] = 0x12; bytes[0x29] = 0x34; bytes[0x2A] = 0x56; bytes[0x2B] = 0x78
        // imageOffset = 0x60
        bytes[0x2C] = 0x00; bytes[0x2D] = 0x00; bytes[0x2E] = 0x00; bytes[0x2F] = 0x60
        // iconFmt = 0x0002, animSpeed = 0x5555
        bytes[0x30] = 0x00; bytes[0x31] = 0x02
        bytes[0x32] = 0x55; bytes[0x33] = 0x55
        // permissions
        bytes[0x34] = 0x04
        // copyCounter
        bytes[0x35] = 0x00
        // firstBlock = 0x0005
        bytes[0x36] = 0x00; bytes[0x37] = 0x05
        // blockCount = 0x002B
        bytes[0x38] = 0x00; bytes[0x39] = 0x2B
        // unused2 = 0xFFFF
        bytes[0x3A] = 0xFF; bytes[0x3B] = 0xFF
        // commentsAddr = 0x2000
        bytes[0x3C] = 0x00; bytes[0x3D] = 0x00; bytes[0x3E] = 0x20; bytes[0x3F] = 0x00

        // Pseudo-random body so any drop/duplicate is visible.
        var rng: UInt32 = 0xDEADBEEF
        for i in 0..<bodyLength {
            rng = rng &* 1664525 &+ 1013904223
            bytes[GCIFile.headerSize + i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testParseHeaderFields() throws {
        let raw = makeXDGCIBytes()
        let gci = try GCIFile(data: raw, name: "fixture")

        XCTAssertEqual(gci.header.gamecode, "GXXE")
        XCTAssertEqual(gci.header.makercode, "01")
        XCTAssertEqual(gci.header.unused1, 0xFF)
        XCTAssertEqual(gci.header.bannerAndIconFlags, 0x02)
        XCTAssertEqual(gci.header.filename, "pokemon_storys")
        XCTAssertEqual(gci.header.modtime, 0x12345678)
        XCTAssertEqual(gci.header.imageOffset, 0x60)
        XCTAssertEqual(gci.header.iconFmt, 0x0002)
        XCTAssertEqual(gci.header.animSpeed, 0x5555)
        XCTAssertEqual(gci.header.permissions, 0x04)
        XCTAssertEqual(gci.header.copyCounter, 0x00)
        XCTAssertEqual(gci.header.firstBlock, 0x0005)
        XCTAssertEqual(gci.header.blockCount, 0x002B)
        XCTAssertEqual(gci.header.unused2, 0xFFFF)
        XCTAssertEqual(gci.header.commentsAddr, 0x2000)
        XCTAssertEqual(gci.body.length, 0x56000)
    }

    func testRoundTripBytes() throws {
        let raw = makeXDGCIBytes()
        let gci = try GCIFile(data: raw, name: "fixture")
        let rebuilt = try gci.assembled()
        XCTAssertEqual(rebuilt.rawBytes, raw.rawBytes,
                       "GCI envelope did not byte-roundtrip")
    }

    func testFileFormatBinariesRoundTrip() throws {
        let raw = makeXDGCIBytes()
        let gci = try GCIFile(binaries: [
            FileData(file: File("fixture.gci"), data: raw)
        ])
        let bins = try gci.binaries
        XCTAssertEqual(bins.count, 1)
        XCTAssertEqual(bins[0].file.path, "fixture.gci")
        XCTAssertEqual(bins[0].data.rawBytes, raw.rawBytes)
    }

    func testOutputsRoundTripViaJSONManifest() throws {
        let raw = makeXDGCIBytes()
        let gci = try GCIFile(data: raw, name: "fixture")
        let outputs = try gci.outputs

        // Manifest first, body sidecar second.
        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(outputs[0].file.path, "fixture.gci.json")
        XCTAssertEqual(outputs[1].file.path, "fixture.gci.body.bin")
        XCTAssertEqual(outputs[1].data.rawBytes, gci.body.rawBytes)

        let restored = try GCIFile(outputs: outputs)
        let rebuilt = try restored.assembled()
        XCTAssertEqual(rebuilt.rawBytes, raw.rawBytes)
    }

    func testRejectsTruncatedBody() {
        let raw = makeXDGCIBytes()
        // Drop the last block — body length now mismatches blockCount.
        let truncated = GoDData(
            byteStream: Array(raw.rawBytes.prefix(raw.length - GCIFile.blockSize)),
            byteOrder: .big
        )
        XCTAssertThrowsError(try GCIFile(data: truncated, name: "fixture"))
    }
}
