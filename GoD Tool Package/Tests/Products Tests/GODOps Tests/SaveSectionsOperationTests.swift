//
//  SaveSectionsOperationTests.swift
//  GODOpsTests
//
//  Runs the real sub-section dump/build against an InMemoryFST. These
//  operations sit either side of the save dump/build: they take one raw
//  section `.bin`, decompose it against a layout, and recompose it — so the
//  contract under test is that a decompose/recompose round trip is byte-exact
//  and that an edit to an artifact actually reaches the binary.
//
//  The flag fixture deliberately includes a bank-straddling flag, which is the
//  case `_flagGet`/`_flagSet` handle by reaching into the next word and the
//  easiest thing for a codec to get wrong. Its bytes are written as raw words
//  rather than through `XDFlagTable`, so the fixture can't agree with a broken
//  codec.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import XD
@testable import GODOps

final class SaveSectionsOperationTests: XCTestCase {

    private let sectionName = "Flags"
    private let binaryName = "08-Flags.bin"
    private let sectionLength = 0x6B4

    // MARK: - Fixtures

    /// A flag table with a spread of widths. Flag 2 is 8 bits starting at bit
    /// 31 of bank 1, i.e. it straddles the word boundary.
    private func flagTableCSV() -> String {
        func row(bank: Int, bits: Int, next: Int) -> String {
            "\((bank << 6) | bits),0,0,\(next)"
        }
        return ([
            "bankAndBitLength,reserved,bitPosition,nextFlagID",
            row(bank: 1, bits: 1, next: 1),    // 0: bank 1, bit 0
            row(bank: 1, bits: 30, next: 2),   // 1: bank 1, bits 1-30
            row(bank: 1, bits: 8, next: 3),    // 2: bank 1, bits 31-38 — straddles
            row(bank: 3, bits: 32, next: 4),   // 3: bank 3, a whole word
            row(bank: 3, bits: 12, next: -1),  // 4: bank 3, bits 32-43
        ].joined(separator: "\n")) + "\n"
    }

    private func layoutJSON() -> String {
        """
        { "sections": { "Flags": { "chunks": [
            { "flags": { "name": "flags", "offset": 0, "banks": [
                {"name": "FlagLevel0", "length": 32},
                {"name": "FlagLevel1", "length": 128},
                {"name": "FlagLevel2", "length": 1536} ] } },
            { "struct": { "name": "tail", "offset": 1696, "type": "XDSaveFlagsTail" } }
        ] } } }
        """
    }

