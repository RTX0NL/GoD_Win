//
//  PBRCommonTableRealCorpusTests.swift
//  PBRTests
//
//  Reads the real `common.fsys` tables with the engine's own struct
//  definitions, so the definitions are checked against the disc rather than
//  against a restatement of themselves. Skips cleanly when the unpacked
//  project isn't present, so it's safe to keep in the suite on a machine
//  without ROMs.
//
//  Point it at another dump with GODDESS_PBR_COMMON (a folder holding the
//  extracted `common NNNN.bin` members).
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
@testable import PBR

final class PBRCommonTableRealCorpusTests: XCTestCase {

    private var commonFolder: String? {
        let path = ProcessInfo.processInfo.environment["GODDESS_PBR_COMMON"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files/common"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func table(_ index: Int, in folder: String) -> GoDData? {
        let path = folder + "/common " + String(format: "%04d", index) + ".bin"
        guard let bytes = FileManager.default.contents(atPath: path) else { return nil }
        return GoDData(data: bytes, byteOrder: .big)
    }

    private func align(_ value: Int, to alignment: Int) -> Int {
        let remainder = value % alignment
        return remainder == 0 ? value : value + alignment - remainder
    }

    /// Every geometry invariant the header struct documents, read through
    /// the struct itself, on all 33 tables of the disc.
    func testHeaderGeometryHoldsForEveryTable() throws {
        guard let folder = commonFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
        let alignment = engine.data.commonTableFormat.regionAlignment

        var checked = 0
        for descriptor in engine.data.commonTables {
            guard let file = table(descriptor.index, in: folder) else { continue }
            let header = StructData(
                definition: headerDefinition,
                data: try XCTUnwrap(file.read(atAddress: 0, length: headerDefinition.length))
            )
            let context = "\(descriptor.name) (common_\(descriptor.index))"

            let count: Int = try XCTUnwrap(header.get("entry_count"), context)
            let stride: Int = try XCTUnwrap(header.get("entry_size"), context)
            let poolOffset: Int = try XCTUnwrap(header.get("string_pool_offset"), context)
            let poolSize: Int = try XCTUnwrap(header.get("string_pool_size"), context)
            let entriesOffset: Int = try XCTUnwrap(header.get("entries_offset"), context)
            let entriesSize: Int = try XCTUnwrap(header.get("entries_size"), context)
            let relocationOffset: Int = try XCTUnwrap(header.get("relocation_table_offset"), context)
            let relocationCount: Int = try XCTUnwrap(header.get("relocation_table_count"), context)
            let nameTableOffset: Int = try XCTUnwrap(header.get("name_table_offset"), context)

            XCTAssertEqual(poolOffset, engine.data.commonTableFormat.headerSize,
                           "\(context): string pool starts right after the header")
            XCTAssertEqual(entriesSize, count * stride,
                           "\(context): entries_size is the entry array's byte length")
            XCTAssertEqual(entriesOffset, align(poolOffset + poolSize, to: alignment),
                           "\(context): entry array follows the padded string pool")
            XCTAssertEqual(relocationOffset + relocationCount * 4, file.length,
                           "\(context): relocation table runs to the end of the file")

            // The name table only exists when there are named entries; the
            // header zeroes its offset otherwise.
            if relocationCount == 0 {
                XCTAssertEqual(nameTableOffset, 0, "\(context): no name table")
                XCTAssertEqual(relocationOffset, align(entriesOffset + entriesSize, to: alignment),
                               "\(context): file ends at the padded entry array")
            } else {
                XCTAssertEqual(nameTableOffset, align(entriesOffset + entriesSize, to: alignment),
                               "\(context): name table follows the padded entry array")
            }

            // The registry's recorded stride is what binds a struct to a
            // table, so it has to be what the disc actually says.
            XCTAssertEqual(stride, descriptor.entrySize, "\(context): registry stride")
            checked += 1
        }
        XCTAssertEqual(checked, 33, "expected all 33 common.fsys tables")
    }

    /// Every run a PBR entry struct declares as padding must actually be
    /// filler in the real rows.
    ///
    /// `common.fsys`'s packer fills intra-entry alignment gaps with `0xD0`,
    /// not zero — which is what separates a genuine unknown-but-used field
    /// from a hole, and is the evidence behind several of the padding runs in
    /// these structs. This walks every registered entry struct over every row
    /// of its table and fails if a declared padding run carries anything but
    /// a single repeated filler byte, so mislabelling a live field as padding
    /// is caught immediately.
    func testDeclaredPaddingRunsAreFillerInEveryRow() throws {
        guard let folder = commonFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()

        /// Byte ranges the definition declares as padding, flattened through
        /// arrays and sub-structs.
        ///
        /// `.padding(length:)` produces a byte array under the reserved name
        /// `padding` rather than a distinct type case (that's what makes it
        /// round-trip the real bytes instead of zeroing them), so the run is
        /// identified by property name.
        func paddingRanges(of definition: StructDefinition, base: Int = 0) -> [Range<Int>] {
            var ranges: [Range<Int>] = []
            var offset = base
            for property in definition.properties {
                let length = property.type.length
                if property.name == StructDefinition.paddingPropertyName {
                    ranges.append(offset..<(offset + length))
                } else if case .subStruct(let sub) = property.type {
                    ranges.append(contentsOf: paddingRanges(of: sub, base: offset))
                } else if case .array(let element, let count) = property.type,
                          case .subStruct(let sub) = element {
                    for i in 0..<count {
                        ranges.append(contentsOf: paddingRanges(of: sub, base: offset + i * sub.length))
                    }
                }
                offset += length
            }
            return ranges
        }

        var checkedTables = 0, checkedRuns = 0
        for descriptor in engine.data.commonTables {
            guard let structName = descriptor.structName,
                  let file = table(descriptor.index, in: folder) else { continue }
            let definition = try engine.getStruct(structName)
            let ranges = paddingRanges(of: definition)
            guard !ranges.isEmpty else { continue }

            let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
            let header = StructData(
                definition: headerDefinition,
                data: try XCTUnwrap(file.read(atAddress: 0, length: headerDefinition.length))
            )
            let count: Int = try XCTUnwrap(header.get("entry_count"))
            let entriesOffset: Int = try XCTUnwrap(header.get("entries_offset"))
            let bytes = file.rawBytes

            for range in ranges {
                var observed = Set<UInt8>()
                for row in 0..<count {
                    let start = entriesOffset + row * definition.length
                    observed.formUnion(bytes[(start + range.lowerBound)..<(start + range.upperBound)])
                }
                XCTAssertTrue(
                    observed.isSubset(of: [0x00, 0xD0]),
                    "\(descriptor.name).\(structName) padding at +0x\(String(range.lowerBound, radix: 16)) "
                    + "carries live data (bytes \(observed.sorted().map { String($0, radix: 16) })) — it is a field, not padding"
                )
                checkedRuns += 1
            }
            checkedTables += 1
        }
        XCTAssertGreaterThan(checkedTables, 8, "expected many tables to declare padding")
        XCTAssertGreaterThan(checkedRuns, 15)
    }

    /// Each name-table record points at a string-pool record, and the
    /// relocation table points at those records' pointer fields. Checked on
    /// the abilities table, which is the one with a real name pool
    /// (`TOKUSEI_000`…) and 124 records.
    func testNameTableAndRelocationsResolveOnTheAbilitiesTable() throws {
        guard let folder = commonFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(named: "Abilities"))
        let file = try XCTUnwrap(table(descriptor.index, in: folder))

        let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
        let header = StructData(
            definition: headerDefinition,
            data: try XCTUnwrap(file.read(atAddress: 0, length: headerDefinition.length))
        )
        let entryCount: Int = try XCTUnwrap(header.get("entry_count"))
        let nameTableOffset: Int = try XCTUnwrap(header.get("name_table_offset"))
        let relocationOffset: Int = try XCTUnwrap(header.get("relocation_table_offset"))
        let relocationCount: Int = try XCTUnwrap(header.get("relocation_table_count"))

        let recordDefinition = try engine.getStruct("PBRCommonTableNameRecord")
        let relocationDefinition = try engine.getStruct("PBRCommonTableRelocation")
        XCTAssertGreaterThan(relocationCount, 0)

        var previousHash = -1
        for i in 0..<relocationCount {
            let recordOffset = nameTableOffset + i * recordDefinition.length
            let record = StructData(
                definition: recordDefinition,
                data: try XCTUnwrap(file.read(atAddress: recordOffset, length: recordDefinition.length))
            )
            let nameOffset: Int = try XCTUnwrap(record.get("name_offset"))
            let entryIndex: Int = try XCTUnwrap(record.get("entry_index"))
            XCTAssertLessThan(entryIndex, entryCount, "record \(i) indexes a real entry")

            // The pool record is a 16-bit hash then a NUL-terminated name.
            let stringDefinition = try engine.getStruct("PBRCommonTableStringHeader")
            let stringHeader = StructData(
                definition: stringDefinition,
                data: try XCTUnwrap(file.read(atAddress: nameOffset, length: stringDefinition.length))
            )
            let hash: Int = try XCTUnwrap(stringHeader.get("name_hash"))
            XCTAssertGreaterThan(hash, previousHash, "name table is sorted ascending by hash")
            previousHash = hash

            let nameBytes = file.rawBytes[(nameOffset + 2)...].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            XCTAssertTrue(name.hasPrefix("TOKUSEI_"), "unexpected ability name \(name)")

            // Each relocation word points at the record's pointer field,
            // which is the record's own address.
            let relocation = StructData(
                definition: relocationDefinition,
                data: try XCTUnwrap(file.read(
                    atAddress: relocationOffset + i * relocationDefinition.length,
                    length: relocationDefinition.length
                ))
            )
            XCTAssertEqual(try XCTUnwrap(relocation.get("pointer_field_offset")), recordOffset,
                           "relocation \(i) targets its name record's pointer field")
        }
    }

