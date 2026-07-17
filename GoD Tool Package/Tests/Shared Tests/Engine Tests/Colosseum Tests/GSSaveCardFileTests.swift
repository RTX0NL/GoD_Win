import XCTest
@testable import GeniusSonority
@testable import GoDFoundation

final class GSSaveCardFileTests: XCTestCase {

    /// Build a deterministic 0x56000 body where each region has a
    /// unique fill byte, so the split test can assert each region
    /// landed at the right offset.
    private func makeMarkedBody() -> GoDData {
        var bytes = [UInt8](repeating: 0, count: GSSaveCardFile.bodySize)
        for i in 0..<GSSaveCardFile.bannerSize {
            bytes[GSSaveCardFile.bannerOffset + i] = 0xAA
        }
        for i in 0..<GSSaveCardFile.header0Size {
            bytes[GSSaveCardFile.header0Offset + i] = 0xBB
        }
        for i in 0..<GSSaveCardFile.header1Size {
            bytes[GSSaveCardFile.header1Offset + i] = 0xCC
        }
        for i in 0..<GSSaveCardFile.slotSize {
            bytes[GSSaveCardFile.slotAOffset + i] = 0xDD
        }
        for i in 0..<GSSaveCardFile.slotSize {
            bytes[GSSaveCardFile.slotBOffset + i] = 0xEE
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testSplitLandsRegionsAtCorrectOffsets() throws {
        let body = makeMarkedBody()
        let card = try GSSaveCardFile(body: body)
        XCTAssertEqual(card.banner.length, GSSaveCardFile.bannerSize)
        XCTAssertEqual(card.header0.length, GSSaveCardFile.header0Size)
        XCTAssertEqual(card.header1.length, GSSaveCardFile.header1Size)
        XCTAssertEqual(card.slotA.length, GSSaveCardFile.slotSize)
        XCTAssertEqual(card.slotB.length, GSSaveCardFile.slotSize)

        XCTAssertEqual(card.banner.rawBytes.first, 0xAA)
        XCTAssertEqual(card.banner.rawBytes.last, 0xAA)
        XCTAssertEqual(card.header0.rawBytes.first, 0xBB)
        XCTAssertEqual(card.header1.rawBytes.first, 0xCC)
        XCTAssertEqual(card.slotA.rawBytes.first, 0xDD)
        XCTAssertEqual(card.slotB.rawBytes.first, 0xEE)
    }

    func testRoundTripBytes() throws {
        // Fill the body with a deterministic pseudo-random sequence so any
        // mis-ordered concat in `assembledBody()` is visible.
        var bytes = [UInt8](repeating: 0, count: GSSaveCardFile.bodySize)
        var rng: UInt32 = 0xCAFEBABE
        for i in 0..<bytes.count {
            rng = rng &* 1664525 &+ 1013904223
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
        let body = GoDData(byteStream: bytes, byteOrder: .big)
        let card = try GSSaveCardFile(body: body)
        let rebuilt = try card.assembledBody()
        XCTAssertEqual(rebuilt.rawBytes, body.rawBytes)
    }

    func testRejectsWrongBodySize() {
        let tooShort = GoDData(length: GSSaveCardFile.bodySize - 1, byteOrder: .big)
        XCTAssertThrowsError(try GSSaveCardFile(body: tooShort))
    }

    func testRejectsWrongRegionSize() throws {
        let body = makeMarkedBody()
        var card = try GSSaveCardFile(body: body)
        card.banner = GoDData(length: GSSaveCardFile.bannerSize - 1, byteOrder: .big)
        XCTAssertThrowsError(try card.assembledBody())
    }
}