    /// Only bits the table above covers are set, so a rebuild — which zeroes
    /// everything no flag claims — can be byte-exact.
    private func sectionBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: sectionLength)
        func word(_ at: Int, _ value: UInt32) {
            bytes[at]     = UInt8((value >> 24) & 0xFF)
            bytes[at + 1] = UInt8((value >> 16) & 0xFF)
            bytes[at + 2] = UInt8((value >> 8) & 0xFF)
            bytes[at + 3] = UInt8(value & 0xFF)
        }
        word(0x000, 0xFFFF_FFFF)   // bank 1, bits 0-31
        word(0x004, 0x0000_007F)   // bank 1, bits 32-38
        word(0x0A0, 0xDEAD_BEEF)   // bank 3, bits 0-31
        word(0x0A4, 0x0000_0ABC)   // bank 3, bits 32-43
        for i in 0..<0x14 { bytes[0x6A0 + i] = UInt8(0x40 + i) }   // the tail
        return bytes
    }

    private func makeProject() throws -> (fst: InMemoryFST, slot: Folder, layout: File, table: File, engines: [Folder]) {
        let fst = InMemoryFST()
        let engine = installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let slot = Folder("/project/Source/Save/Latest Slot")
        try fst.writeFile(GoDData(byteStream: sectionBytes(), byteOrder: .big),
                          at: slot.file(binaryName), overwrite: true)
        let layout = File("/project/layout.json")
        try fst.writeFile(GoDData(string: layoutJSON(), format: .utf8), at: layout, overwrite: true)
        let table = File("/project/flags.csv")
        try fst.writeFile(GoDData(string: flagTableCSV(), format: .utf8), at: table, overwrite: true)
        return (fst, slot, layout, table, [engine])
    }

    private func runDump(_ p: (fst: InMemoryFST, slot: Folder, layout: File, table: File, engines: [Folder]),
                         flagsTable: File? = nil) throws {
        let config = SaveSectionsOps.DumpConfig(operations: [
            OperationConfig(operation: .dumpSaveSections(
                slotFolder: p.slot, overwrite: true, layout: p.layout,
                engines: p.engines, flagsTable: flagsTable ?? p.table
            ), enabled: .yes)
        ])
        try SaveSectionsOps.dump(config: config, settings: .default, fileSystem: p.fst, logger: SilentLogger())
    }

    private func runBuild(_ p: (fst: InMemoryFST, slot: Folder, layout: File, table: File, engines: [Folder])) throws {
        let config = SaveSectionsOps.BuildConfig(operations: [
            OperationConfig(operation: .buildSaveSections(
                slotFolder: p.slot, overwrite: true, layout: p.layout,
                engines: p.engines, flagsTable: p.table
            ), enabled: .yes)
        ])
        try SaveSectionsOps.build(config: config, settings: .default, fileSystem: p.fst, logger: SilentLogger())
    }

    // MARK: - Round trip

    func testDecomposeThenRecomposeIsByteExact() throws {
        let p = try makeProject()
        try runDump(p)

        // The raw binary is never deleted — it is the save build's input.
        XCTAssertNotNil(p.fst.readFile(at: p.slot.file(binaryName)), "the section binary must survive the dump")

        let folder = p.slot.folder("08-Flags")
        XCTAssertNotNil(p.fst.readFile(at: folder.file("flags.csv")))
        XCTAssertNotNil(p.fst.readFile(at: folder.file("tail.json")))

        // Wipe the binary so the rebuild can't accidentally inherit it.
        try p.fst.writeFile(GoDData(length: sectionLength, byteOrder: .big),
                            at: p.slot.file(binaryName), overwrite: true)
        try runBuild(p)

        let rebuilt = try XCTUnwrap(p.fst.readFile(at: p.slot.file(binaryName))?.allData).rawBytes
        XCTAssertEqual(rebuilt, sectionBytes(), "the section must recompose byte for byte from its artifacts")
    }

    func testTheFlagCSVCarriesOnlyIdAndValue() throws {
        let p = try makeProject()
        try runDump(p)
        let csv = try XCTUnwrap(p.fst.readFile(at: p.slot.folder("08-Flags").file("flags.csv"))?.allData)
        let rows = try CSV.parse(String(decoding: csv.rawBytes, as: UTF8.self))
        XCTAssertEqual(rows.first, ["id", "value"], "bank/width/position are derivable, so they aren't columns")
        XCTAssertEqual(rows.count - 1, 5)
        // Values read back through the codec, including the straddling flag.
        let values = Dictionary(uniqueKeysWithValues: rows.dropFirst().map { ($0[0], $0[1]) })
        XCTAssertEqual(values["0"], "1")
        XCTAssertEqual(values["1"], "1073741823")   // 0x3FFFFFFF
        XCTAssertEqual(values["2"], "255")          // straddles the word boundary
        XCTAssertEqual(values["3"], "3735928559")   // 0xDEADBEEF
        XCTAssertEqual(values["4"], "2748")         // 0xABC
    }

    func testEditingAFlagReachesTheBinary() throws {
        let p = try makeProject()
        try runDump(p)
        let csvFile = p.slot.folder("08-Flags").file("flags.csv")
        try p.fst.writeFile(
            GoDData(string: "id,value\n3,305419896\n", format: .utf8),   // 0x12345678
            at: csvFile, overwrite: true
        )
        try runBuild(p)
        let rebuilt = try XCTUnwrap(p.fst.readFile(at: p.slot.file(binaryName))?.allData).rawBytes
        // Flag 3 is bank 3's first word.
        XCTAssertEqual(Array(rebuilt[0xA0..<0xA4]), [0x12, 0x34, 0x56, 0x78])
        // A partial CSV is valid: flags it omits rebuild as zero.
        XCTAssertEqual(Array(rebuilt[0x00..<0x04]), [0, 0, 0, 0])
    }

    /// A layout that describes only part of a section still has to be
    /// lossless — the bytes it doesn't claim are kept verbatim.
    func testUnclaimedBytesSurviveAsGapFiles() throws {
        var p = try makeProject()
        p.layout = File("/project/partial.json")
        try p.fst.writeFile(GoDData(string: """
        { "sections": { "Flags": { "chunks": [
            { "struct": { "name": "tail", "offset": 1696, "type": "XDSaveFlagsTail" } }
        ] } } }
        """, format: .utf8), at: p.layout, overwrite: true)

        try runDump(p)
        let gap = p.slot.folder("08-Flags").file(SaveSectionsOps.gapFilename(offset: 0))
        let gapBytes = try XCTUnwrap(p.fst.readFile(at: gap)?.allData)
        XCTAssertEqual(gapBytes.length, 0x6A0, "everything before the tail is one unclaimed run")

        try p.fst.writeFile(GoDData(length: sectionLength, byteOrder: .big),
                            at: p.slot.file(binaryName), overwrite: true)
        try runBuild(p)
        let rebuilt = try XCTUnwrap(p.fst.readFile(at: p.slot.file(binaryName))?.allData).rawBytes
        XCTAssertEqual(rebuilt, sectionBytes())
    }

    // MARK: - Rejections

    func testOverlappingChunksAreRejected() throws {
        var p = try makeProject()
        p.layout = File("/project/overlap.json")
        try p.fst.writeFile(GoDData(string: """
        { "sections": { "Flags": { "chunks": [
            { "struct": { "name": "a", "offset": 0, "type": "XDSaveFlagsTail" } },
            { "struct": { "name": "b", "offset": 4, "type": "XDSaveFlagsTail" } }
        ] } } }
        """, format: .utf8), at: p.layout, overwrite: true)
        XCTAssertThrowsError(try runDump(p)) { error in
            guard case SaveSectionsOpsErrors.overlappingChunks = error else {
                return XCTFail("Expected overlappingChunks, got \(error)")
            }
        }
    }

    func testAChunkPastTheSectionEndIsRejected() throws {
        var p = try makeProject()
        p.layout = File("/project/oob.json")
        try p.fst.writeFile(GoDData(string: """
        { "sections": { "Flags": { "chunks": [
            { "struct": { "name": "a", "offset": 1700, "type": "XDSaveFlagsTail" } }
        ] } } }
        """, format: .utf8), at: p.layout, overwrite: true)
        XCTAssertThrowsError(try runDump(p)) { error in
            guard case SaveSectionsOpsErrors.chunkOutOfBounds = error else {
                return XCTFail("Expected chunkOutOfBounds, got \(error)")
            }
        }
    }

    func testFlagChunkWithoutATableIsRejected() throws {
        let p = try makeProject()
        let config = SaveSectionsOps.DumpConfig(operations: [
            OperationConfig(operation: .dumpSaveSections(
                slotFolder: p.slot, overwrite: true, layout: p.layout,
                engines: p.engines, flagsTable: nil
            ), enabled: .yes)
        ])
        XCTAssertThrowsError(
            try SaveSectionsOps.dump(config: config, settings: .default, fileSystem: p.fst, logger: SilentLogger())
        ) { error in
            guard case SaveSectionsOpsErrors.missingFlagTable = error else {
                return XCTFail("Expected missingFlagTable, got \(error)")
            }
        }
    }

    // MARK: - The table codec

    func testBitPositionsAreARunningTotalPerBank() throws {
        let (table, _) = try XDFlagTable.load(csv: flagTableCSV())
        XCTAssertEqual(table.flags.map(\.bank), [1, 1, 1, 3, 3])
        XCTAssertEqual(table.flags.map(\.bitLength), [1, 30, 8, 32, 12])
        XCTAssertEqual(table.flags.map(\.bitPosition), [0, 1, 31, 0, 32])
        XCTAssertEqual(table.bitsNeeded(inBank: 1), 39)
        XCTAssertEqual(table.bitsNeeded(inBank: 3), 44)
    }

    /// Read by column name, not offset — which is what lets XD's 6-byte and
    /// Colosseum's 8-byte descriptors share this codec.
    func testTheTableIsReadByColumnNameNotOffset() throws {
        let reordered = """
        nextFlagID,category,bankAndBitLength,bitPosition
        1,0,65,0
        -1,0,194,0
        """
        let (table, _) = try XDFlagTable.load(csv: reordered)
        XCTAssertEqual(table.flags.map(\.bank), [1, 3])
        XCTAssertEqual(table.flags.map(\.bitLength), [1, 2])
        XCTAssertEqual(table.flags.map(\.nextFlagID), [1, -1])
    }

    // MARK: - Field-addressed banks (Colosseum's shape)

    /// Colosseum's flags sit inside `Tail`, which is itself a struct, so the
    /// section dumps as JSON and there is no `.bin` to slice. The layout
    /// addresses the banks by property instead, and the build writes the
    /// decoded values back into that JSON — which the save build reads next.
    private func makeTypedSectionProject() throws -> (fst: InMemoryFST, slot: Folder, layout: File, table: File, engines: [Folder]) {
        let fst = InMemoryFST()
        let engine = installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let slot = Folder("/project/Source/Save/Latest Slot")

        // A typed section artifact: the banks as named byte arrays, plus an
        // unrelated property that must survive untouched.
        var level0 = [Int](repeating: 0, count: 32)
        level0[0] = 0xFF; level0[1] = 0xFF; level0[2] = 0xFF; level0[3] = 0xFF
        level0[4] = 0x00; level0[5] = 0x00; level0[6] = 0x00; level0[7] = 0x7F
        var level2 = [Int](repeating: 0, count: 1536)
        level2[0] = 0xDE; level2[1] = 0xAD; level2[2] = 0xBE; level2[3] = 0xEF
        level2[4] = 0x00; level2[5] = 0x00; level2[6] = 0x0A; level2[7] = 0xBC
        let json: [String: Any] = ["type": "ColoSaveTailStub", "data": [
            "somethingElse": 4242,
            "flagLevel0": level0,
            "flagLevel1": [Int](repeating: 0, count: 128),
            "flagLevel2": level2,
        ]]
        let encoded = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try fst.writeFile(GoDData(byteStream: [UInt8](encoded), byteOrder: .big),
                          at: slot.file("06-Tail.json"), overwrite: true)

        let layout = File("/project/typed-layout.json")
        try fst.writeFile(GoDData(string: """
        { "sections": { "Tail": { "chunks": [
            { "flags": { "name": "flags", "banks": [
                {"name": "FlagLevel0", "length": 32,   "field": "flagLevel0"},
                {"name": "FlagLevel1", "length": 128,  "field": "flagLevel1"},
                {"name": "FlagLevel2", "length": 1536, "field": "flagLevel2"} ] } }
        ] } } }
        """, format: .utf8), at: layout, overwrite: true)

        let table = File("/project/flags.csv")
        try fst.writeFile(GoDData(string: flagTableCSV(), format: .utf8), at: table, overwrite: true)
        return (fst, slot, layout, table, [engine])
    }

    func testFieldAddressedBanksDecodeFromATypedSection() throws {
        let p = try makeTypedSectionProject()
        try runDump(p)
        let csv = try XCTUnwrap(p.fst.readFile(at: p.slot.folder("06-Tail").file("flags.csv"))?.allData)
        let rows = try CSV.parse(String(decoding: csv.rawBytes, as: UTF8.self))
        let values = Dictionary(uniqueKeysWithValues: rows.dropFirst().map { ($0[0], $0[1]) })
        // Same fixture values as the byte-addressed case, reached through the
        // section's properties instead of a byte range.
        XCTAssertEqual(values["2"], "255", "the word-straddling flag still decodes")
        XCTAssertEqual(values["3"], "3735928559")
        XCTAssertEqual(values["4"], "2748")
        // The section's `.bin` is absent here, and that must not be an error.
        XCTAssertNil(p.fst.readFile(at: p.slot.file("06-Tail.bin")))
    }

    func testFieldAddressedBanksAreWrittenBackIntoTheSectionJSON() throws {
        let p = try makeTypedSectionProject()
        try runDump(p)
        try p.fst.writeFile(
            GoDData(string: "id,value\n3,305419896\n", format: .utf8),   // 0x12345678
            at: p.slot.folder("06-Tail").file("flags.csv"), overwrite: true
        )
        try runBuild(p)

        let rebuilt = try XCTUnwrap(p.fst.readFile(at: p.slot.file("06-Tail.json"))?.allData)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: rebuilt.data) as? [String: Any])
        let data = try XCTUnwrap(root["data"] as? [String: Any])
        let level2 = try XCTUnwrap(data["flagLevel2"] as? [Int])
        XCTAssertEqual(Array(level2[0..<4]), [0x12, 0x34, 0x56, 0x78], "flag 3 is bank 3's first word")
        // Properties the layout says nothing about are left exactly as they were.
        XCTAssertEqual(data["somethingElse"] as? Int, 4242)
        XCTAssertEqual((data["flagLevel1"] as? [Int])?.count, 128)
    }
}
