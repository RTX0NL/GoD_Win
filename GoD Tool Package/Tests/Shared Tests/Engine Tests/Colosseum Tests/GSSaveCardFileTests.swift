import XCTest
@testable import GeniusSonority
@testable import GoDFoundation

final class GSSaveCardFileTests: XCTestCase {

    /// Build a deterministic 0x56000 body where each region has a
    /// unique fill byte, so the split test can assert each region
    /// landed at the right offset.
    private func makeMarkedBody() -> GoDData {
        var bytes = [UInt8](repeating: 0, count: GSSaveCardFile.bodySize)
        for i in 0..<GSSaveCardFile.metadataSize {
            bytes[GSSaveCardFile.metadataOffset + i] = 0xAA
        }
        for i in 0..<GSSaveCardFile.slotSize {
            bytes[GSSaveCardFile.slotAOffset + i] = 0xDD
        }
        for i in 0..<GSSaveCardFile.slotSize {
            bytes[GSSaveCardFile.slotBOffset + i] = 0xEE
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// The body splits into the metadata region and the two slots. The
    /// metadata region is one run, not the banner / header0 / header1
    /// trio an earlier version claimed: measured on every real save, the
    /// banner ends a quarter of the way into what was called `header0`.
    func testSplitsBodyIntoMetadataAndSlots() throws {
        let card = try GSSaveCardFile(body: makeMarkedBody())
        XCTAssertEqual(card.metadata.length, GSSaveCardFile.metadataSize)
        XCTAssertEqual(card.slotA.length, GSSaveCardFile.slotSize)
        XCTAssertEqual(card.slotB.length, GSSaveCardFile.slotSize)

        XCTAssertEqual(card.metadata.rawBytes.first, 0xAA)
        XCTAssertEqual(card.metadata.rawBytes.last, 0xAA)
        XCTAssertEqual(card.slotA.rawBytes.first, 0xDD)
        XCTAssertEqual(card.slotB.rawBytes.first, 0xEE)
        XCTAssertEqual(card.slots.count, GSSaveCardFile.slotCount)
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
        var card = try GSSaveCardFile(body: makeMarkedBody())
        card.metadata = GoDData(length: GSSaveCardFile.metadataSize - 1, byteOrder: .big)
        XCTAssertThrowsError(try card.assembledBody())
    }

    /// The declared region list and this type have to agree, since the
    /// GCI operations split on the declaration while other callers use
    /// the type directly.
    func testDeclaredRegionsMatchTheSplit() throws {
        let declaration = try XCTUnwrap(
            GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness).data.saveCard
        )
        XCTAssertEqual(declaration.bodyLength, GSSaveCardFile.bodySize)
        XCTAssertEqual(declaration.regions.map(\.name), ["metadata", "slot-a", "slot-b"])
        XCTAssertEqual(declaration.regions[0].length, GSSaveCardFile.metadataSize)
        XCTAssertEqual(declaration.regions[1].offset, GSSaveCardFile.slotAOffset)
        XCTAssertEqual(declaration.regions[2].offset, GSSaveCardFile.slotBOffset)
    }
}
