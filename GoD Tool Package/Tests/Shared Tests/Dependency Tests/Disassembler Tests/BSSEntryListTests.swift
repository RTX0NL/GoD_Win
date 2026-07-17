import XCTest
import Foundation
import GoDFoundation
import Disassembler
import TestSupport

/// Tests for `BSSEntryList` — sequential BSS address assignment with
/// 4-byte alignment. Ground truth is computed by hand.
final class BSSEntryListTests: XCTestCase {

    func testAssignAddresses_alignsEachEntryToFourBytes() {
        let list = BSSEntryList(entries: [
            .init(label: "a", size: 6),
            .init(label: "b", size: 4),
        ])
        // Base 0x80420001 → a aligns to 0x80420004, ends 0x8042000A;
        // b aligns to 0x8042000C.
        let assigned = list.assignAddresses(baseAddress: 0x8042_0001)
        XCTAssertEqual(assigned.count, 2)
        XCTAssertEqual(assigned[0].label, "a")
        XCTAssertEqual(assigned[0].address, 0x8042_0004)
        XCTAssertEqual(assigned[0].size, 6)
        XCTAssertEqual(assigned[1].label, "b")
        XCTAssertEqual(assigned[1].address, 0x8042_000C)
    }

    func testTotalSize_alignsEndToFourBytes() {
        let list = BSSEntryList(entries: [
            .init(label: "a", size: 6),
            .init(label: "b", size: 4),
        ])
        // b ends at 0x80420010 (aligned) → total = 0x80420010 - 0x80420001.
        XCTAssertEqual(list.totalSize(baseAddress: 0x8042_0001), 0xF)
    }

    func testTotalSize_emptyListIsZero() {
        XCTAssertEqual(BSSEntryList().totalSize(baseAddress: 0x8000_0000), 0)
    }

    func testCodable_roundTripsEntries() throws {
        let list = BSSEntryList(entries: [.init(label: "buffer", size: 0x100)])
        let payload: Data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(BSSEntryList.self, from: payload)
        XCTAssertEqual(decoded, list)
    }
}
