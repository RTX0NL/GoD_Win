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
//  Reads the archive itself (`Build/Contents/DATA/files/common.fsys`) rather
//  than the members an unpack leaves behind, because the dump replaces each
//  typed member's `.bin` with its CSV — so a fully-dumped project no longer
//  satisfied a test that wanted the raw bytes. Point it elsewhere with
//  GODDESS_PBR_COMMON / GODDESS_PBR_COMMON_JP (a path to a `common.fsys`).
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority
@testable import PBR

final class PBRCommonTableRealCorpusTests: XCTestCase {

    /// Reads an array property as big-endian 16-bit words. Struct keypaths
    /// don't index into arrays, so an array field comes back as its raw run
    /// of bytes and the element width is applied here.
    static func uint16s(in row: StructData, _ keypath: String) throws -> [UInt16] {
        let data: GoDData = try XCTUnwrap(row.get(keypath), "missing '\(keypath)'")
        data.setByteOrder(.big)
        return stride(from: 0, to: data.length - 1, by: 2).map {
            data.readSafely(atAddress: $0) as UInt16
        }
    }

    /// The tables, read straight out of the disc's `common.fsys`.
    ///
    /// These used to read `common NNNN.bin` files left behind by an unpack,
    /// which had two problems: the unpack's naming changed (`common 0000.bin`
    /// → `common_0000.bin`) and these tests silently skipped for however long,
    /// and — worse — the dump *replaces* each typed member's `.bin` with its
    /// CSV, so the very projects these tests exist to validate stopped
    /// satisfying them. The archive survives both, so it's the honest source:
    /// what's tested is what a dump actually reads.
    ///
    /// Members come back keyed by their index within the archive, which is
    /// what the table descriptors are keyed on.
    struct Corpus {
        let members: [Int: GoDData]
        let label: String
    }

    private static func loadCorpus(_ paths: [String], label: String) -> Corpus? {
        for path in paths {
            guard let bytes = FileManager.default.contents(atPath: path) else { continue }
            let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
            guard let archive = try? FSYSArchive(
                data: GoDData(data: bytes, byteOrder: .big), engine: engine
            ) else { continue }
            var members = [Int: GoDData]()
            for (index, entry) in archive.entries.enumerated() {
                members[index] = entry.data
            }
            guard !members.isEmpty else { continue }
            return Corpus(members: members, label: label)
        }
        return nil
    }

    /// US/PAL corpus. `GODDESS_PBR_COMMON` overrides with a path to a
    /// `common.fsys`.
    private var corpus: Corpus? {
        if let override = ProcessInfo.processInfo.environment["GODDESS_PBR_COMMON"] {
            return Self.loadCorpus([override], label: "override")
        }
        return Self.loadCorpus([
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files/common.fsys",
            NSHomeDirectory() + "/Downloads/GODDESS-JP-dump/PBR PAL project/Build/Contents/DATA/files/common.fsys",
        ], label: "PAL")
    }

    /// The Japanese disc is a separate corpus, not another path to the same
    /// one. `GODDESS_PBR_COMMON_JP` overrides.
    private var japaneseCorpus: Corpus? {
        if let override = ProcessInfo.processInfo.environment["GODDESS_PBR_COMMON_JP"] {
            return Self.loadCorpus([override], label: "override")
        }
        return Self.loadCorpus([
            NSHomeDirectory() + "/Downloads/GODDESS-JP-dump/PBR JP project/Build/Contents/DATA/files/common.fsys",
        ], label: "JP")
    }

    private func align(_ value: Int, to alignment: Int) -> Int {
        let remainder = value % alignment
        return remainder == 0 ? value : value + alignment - remainder
    }

