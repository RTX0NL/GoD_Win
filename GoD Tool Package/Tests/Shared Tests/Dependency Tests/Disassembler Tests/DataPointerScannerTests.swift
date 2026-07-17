import XCTest
import Foundation
import GoDFoundation
import Disassembler
import TestSupport

/// Tests for `DataPointerScanner` — finds 4-byte-aligned values in data
/// sections that point into known section ranges (or match confirmed
/// relocation targets).
final class DataPointerScannerTests: XCTestCase {

    private let scanner = DataPointerScanner()
    private let textRange: [(start: UInt32, end: UInt32)] = [(0x8000_3100, 0x8000_5600)]

    private func word(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    func testScan_detectsInRangeValueAndIgnoresOutOfRange() {
        let data = word(0x8000_4000)      // offset 0: inside text range → hit
                 + word(0x1234_5678)      // offset 4: nowhere → miss
                 + word(0x8000_5600)      // offset 8: == range end (exclusive) → miss
        let pointers = scanner.scan(data: data, baseAddress: 0x8045_6200,
                                    confirmedTargets: [], sectionRanges: textRange)
        XCTAssertEqual(pointers, [0: 0x8000_4000])
    }

    func testScan_detectsConfirmedTargetOutsideRanges() {
        let data = word(0x8050_0000)
        let pointers = scanner.scan(data: data, baseAddress: 0x8045_6200,
                                    confirmedTargets: [0x8050_0000], sectionRanges: textRange)
        XCTAssertEqual(pointers, [0: 0x8050_0000])
    }

    func testScan_onlyConsidersFourByteAlignedOffsets() {
        // A pointer byte pattern starting at offset 2 must not be found.
        let data: [UInt8] = [0x00, 0x00] + word(0x8000_4000) + [0x00, 0x00]
        let pointers = scanner.scan(data: data, baseAddress: 0x8045_6200,
                                    confirmedTargets: [], sectionRanges: textRange)
        XCTAssertTrue(pointers.isEmpty)
    }

    func testScan_shortDataReturnsEmpty() {
        let pointers = scanner.scan(data: [0x80, 0x00], baseAddress: 0,
                                    confirmedTargets: [], sectionRanges: textRange)
        XCTAssertTrue(pointers.isEmpty)
    }

    func testScanAllSections_returnsPerSectionMaps() {
        let sectionA: [UInt8] = word(0x8000_3100)   // → text
        let sectionB: [UInt8] = word(0x0000_0000)   // → nothing
        let results = scanner.scanAllSections(
            dataSections: [(0x8045_6200, sectionA), (0x8045_7200, sectionB)],
            initialConfirmedTargets: [],
            sectionRanges: textRange
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], [0: 0x8000_3100])
        XCTAssertTrue(results[1].isEmpty)
    }
}
