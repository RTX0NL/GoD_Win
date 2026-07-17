import XCTest
import Foundation
import GoDFoundation
import Colosseum
import FixtureCatalog
import TestSupport

/// Encode/decode tests for `ColoSaveCardFile` (the Colosseum GCI body →
/// preamble + 3 encrypted slots split). No golden fixture: the format is a
/// fixed-offset split whose ground truth is the PKHeX-documented constants
/// (SLOT_START 0x6000, SLOT_SIZE 0x1E000, 3 slots), so tests slice a
/// deterministic body independently and compare against the type's output.
final class ColoSaveCardFileTests: XCTestCase {

    // MARK: - Decode (body → regions)

    func testColoSaveCard_initBody_splitsRegionsAtDocumentedOffsets() throws {
        let body = deterministicBytes(0x60000, seed: 0xC010_0001)
        let card = try ColoSaveCardFile(body: GoDData(byteStream: body, byteOrder: .big))

        assertBytesEqual(card.preamble.rawBytes, Array(body[0x00000..<0x06000]), "preamble")
        XCTAssertEqual(card.slots.count, 3)
        assertBytesEqual(card.slots[0].rawBytes, Array(body[0x06000..<0x24000]), "slot 0")
        assertBytesEqual(card.slots[1].rawBytes, Array(body[0x24000..<0x42000]), "slot 1")
        assertBytesEqual(card.slots[2].rawBytes, Array(body[0x42000..<0x60000]), "slot 2")
    }

    func testColoSaveCard_initBody_rejectsWrongSize() {
        let short = GoDData(byteStream: [UInt8](repeating: 0, count: 0x1000), byteOrder: .big)
        XCTAssertThrowsError(try ColoSaveCardFile(body: short))
    }

    // MARK: - Encode (regions → body)

    func testColoSaveCard_assembledBody_concatenatesRegionsInOrder() throws {
        let preamble = deterministicBytes(0x06000, seed: 0xC010_00FE)
        let slot0 = deterministicBytes(0x1E000, seed: 0xC010_0000)
        let slot1 = deterministicBytes(0x1E000, seed: 0xC010_0011)
        let slot2 = deterministicBytes(0x1E000, seed: 0xC010_0022)

        let card = ColoSaveCardFile(
            preamble: GoDData(byteStream: preamble, byteOrder: .big),
            slots: [
                GoDData(byteStream: slot0, byteOrder: .big),
                GoDData(byteStream: slot1, byteOrder: .big),
                GoDData(byteStream: slot2, byteOrder: .big),
            ]
        )
        let body = try card.assembledBody()
        XCTAssertEqual(body.length, ColoSaveCardFile.bodySize)
        assertBytesEqual(body.rawBytes, preamble + slot0 + slot1 + slot2)
    }

    func testColoSaveCard_assembledBody_rejectsWrongSlotCount() {
        let card = ColoSaveCardFile(
            preamble: GoDData(byteStream: [UInt8](repeating: 0, count: 0x6000), byteOrder: .big),
            slots: [GoDData(byteStream: [UInt8](repeating: 0, count: 0x1E000), byteOrder: .big)]
        )
        XCTAssertThrowsError(try card.assembledBody())
    }

    func testColoSaveCard_assembledBody_rejectsWrongRegionSize() {
        let card = ColoSaveCardFile(
            preamble: GoDData(byteStream: [UInt8](repeating: 0, count: 0x6000), byteOrder: .big),
            slots: [
                GoDData(byteStream: [UInt8](repeating: 0, count: 0x1E000), byteOrder: .big),
                GoDData(byteStream: [UInt8](repeating: 0, count: 0x100), byteOrder: .big),  // wrong
                GoDData(byteStream: [UInt8](repeating: 0, count: 0x1E000), byteOrder: .big),
            ]
        )
        XCTAssertThrowsError(try card.assembledBody())
    }

    // MARK: - Latest-slot detection

    func testColoSaveCard_detectLatestIndex_picksHighestCounter() throws {
        func slot(counter: Int32) -> GoDData {
            var bytes = [UInt8](repeating: 0, count: ColoSaveCardFile.slotSize)
            let u = UInt32(bitPattern: counter)
            bytes[4] = UInt8(u >> 24); bytes[5] = UInt8((u >> 16) & 0xFF)
            bytes[6] = UInt8((u >> 8) & 0xFF); bytes[7] = UInt8(u & 0xFF)
            return GoDData(byteStream: bytes, byteOrder: .big)
        }
        let card = ColoSaveCardFile(
            preamble: GoDData(byteStream: [UInt8](repeating: 0, count: 0x6000), byteOrder: .big),
            slots: [slot(counter: 5), slot(counter: 42), slot(counter: -1)]
        )
        XCTAssertEqual(card.detectLatestIndex(), 1)
    }
}
