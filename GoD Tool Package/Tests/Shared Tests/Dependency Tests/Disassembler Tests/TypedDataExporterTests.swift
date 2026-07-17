import XCTest
import Foundation
import GoDFoundation
import Structs
import Disassembler
import TestSupport

/// Tests for `TypedDataExporter` — the live struct/table export used by DOL
/// disassembly. Uses an in-memory `StructDefinition` (uint32 + label
/// fields); ground truth is hand-computed bytes.
final class TypedDataExporterTests: XCTestCase {

    private let exporter = TypedDataExporter()

    /// 8-byte struct: `id` (u32) then `ptr` (label = 4-byte pointer).
    private var definition: StructDefinition {
        StructDefinition(
            name: "TestStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .uint32(name: "id"),
                .label(name: "ptr"),
            ]
        )
    }

    private func entryBytes(id: UInt32, ptr: UInt32) -> [UInt8] {
        [UInt8(id >> 24), UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF),
         UInt8(ptr >> 24), UInt8((ptr >> 16) & 0xFF), UInt8((ptr >> 8) & 0xFF), UInt8(ptr & 0xFF)]
    }

    func testExportStruct_resolvesKnownLabelAddress() {
        let data = GoDData(byteStream: entryBytes(id: 0x2A, ptr: 0x8000_3000), byteOrder: .big)
        let exported = exporter.exportStruct(
            data: data,
            definition: definition,
            addressToLabel: [0x8000_3000: "my_func"]
        )
        let id: Int? = exported.get("id")
        XCTAssertEqual(id, 0x2A)
        XCTAssertEqual(exported.labelValues["ptr"], "my_func")
    }

    func testExportStruct_autoNamesUnknownLabelAddress() {
        let data = GoDData(byteStream: entryBytes(id: 1, ptr: 0x8000_4000), byteOrder: .big)
        let exported = exporter.exportStruct(
            data: data,
            definition: definition,
            addressToLabel: [:]
        )
        XCTAssertEqual(exported.labelValues["ptr"], "lbl_80004000")
    }

    func testExportTable_splitsEntriesAndAppliesEntryLabels() {
        let bytes = entryBytes(id: 1, ptr: 0x8000_3000) + entryBytes(id: 2, ptr: 0x8000_3100)
        let entries = exporter.exportTable(
            data: GoDData(byteStream: bytes, byteOrder: .big),
            definition: definition,
            count: 2,
            entryLabels: [(offset: 0, name: "first_entry")],
            addressToLabel: [0x8000_3000: "func_a"]
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].label, "first_entry")
        XCTAssertNil(entries[1].label)

        let id0: Int? = entries[0].data.get("id")
        let id1: Int? = entries[1].data.get("id")
        XCTAssertEqual(id0, 1)
        XCTAssertEqual(id1, 2)
        XCTAssertEqual(entries[0].data.labelValues["ptr"], "func_a")
        XCTAssertEqual(entries[1].data.labelValues["ptr"], "lbl_80003100",
                       "unknown pointer target auto-names")
    }

    func testExportTable_truncatedDataStopsShort() {
        // Only 1.5 entries of bytes — the second (incomplete) entry is dropped.
        let bytes = entryBytes(id: 1, ptr: 0x8000_3000) + [0x00, 0x00, 0x00, 0x05]
        let entries = exporter.exportTable(
            data: GoDData(byteStream: bytes, byteOrder: .big),
            definition: definition,
            count: 2,
            entryLabels: [],
            addressToLabel: [:]
        )
        XCTAssertEqual(entries.count, 1)
    }
}