    /// Every geometry invariant the header struct documents, read through
    /// the struct itself, on all 33 tables of the disc.
    func testHeaderGeometryHoldsForEveryTable() throws {
        guard let corpus else {
            throw XCTSkip("No PBR common.fsys — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
        // The data-table region alignment lives on the GS/FSYS engine now.
        let alignment = GeniusSonorityEngine.defaultEngine(for: .battleRevolution).data.fsys.dataTableRegionAlignmentValue

        var checked = 0
        for descriptor in engine.data.commonTables {
            guard let file = corpus.members[descriptor.index] else { continue }
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
        guard let corpus else {
            throw XCTSkip("No PBR common.fsys — set GODDESS_PBR_COMMON to run.")
        }
        let checked = try assertDeclaredPaddingIsFiller(in: corpus, japanese: false)
        XCTAssertGreaterThan(checked.tables, 8, "expected many tables to declare padding")
        XCTAssertGreaterThan(checked.runs, 15)
    }

    /// The same guard on the Japanese disc, which is where it earns its keep.
    ///
    /// A JP record can diverge *without* changing stride — `PokemonStats`
    /// drops the international record's Japanese-name id and ends on two
    /// bytes of filler, same 0x34 either way — so it still tiles the entry
    /// array and every geometry check passes while each field is read two
    /// bytes late. Filler is the content that catches it: read a JP table
    /// with the wrong record and the bytes its struct calls padding carry
    /// live data.
    func testDeclaredPaddingRunsAreFillerOnTheJapaneseDisc() throws {
        guard let corpus = japaneseCorpus else {
            throw XCTSkip("No Japanese PBR common.fsys — set GODDESS_PBR_COMMON_JP to run.")
        }
        let checked = try assertDeclaredPaddingIsFiller(in: corpus, japanese: true)
        XCTAssertGreaterThan(checked.tables, 8, "expected many tables to declare padding")
        XCTAssertGreaterThan(checked.runs, 15)
    }

    /// Every byte a bound struct declares as padding, in every row of every
    /// table of one disc, is one of the packer's two filler bytes.
    ///
    /// Tables are looked up by file index through `commonTable(fileIndex:
    /// japanese:)` — the same call the dump makes — so the JP member
    /// permutation and the JP record bindings are exercised rather than
    /// restated here.
    private func assertDeclaredPaddingIsFiller(
        in corpus: Corpus, japanese: Bool
    ) throws -> (tables: Int, runs: Int) {
        let engine = try PBREngine.defaults()
        let format = engine.data.commonTableFormat

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
        for (index, file) in corpus.members.sorted(by: { $0.key < $1.key }) {
            guard let descriptor = engine.commonTable(fileIndex: index, japanese: japanese),
                  let structName = descriptor.structName else { continue }
            let definition = try engine.getStruct(structName)
            XCTAssertEqual(
                definition.length, descriptor.entrySize,
                "\(corpus.label) \(descriptor.name): \(structName) doesn't match the declared stride"
            )
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
                // Filler is whatever the engine says it is, so the constant
                // and the disc can't drift apart: 0xD0 inside an entry, 0x00
                // where the packer simply left the field zeroed.
                let filler: Set<UInt8> = [
                    UInt8(truncatingIfNeeded: format.intraEntryPaddingByte),
                    UInt8(truncatingIfNeeded: format.interRegionPaddingByte),
                ]
                XCTAssertTrue(
                    observed.isSubset(of: filler),
                    "\(corpus.label) \(descriptor.name).\(structName) padding at +0x\(String(range.lowerBound, radix: 16)) "
                    + "carries live data (bytes \(observed.sorted().map { String($0, radix: 16) })) — it is a field, not padding"
                )
                checkedRuns += 1
            }
            checkedTables += 1
        }
        return (checkedTables, checkedRuns)
    }

    /// Every table on the Japanese disc rebuilds from its own CSV, byte for
    /// byte — the property a JP build depends on, and one the international
    /// corpus can't stand in for, since JP binds three of its own records and
    /// orders its members differently.
    func testEveryTableRebuildsFromItsCSVOnTheJapaneseDisc() throws {
        guard let corpus = japaneseCorpus else {
            throw XCTSkip("No Japanese PBR common.fsys — set GODDESS_PBR_COMMON_JP to run.")
        }
        let engine = try PBREngine.defaults()

        var checked = 0
        for (index, file) in corpus.members.sorted(by: { $0.key < $1.key }) {
            guard let descriptor = engine.commonTable(fileIndex: index, japanese: true),
                  descriptor.structName != nil,
                  let typed = try engine.typeCommonTable(descriptor, binary: file, structs: engine)
            else { continue }

            let csv = try StructTableCSV.encode(entries: typed.entries, definition: typed.entryDefinition)
            let fills = try XCTUnwrap(
                StructPaddingFill.measure(in: typed.entries, definition: typed.entryDefinition),
                "\(descriptor.name): a padding run varies between rows, so it isn't padding"
            )
            let rebuilt = try StructTableCSV.decode(
                csv, definition: typed.entryDefinition, byteOrder: .big, paddingFills: fills
            ).entries
            XCTAssertEqual(
                rebuilt.flatMap { $0.data.rawBytes }, typed.entries.flatMap { $0.data.rawBytes },
                "\(descriptor.name) doesn't rebuild from its CSV"
            )
            checked += 1
        }
        XCTAssertEqual(checked, 32, "the JP disc ships 32 tables and all of them type")
    }

    /// Each name-table record points at a string-pool record, and the
    /// relocation table points at those records' pointer fields. Checked on
    /// the abilities table, which is the one with a real name pool
    /// (`TOKUSEI_000`…) and 124 records.
    func testNameTableAndRelocationsResolveOnTheAbilitiesTable() throws {
        guard let corpus else {
            throw XCTSkip("No PBR common.fsys — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(named: "Abilities"))
        let file = try XCTUnwrap(corpus.members[descriptor.index])

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
        guard let corpus else {
            throw XCTSkip("No PBR common.fsys — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(named: "PokemonModels"))
        let file = try XCTUnwrap(corpus.members[descriptor.index])

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

    // MARK: - Japanese disc

    /// The JP disc lays two tables out differently, and the engine binds a
    /// separate struct to each. Both differ from US/PAL only by the width of
    /// a per-language array, so the test that matters is that every *other*
    /// field still lands where the struct says — which is what the
    /// cross-field relations below check.
    func testJapaneseCountriesUseTheJapaneseRecord() throws {
        guard let corpus = japaneseCorpus else {
            throw XCTSkip("No Japanese PBR common.fsys — set GODDESS_PBR_COMMON_JP to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(fileIndex: 7, japanese: true))
        XCTAssertEqual(descriptor.name, "Countries")
        XCTAssertEqual(descriptor.structName, "PBRCountryJP")
        XCTAssertEqual(descriptor.entrySize, 0x6C)

        let binary = try XCTUnwrap(corpus.members[7], "JP common.fsys member 7")
        let typed = try XCTUnwrap(engine.typeCommonTable(descriptor, binary: binary, structs: engine))
        XCTAssertEqual(typed.entries.count, 234, "the JP disc ships the same 234 countries")

        // Name ids are one per country and contiguous, exactly as on PAL.
        let names: [Int] = try typed.entries.map { try XCTUnwrap($0.get("name_message_id")) }
        XCTAssertEqual(names.first, 5705)
        XCTAssertEqual(names.last, 5938)
        XCTAssertEqual(names, names.sorted(), "name ids ascend with the row")

        // `subregion_count` counting the populated ids is the relation that
        // proves the array is at the right offset and the right length: if
        // the record were misaligned these would not agree on any row.
        var populated = 0
        for (index, row) in typed.entries.enumerated() {
            let ids = try Self.uint16s(in: row, "subregion_name_message_ids")
            XCTAssertEqual(ids.count, 52, "row \(index): sub-region slot count")
            let nonZero = ids.filter { $0 != 0 }.count
            XCTAssertEqual(try XCTUnwrap(row.get("subregion_count") as Int?), nonZero,
                           "row \(index): subregion_count must match the populated ids")
            if nonZero > 0 { populated += 1 }
        }
        XCTAssertEqual(populated, 18, "the same 18 countries carry sub-regions as on PAL")
    }

    /// The JP stats table is the same 501 rows at the same 0x34 stride, so a
    /// wrong record doesn't fail — it silently reads every field past the
    /// species name two bytes late. What settles it is the values: Bulbasaur's
    /// base stats and typing are the same numbers on every disc, and they only
    /// land in the right fields once the name id the JP record drops (+0x1A,
    /// the Japanese name every international disc also carries) is accounted
    /// for.
    func testJapanesePokemonStatsUseTheJapaneseRecord() throws {
        guard let corpus = japaneseCorpus else {
            throw XCTSkip("No Japanese PBR common.fsys — set GODDESS_PBR_COMMON_JP to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(fileIndex: 14, japanese: true))
        XCTAssertEqual(descriptor.name, "PokemonStats")
        XCTAssertEqual(descriptor.structName, "PBRPokemonStatsJP")
        XCTAssertEqual(descriptor.entrySize, 0x34, "the record is the same length, not the same layout")

        let binary = try XCTUnwrap(corpus.members[14], "JP common.fsys member 14")
        let typed = try XCTUnwrap(engine.typeCommonTable(descriptor, binary: binary, structs: engine))
        XCTAssertEqual(typed.entries.count, 501, "the JP disc ships the same 501 species rows")

        let bulbasaur = typed.entries[1]
        XCTAssertEqual(bulbasaur.get("base_hp") as Int?, 45)
        XCTAssertEqual(bulbasaur.get("base_attack") as Int?, 49)
        XCTAssertEqual(bulbasaur.get("base_defense") as Int?, 49)
        XCTAssertEqual(bulbasaur.get("base_speed") as Int?, 45)
        XCTAssertEqual(bulbasaur.get("base_special_attack") as Int?, 65)
        XCTAssertEqual(bulbasaur.get("base_special_defense") as Int?, 65)
        XCTAssertEqual(bulbasaur.get("type_1") as Int?, 12, "Grass")
        XCTAssertEqual(bulbasaur.get("type_2") as Int?, 3, "Poison")
        XCTAssertEqual(bulbasaur.get("catch_rate") as Int?, 45)
        XCTAssertEqual(bulbasaur.get("base_experience") as Int?, 64)
        XCTAssertEqual(bulbasaur.get("ability_1") as Int?, 65, "Overgrow")
        XCTAssertEqual(bulbasaur.get("height") as Int?, 7, "0.7 m, stored ×10")
        XCTAssertEqual(bulbasaur.get("weight") as Int?, 69, "6.9 kg, stored ×10")

        // The model index is the field the dropped name id used to sit in
        // front of, so it is the one that moves; row N pointing at model N
        // for the first few species is what shows it landed.
        XCTAssertEqual(bulbasaur.get("model_index") as Int?, 1)
        XCTAssertEqual(typed.entries[2].get("model_index") as Int?, 2)

        // Name ids ascend with the row across the whole table, which they
        // cannot do if the field is misaligned.
        let names: [Int] = try typed.entries[1...386].map { try XCTUnwrap($0.get("name_message_id")) }
        XCTAssertEqual(names, names.sorted(), "name ids ascend with the row")
        XCTAssertEqual(names.first, 11)

        // And the id is worth resolving rather than only checking it ascends,
        // because the JP disc carries its one string table and its directory
        // in this same archive: the row's id turns into the text the game
        // prints. A record read two bytes late would still hand back *an* id,
        // and it would not be the species'.
        let directory = try PBRStringDirectory(
            binary: XCTUnwrap(corpus.members[engine.data.japaneseStringDirectoryIndex],
                              "JP common.fsys string directory")
        )
        var stringTables = [Int: PBRStringTable]()
        for member in corpus.members.values where PBRStringTable.isStringTable(member) {
            let table = try PBRStringTable(binary: member)
            stringTables[table.tableID] = table
        }
        func speciesName(row: Int) throws -> String {
            let id: Int = try XCTUnwrap(typed.entries[row].get("name_message_id"))
            let record = directory.records[id - 1]
            let table = try XCTUnwrap(stringTables[record.tableID], "string table \(record.tableID)")
            return table.strings[record.index - 1].string(format: .gsPBR)
        }
        // Leading control codes are the string's own formatting, so the name
        // is the tail of it.
        for (row, name) in [(1, "フシギダネ"), (25, "ピカチュウ"), (150, "ミュウツー"), (386, "デオキシス")] {
            let text = try speciesName(row: row)
            XCTAssertTrue(text.hasSuffix(name), "row \(row) named '\(text)', expected it to end in \(name)")
        }

        // Reading it right is half the job. The record ends on two bytes the
        // packer filled, and a CSV has no column for padding, so the table an
        // edit rebuilds is only the table the disc had if the fill is carried
        // separately — which is what the dump measures and the registry
        // records.
        let csv = try StructTableCSV.encode(entries: typed.entries, definition: typed.entryDefinition)
        let fills = try XCTUnwrap(StructPaddingFill.measure(in: typed.entries, definition: typed.entryDefinition))
        XCTAssertEqual(fills, [StructPaddingFill(offset: 0x32, length: 2, byte: 0xD0)],
                       "the record's only gap is the two bytes the dropped name id left, filled with 0xD0")
        let decoded = try StructTableCSV.decode(
            csv, definition: typed.entryDefinition, byteOrder: .big, paddingFills: fills
        )
        XCTAssertEqual(
            decoded.entries.flatMap { $0.data.rawBytes },
            typed.entries.flatMap { $0.data.rawBytes },
            "the JP stats table rebuilds byte-for-byte from its CSV"
        )
    }

    func testJapaneseIndexNineIsColosseumsUnknownNotTutorialData() throws {
        guard let corpus = japaneseCorpus else {
            throw XCTSkip("No Japanese PBR common.fsys — set GODDESS_PBR_COMMON_JP to run.")
        }
        let engine = try PBREngine.defaults()

        // The mapping itself is the claim under test: JP index 9 used to be
        // bound to TutorialData, which the JP disc doesn't ship at all.
        let descriptor = try XCTUnwrap(engine.commonTable(fileIndex: 9, japanese: true))
        XCTAssertEqual(descriptor.name, "ColosseumsUnknown")
        XCTAssertEqual(descriptor.structName, "PBRColosseumsUnknownJP")
        XCTAssertEqual(descriptor.entrySize, 0x3A)
        XCTAssertNil(engine.commonTable(named: "TutorialData")?.japaneseIndex,
                     "TutorialData is absent from the JP disc")

        let binary = try XCTUnwrap(corpus.members[9], "JP common.fsys member 9")
        let typed = try XCTUnwrap(engine.typeCommonTable(descriptor, binary: binary, structs: engine))
        XCTAssertEqual(typed.entries.count, 106, "same row count as the PAL table")

        var groupIndices = Set<Int>()
        var flagValues = Set<Int>()
        for (offset, row) in typed.entries.enumerated() {
            let context = "row \(offset)"
            // `index` running 182 + row is what ties these rows to the PAL
            // table's, and pins the record's start.
            XCTAssertEqual(try XCTUnwrap(row.get("index") as Int?, context), 182 + offset, context)
            // One quote set of 16 ids, not PAL's five — the whole of the
            // stride difference.
            let ids = try Self.uint16s(in: row, "quote_sets")
            XCTAssertEqual(ids.count, 16, "\(context): the JP disc carries a single quote set")
            groupIndices.insert(try XCTUnwrap(row.get("group_index"), context))
            flagValues.insert(try XCTUnwrap(row.get("flags"), context))
        }
        // The same ranges the PAL record documents — these sit at the very
        // end of the entry, so they only land correctly if everything before
        // them is the right width.
        XCTAssertEqual(groupIndices.min(), 17)
        XCTAssertEqual(groupIndices.max(), 54)
        XCTAssertEqual(flagValues, [0x81, 0x82])
    }

    /// The type chart identifies itself, so it can be asserted rather than
    /// assumed: if the columns of `PBRTypeMatchup` were named in the wrong
    /// order, or `PBRTypeEffectiveness`'s values were assigned the wrong way
    /// round, these matchups would not be the ones the series has.
    func testTypeMatchupChartIsTheSeriesChart() throws {
        guard let corpus else {
            throw XCTSkip("No PBR common.fsys — set GODDESS_PBR_COMMON to run.")
        }
        let engine = try PBREngine.defaults()
        let descriptor = try XCTUnwrap(engine.commonTable(named: "TypeMatchups"))
        let file = try XCTUnwrap(corpus.members[descriptor.index])

        let headerDefinition = try engine.getStruct("PBRCommonTableHeader")
        let header = StructData(
            definition: headerDefinition,
            data: try XCTUnwrap(file.read(atAddress: 0, length: headerDefinition.length))
        )
        let count: Int = try XCTUnwrap(header.get("entry_count"))
        let entriesOffset: Int = try XCTUnwrap(header.get("entries_offset"))

        let rowDefinition = try engine.getStruct("PBRTypeMatchup")
        XCTAssertEqual(rowDefinition.length, descriptor.entrySize)

        let columns = [
            "effect_against_normal", "effect_against_fighting", "effect_against_flying",
            "effect_against_poison", "effect_against_ground", "effect_against_rock",
            "effect_against_bug", "effect_against_ghost", "effect_against_steel",
            "effect_against_none", "effect_against_fire", "effect_against_water",
            "effect_against_grass", "effect_against_electric", "effect_against_psychic",
            "effect_against_ice", "effect_against_dragon", "effect_against_dark",
        ]
        XCTAssertEqual(columns.count, 18)

        func row(_ index: Int) throws -> StructData {
            StructData(
                definition: rowDefinition,
                data: try XCTUnwrap(file.read(
                    atAddress: entriesOffset + index * rowDefinition.length,
                    length: rowDefinition.length
                ))
            )
        }
        func effect(_ attacking: Int, _ column: String) throws -> String {
            let value: Enum.Case? = try row(attacking).get(column)
            return try XCTUnwrap(value, "row \(attacking).\(column)").name
        }

        // Attacking type index → the shared `Type` enum's order.
        XCTAssertEqual(try effect(0, "effect_against_ghost"), "NoEffect")           // Normal
        XCTAssertEqual(try effect(0, "effect_against_rock"), "NotVeryEffective")
        XCTAssertEqual(try effect(1, "effect_against_normal"), "SuperEffective")    // Fighting
        XCTAssertEqual(try effect(1, "effect_against_ghost"), "NoEffect")
        XCTAssertEqual(try effect(1, "effect_against_flying"), "NotVeryEffective")
        XCTAssertEqual(try effect(4, "effect_against_flying"), "NoEffect")          // Ground
        XCTAssertEqual(try effect(7, "effect_against_normal"), "NoEffect")          // Ghost
        XCTAssertEqual(try effect(10, "effect_against_grass"), "SuperEffective")    // Fire
        XCTAssertEqual(try effect(10, "effect_against_water"), "NotVeryEffective")
        XCTAssertEqual(try effect(11, "effect_against_fire"), "SuperEffective")     // Water
        XCTAssertEqual(try effect(13, "effect_against_ground"), "NoEffect")         // Electric
        XCTAssertEqual(try effect(16, "effect_against_dragon"), "SuperEffective")   // Dragon

        // Type slot 9 is unused and neutral in both directions.
        for column in columns {
            XCTAssertEqual(try effect(9, column), "Neutral", "unused type's own row")
        }
        for attacking in 0..<18 {
            XCTAssertEqual(try effect(attacking, "effect_against_none"), "Neutral",
                           "row \(attacking) against the unused type")
        }

        // Rows past the 18 types are the battle code's override rows: each is
        // either uniform, or neutral except for one or more `NoEffect`
        // columns — an immunity granted by an ability or effect. (Row 21
        // grants two, against Poison and Steel.)
        XCTAssertGreaterThanOrEqual(count, 18)
        for index in 18..<count {
            let values = try columns.map { try effect(index, $0) }
            if Set(values).count == 1 { continue }
            let exceptions = Set(values.filter { $0 != "Neutral" })
            XCTAssertEqual(exceptions, ["NoEffect"],
                           "override row \(index) should be neutral but for immunities")
        }
    }
}