    /// Reads every row of the model table through `PBRPokemonModel` and
    /// checks the facts the struct's field layout claims. If any field were
    /// at the wrong offset these would drift immediately.
    func testPokemonModelRowsDecodeAcrossTheWholeTable() throws {
        guard let folder = commonFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(named: "PokemonModels"))
        let file = try XCTUnwrap(table(descriptor.index, in: folder))

        let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
        let header = StructData(
            definition: headerDefinition,
            data: try XCTUnwrap(file.read(atAddress: 0, length: headerDefinition.length))
        )
        let count: Int = try XCTUnwrap(header.get("entry_count"))
        let entriesOffset: Int = try XCTUnwrap(header.get("entries_offset"))

        let rowDefinition = try engine.getStruct("PBRPokemonModel")
        XCTAssertEqual(rowDefinition.length, descriptor.entrySize)

        var femaleRows = 0
        var noAnimationSlots = 0
        for i in 0..<count {
            let row = StructData(
                definition: rowDefinition,
                data: try XCTUnwrap(file.read(
                    atAddress: entriesOffset + i * rowDefinition.length,
                    length: rowDefinition.length
                ))
            )
            let context = "row \(i)"

            let parameters: Int = try XCTUnwrap(row.get("parameters"), context)
            // Bits 3, 1 and 0 are never set on the disc.
            XCTAssertEqual(parameters & 0b0000_1011, 0, "\(context): unused parameter bits")
            if parameters & 0b0000_0100 != 0 { femaleRows += 1 }

            // Archive ids run 5001…5495 over the disc's 495 model archives.
            // For a real species that lands on 5000 + its dex number; the
            // two archives past the dex (pkx_600/601) just continue the
            // sequence, so only species ids in range can be checked.
            let fsysID: Int = try XCTUnwrap(row.get("fsys_id"), context)
            let species: Int = try XCTUnwrap(row.get("species"), context)
            if fsysID != 0 {
                XCTAssertTrue((5001...5495).contains(fsysID), "\(context): archive id \(fsysID) out of range")
                if species <= 493 {
                    XCTAssertEqual(fsysID, 5000 + species, "\(context): archive id encodes the dex number")
                }
            }

            // The model file id packs the FSYS entry identifier above its
            // file type, and the `.sdr` model type is 0x0400.
            let modelFileID: Int = try XCTUnwrap(row.get("model_file_id"), context)
            if modelFileID != 0 {
                XCTAssertEqual(modelFileID & 0xFFFF, 0x0400, "\(context): model file type")
            }

            XCTAssertLessThanOrEqual(try XCTUnwrap(row.get("form_index") as Int?, context), 27,
                                     "\(context): form index")

            // 0xFF ("no animation") is only ever used for the three tx_
            // face animations in the last three slots.
            let animations = try XCTUnwrap(row.get("animations") as StructData?, context)
            for slot in ["battle_idle", "special_move", "physical_move", "take_damage",
                         "faint", "running", "status_move", "summary_screen_idle"] {
                XCTAssertNotEqual(try XCTUnwrap(animations.get(slot) as Int?, context), 0xFF,
                                  "\(context): \(slot) should always be mapped")
            }
            if try XCTUnwrap(animations.get("blink") as Int?, context) == 0xFF { noAnimationSlots += 1 }
        }

        XCTAssertEqual(count, 670, "PAL model table row count")
        XCTAssertEqual(femaleRows, 93, "rows flagged as the female-specific model")
        XCTAssertGreaterThan(noAnimationSlots, 0, "some models have no blink animation")
    }
}
