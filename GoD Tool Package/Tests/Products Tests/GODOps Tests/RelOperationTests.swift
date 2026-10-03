//
//  RelOperationTests.swift
//  GODOpsTests
//
//  The REL operation family used to be disabled behind `RelOperationsGate`
//  and these tests only documented that. The gate is open, so they now cover
//  the real behaviour: a disassembly writes per-section artifacts and a
//  `<name>.rel.json` manifest, an assembly rebuilds the binary from the
//  manifest plus the chunk files byte-for-byte, and the batch wrappers keep
//  going when one member fails.
//
//  The manifest carries no bytes, so the chunk files *are* the module:
//  `testEditedTableCSVLandsInRebuiltRel` edits a CSV cell and a pointer and
//  finds both in the rebuilt `.rel`.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
import Disassembler
import XD
import FixtureCatalog
@testable import GODOps

final class RelOperationTests: XCTestCase {

    private func installXDEngine(in fst: InMemoryFST) throws -> Folder {
        installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
    }

    /// Writes the shared REL fixture and returns its bytes.
    @discardableResult
    private func writeSampleRel(
        at path: File,
        in fst: InMemoryFST
    ) throws -> GoDData {
        let bytes = try RELFixtures.model().binaryData
        try fst.writeFile(bytes, at: path, overwrite: true)
        return bytes
    }

    // MARK: - relDisassembly

    func testRelDisassemblyWritesManifestAndSections() throws {
        let fst = InMemoryFST()
        try writeSampleRel(at: File("/project/sample.rel"), in: fst)

        let config = RelDisassembly.Config(
            relPath: File("/project/sample.rel"),
            outputFolder: Folder("/project/Out"),
            dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        )
        try RelDisassembly.disassemble(
            config: config, settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        // The lossless whole-file manifest is what the assembler consumes.
        XCTAssertNotNil(
            fst.readFile(at: File("/project/Out/sample.rel.json")),
            "disassembly must emit the canonical <name>.rel.json"
        )
        // At least one text section came out as assembly source.
        XCTAssertNotNil(
            fst.readFile(at: File("/project/Out/text1.s")),
            "the fixture's text section should disassemble to text1.s"
        )
    }

    func testRelDisassemblyThrowsWhenRelMissing() throws {
        let fst = InMemoryFST()
        let config = RelDisassembly.Config(
            relPath: File("/project/nope.rel"),
            outputFolder: Folder("/project/Out"),
            dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        )
        XCTAssertThrowsError(
            try RelDisassembly.disassemble(
                config: config, settings: .default, fileSystem: fst, logger: SilentLogger()
            )
        ) { error in
            guard case RelDisassemblyErrors.relNotFound = error else {
                return XCTFail("Expected relNotFound, got \(error)")
            }
        }
    }

    // MARK: - relAssembly

    func testRelDisassemblyThenAssemblyRoundTripsBytes() throws {
        let fst = InMemoryFST()
        let original = try writeSampleRel(at: File("/project/sample.rel"), in: fst)

        try RelDisassembly.disassemble(
            config: .init(
                relPath: File("/project/sample.rel"),
                outputFolder: Folder("/project/Out"),
                dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        try RelAssembly.assemble(
            config: .init(
                inputFolder: Folder("/project/Out"),
                relName: "sample",
                outputPath: File("/project/rebuilt.rel")
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let rebuilt = fst.readFile(at: File("/project/rebuilt.rel"))?.allData
        XCTAssertNotNil(rebuilt, "assembly must write the rebuilt REL")
        XCTAssertEqual(
            rebuilt?.rawBytes, original.rawBytes,
            "REL rebuilt from its own manifest must be byte-identical"
        )
    }

    func testRelAssemblyThrowsWhenManifestMissing() {
        XCTAssertThrowsError(
            try RelAssembly.assemble(
                config: .init(
                    inputFolder: Folder("/project/In"),
                    relName: "sample",
                    outputPath: File("/project/sample.rel")
                ),
                settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger()
            )
        ) { error in
            guard case RelAssemblyErrors.manifestNotFound = error else {
                return XCTFail("Expected manifestNotFound, got \(error)")
            }
        }
    }

    // MARK: - commonRelDump (game-engine resolution runs before anything else)

    func testCommonRelDumpWithBogusEngineThrowsUnknownGameEngine() {
        let config = CommonRelDump.Config(
            relPath: File("/project/common.rel"),
            outputFolder: Folder("/project/Out"),
            overwrite: true,
            dolphinEngine: Folder("/project/Engines/Dolphin"),
            gameEngine: Folder("/project/NotAnEngine")
        )
        XCTAssertThrowsError(
            try CommonRelDump.dump(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case CommonRelErrors.unknownGameEngine = error else {
                return XCTFail("Expected CommonRelErrors.unknownGameEngine, got \(error)")
            }
        }
    }

    func testCommonRelDumpWritesManifestForAValidEngine() throws {
        let fst = InMemoryFST()
        let gameEngine = try installXDEngine(in: fst)
        try writeSampleRel(at: File("/project/common.rel"), in: fst)

        try CommonRelDump.dump(
            config: .init(
                relPath: File("/project/common.rel"),
                outputFolder: Folder("/project/Out"),
                overwrite: true,
                dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst),
                gameEngine: gameEngine
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(
            fst.readFile(at: File("/project/Out/common.rel.json")),
            "common.rel dump must emit the canonical manifest"
        )
    }

    // MARK: - typed tables name pointer fields through relocations

    /// A pointer inside a REL's data is a relocation: the word on disc is 0
    /// and the target lives in the relocation table. A typed table with a
    /// `.label` field has to show the relocation's target name in that
    /// column — and leave the cell empty where no relocation exists, because
    /// that word is a null pointer, not a pointer to address 0.
    func testTypedTableNamesPointerFieldsFromRelocations() throws {
        let own: UInt32 = 0x2A
        let dol: UInt32 = 0

        // One ADDR32 word in the text section aimed at the data section's
        // first byte, so the table start gets a self symbol (pointer index
        // 0) that the symbol index can name.
        let text: [RELFile.TextInstruction] = [
            .init(raw: 0x4E800020),
            .init(raw: 0x00000000, ref: .init(moduleID: own, section: 2, offset: 0x00), fixup: .addr32),
        ]
        // Two Pokespot entries (0x1C bytes each): six flag ids, then the
        // encounter-table pointer. Entry 0's pointer is relocated to a DOL
        // address; entry 1's is null.
        func flagIDs(_ first: UInt8) -> [UInt8] {
            (0 ..< 6).flatMap { [0, 0, 0, first + UInt8($0)] }
        }
        let data: [RELFile.DataChunk] = [
            .binary(bytes: flagIDs(1)),
            .pointer(ref: .init(moduleID: dol, section: 11, offset: 0x804E89B4), restValue: 0),
            .binary(bytes: flagIDs(0x11) + [0, 0, 0, 0]),
        ]
        var rel = RELFile(
            moduleID: own,
            version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text(text)),
                .init(index: 2, body: .data(data)),
            ],
            importedModules: [own, dol]
        )
        rel.name = "spots"
        rel.prologSection = 1
        rel.prologOffset = 0
        rel.sectionAlign = 4
        rel.bssAlign = 8

        let fst = InMemoryFST()
        try fst.writeFile(try rel.binaryData, at: File("/project/spots.rel"), overwrite: true)
        writeText(#"{"symbols": {"0": "Pokespots"}}"#, at: File("/project/symbols.json"), in: fst)
        writeText(
            #"{"chunks": [{"table": {"name": "Pokespots", "start": "Pokespots", "entryType": "Pokespot"}}]}"#,
            at: File("/project/typemap.json"), in: fst
        )
        let gameEngine = try installXDEngine(in: fst)

        try RelDisassembly.disassemble(
            config: .init(
                relPath: File("/project/spots.rel"),
                outputFolder: Folder("/project/Out"),
                dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst),
                symbolIndexPath: File("/project/symbols.json"),
                typeMapPath: File("/project/typemap.json"),
                engines: [gameEngine]
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let csv = try XCTUnwrap(
            fst.readFile(at: File("/project/Out/data2/Pokespots.csv"))?.allData,
            "a table whose only pointer is a relocation must still dump as CSV"
        ).string(format: .utf8)
        let rows = csv.split(separator: "\n").map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        XCTAssertEqual(rows.count, 3, "header + two entries")
        let column = try XCTUnwrap(rows[0].firstIndex(of: "encounter_table_pointer"))
        XCTAssertEqual(rows[1][column], "dol_804E89B4", "relocated pointer names its target")
        XCTAssertEqual(rows[2][column], "", "unrelocated pointer is null, not lbl_00000000")
        XCTAssertEqual(rows[1][0], "1", "the flag ids before the pointer come through untouched")
        XCTAssertEqual(rows[2][0], "17")
    }

    // MARK: - edits to the chunk files reach the rebuilt binary

    /// The manifest carries no bytes, so the CSV is the table. Dump a typed
    /// REL, rebuild it untouched (byte-identical), then edit the CSV — a
    /// value in one entry, and a null pointer turned into a relocation to a
    /// DOL symbol — and rebuild again: both edits must be in the `.rel`.
    func testEditedTableCSVLandsInRebuiltRel() throws {
        let own: UInt32 = 0x2A
        let dol: UInt32 = 0
        let text: [RELFile.TextInstruction] = [
            .init(raw: 0x4E800020),
            .init(raw: 0x00000000, ref: .init(moduleID: own, section: 2, offset: 0x00), fixup: .addr32),
        ]
        func flagIDs(_ first: UInt8) -> [UInt8] {
            (0 ..< 6).flatMap { [0, 0, 0, first + UInt8($0)] }
        }
        let data: [RELFile.DataChunk] = [
            .binary(bytes: flagIDs(1)),
            .pointer(ref: .init(moduleID: dol, section: 11, offset: 0x804E89B4), restValue: 0),
            .binary(bytes: flagIDs(0x11) + [0, 0, 0, 0]),
        ]
        var rel = RELFile(
            moduleID: own,
            version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text(text)),
                .init(index: 2, body: .data(data)),
            ],
            importedModules: [own, dol]
        )
        rel.name = "spots"
        rel.prologSection = 1
        rel.sectionAlign = 4
        rel.bssAlign = 8
        let original = try rel.binaryData

        let fst = InMemoryFST()
        try fst.writeFile(original, at: File("/project/spots.rel"), overwrite: true)
        writeText(#"{"symbols": {"0": "Pokespots"}}"#, at: File("/project/symbols.json"), in: fst)
        writeText(
            #"{"chunks": [{"table": {"name": "Pokespots", "start": "Pokespots", "entryType": "Pokespot"}}]}"#,
            at: File("/project/typemap.json"), in: fst
        )
        let gameEngine = try installXDEngine(in: fst)
        let dolphin = installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)

        try RelDisassembly.disassemble(
            config: .init(
                relPath: File("/project/spots.rel"),
                outputFolder: Folder("/project/Out"),
                dolphinEngine: dolphin,
                symbolIndexPath: File("/project/symbols.json"),
                typeMapPath: File("/project/typemap.json"),
                engines: [gameEngine]
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        // The manifest names the CSV and the type it was mapped to, and
        // nothing in it carries bytes.
        let manifestData = try XCTUnwrap(fst.readFile(at: File("/project/Out/spots.rel.json"))?.allData)
        let manifest = try RelManifest(json: manifestData)
        let tableChunk = try XCTUnwrap(manifest.sections.first { $0.index == 2 }?.chunks?.first)
        XCTAssertEqual(tableChunk.type, .table)
        XCTAssertEqual(tableChunk.file, "data2/Pokespots.csv", "chunk paths are relative to the module folder")
        XCTAssertEqual(tableChunk.structType, "Pokespot", "manifest records the mapped type")
        XCTAssertEqual(tableChunk.count, 2)
        XCTAssertFalse(manifestData.string(format: .utf8).contains("\"bytes\""), "no chunk bytes in the manifest")
        XCTAssertNil(fst.readFile(at: File("/project/Out/data2/manifest.json")), "no per-section manifest any more")

        func assemble(to path: File) throws -> RELFile {
            try RelAssembly.assemble(
                config: .init(
                    inputFolder: Folder("/project/Out"), relName: "spots", outputPath: path,
                    engines: [gameEngine]
                ),
                settings: .default, fileSystem: fst, logger: SilentLogger()
            )
            let bytes = try XCTUnwrap(fst.readFile(at: path)?.allData)
            return try RELFile(binary: bytes, name: "spots")
        }

        // Untouched: byte-identical.
        _ = try assemble(to: File("/project/rebuilt.rel"))
        XCTAssertEqual(fst.readFile(at: File("/project/rebuilt.rel"))?.allData?.rawBytes, original.rawBytes,
                       "a typed dump must rebuild byte-identically before any edit")

        // Edit the CSV: entry 1's first flag id 17 → 99, and its null
        // encounter pointer → the same DOL symbol entry 0 uses.
        let csvFile = File("/project/Out/data2/Pokespots.csv")
        var rows = try XCTUnwrap(fst.readFile(at: csvFile)?.allData).string(format: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        let pointerColumn = try XCTUnwrap(rows[0].firstIndex(of: "encounter_table_pointer"))
        XCTAssertEqual(rows[2][0], "17")
        rows[2][0] = "99"
        rows[2][pointerColumn] = "dol_804E89B4"
        let edited = rows.map { $0.joined(separator: ",") }.joined(separator: "\n")
        try fst.writeFile(GoDData(string: edited, format: .utf8), at: csvFile, overwrite: true)

        let rebuilt = try assemble(to: File("/project/edited.rel"))
        guard case .data(let chunks) = rebuilt.sections[2].body else {
            return XCTFail("section 2 should still be data")
        }
        // Flatten the section back to bytes and pointers.
        var bytes = [UInt8]()
        var pointers: [Int: RELFile.SymbolRef] = [:]
        for chunk in chunks {
            switch chunk {
            case .binary(let b): bytes.append(contentsOf: b)
            case .pointer(let ref, let rest):
                pointers[bytes.count] = ref
                bytes.append(contentsOf: [UInt8(rest >> 24), UInt8((rest >> 16) & 0xFF), UInt8((rest >> 8) & 0xFF), UInt8(rest & 0xFF)])
            }
        }
        XCTAssertEqual(bytes.count, 0x38, "two 0x1C entries")
        XCTAssertEqual(bytes[0x1C + 3], 99, "the edited flag id is in the binary")
        XCTAssertEqual(pointers[0x18], .init(moduleID: dol, section: 11, offset: 0x804E89B4), "entry 0's pointer survives")
        XCTAssertEqual(pointers[0x1C + 0x18], .init(moduleID: dol, section: 11, offset: 0x804E89B4),
                       "the pointer added in the CSV became a relocation to the symbol's target")
    }

    // MARK: - Derived counts

    /// A two-entry `Pokespot` table followed by its count word, both
    /// relocation targets so each is its own symbol.
    private func writeCountedRel(countWord: UInt32, typeMap: String, in fst: InMemoryFST) throws -> (engine: Folder, dolphin: Folder) {
        let own: UInt32 = 0x2A
        let text: [RELFile.TextInstruction] = [
            .init(raw: 0x4E800020),
            .init(raw: 0, ref: .init(moduleID: own, section: 2, offset: 0x00), fixup: .addr32),
            .init(raw: 0, ref: .init(moduleID: own, section: 2, offset: 0x38), fixup: .addr32),
        ]
        func entry(_ first: UInt8) -> [UInt8] { (0 ..< 7).flatMap { [0, 0, 0, first + UInt8($0)] } }
        let word = [UInt8(countWord >> 24), UInt8((countWord >> 16) & 0xFF), UInt8((countWord >> 8) & 0xFF), UInt8(countWord & 0xFF)]
        var rel = RELFile(
            moduleID: own, version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text(text)),
                .init(index: 2, body: .data([.binary(bytes: entry(1) + entry(0x11) + word)])),
            ],
            importedModules: [own]
        )
        rel.name = "spots"
        rel.prologSection = 1
        rel.sectionAlign = 4
        rel.bssAlign = 8
        try fst.writeFile(try rel.binaryData, at: File("/project/spots.rel"), overwrite: true)
        writeText(#"{"symbols": {"0": "Pokespots", "1": "NumberOfPokespots"}}"#, at: File("/project/symbols.json"), in: fst)
        writeText(typeMap, at: File("/project/typemap.json"), in: fst)
        let engine = try installXDEngine(in: fst)
        let dolphin = installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        return (engine, dolphin)
    }

    private let countedTypeMap = """
    {"chunks": [
      {"table": {"name": "Pokespots", "start": "Pokespots", "entryType": "Pokespot"}},
      {"count": {"label": "NumberOfPokespots", "table": "Pokespots"}}
    ]}
    """

    private func disassembleSpots(engine: Folder, dolphin: Folder, fst: InMemoryFST, logger: Logger = SilentLogger()) throws {
        try RelDisassembly.disassemble(
            config: .init(
                relPath: File("/project/spots.rel"), outputFolder: Folder("/project/Out"), dolphinEngine: dolphin,
                symbolIndexPath: File("/project/symbols.json"), typeMapPath: File("/project/typemap.json"),
                engines: [engine]
            ),
            settings: .default, fileSystem: fst, logger: logger
        )
    }

    private func assembleSpots(engine: Folder, fst: InMemoryFST) throws -> [UInt8] {
        try RelAssembly.assemble(
            config: .init(inputFolder: Folder("/project/Out"), relName: "spots",
                          outputPath: File("/project/rebuilt.rel"), engines: [engine]),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        let rebuilt = try RELFile(binary: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.rel"))?.allData), name: "spots")
        guard case .data(let chunks) = rebuilt.sections.first(where: { $0.index == 2 })?.body else {
            XCTFail("no data section"); return []
        }
        return chunks.flatMap { chunk -> [UInt8] in
            if case .binary(let b) = chunk { return b }
            return [0, 0, 0, 0]
        }
    }

    /// A count word is not dumped as a value: the manifest records which
    /// table it counts, and the build writes that table's entry count.
    func testCountIsDerivedFromItsTable() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeCountedRel(countWord: 2, typeMap: countedTypeMap, in: fst)
        let original = try XCTUnwrap(fst.readFile(at: File("/project/spots.rel"))?.allData?.rawBytes)
        try disassembleSpots(engine: engine, dolphin: dolphin, fst: fst)

        let manifest = try RelManifest(json: try XCTUnwrap(fst.readFile(at: File("/project/Out/spots.rel.json"))?.allData))
        let count = try XCTUnwrap(manifest.sections.first { $0.index == 2 }?.chunks?.first { $0.label == "NumberOfPokespots" })
        XCTAssertEqual(count.type, .count)
        XCTAssertEqual(count.countOf, "Pokespots")
        XCTAssertNil(fst.readFile(at: File("/project/Out/data2/NumberOfPokespots.bin")), "a derived value has no file")

        _ = try assembleSpots(engine: engine, fst: fst)
        XCTAssertEqual(fst.readFile(at: File("/project/rebuilt.rel"))?.allData?.rawBytes, original,
                       "untouched, the derived count reproduces the module")

        // A row added to the CSV is a row the count reports.
        let csvFile = File("/project/Out/data2/Pokespots.csv")
        var lines = try XCTUnwrap(fst.readFile(at: csvFile)?.allData).string(format: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines.append(try XCTUnwrap(lines.last))
        writeText(lines.joined(separator: "\n") + "\n", at: csvFile, in: fst)

        let bytes = try assembleSpots(engine: engine, fst: fst)
        XCTAssertEqual(bytes.count, 3 * 0x1C + 4, "a counted table is sized by its CSV")
        XCTAssertEqual(Array(bytes[(3 * 0x1C)...]), [0, 0, 0, 3], "the count follows it")
    }

    /// A count narrower than the space before the next symbol keeps the rest
    /// as its own chunk, beside it in the same folder.
    func testANarrowCountKeepsTheBytesAfterIt() throws {
        let fst = InMemoryFST()
        let typeMap = """
        {"chunks": [
          {"table": {"name": "Pokespots", "start": "Pokespots", "entryType": "Pokespot"}},
          {"count": {"label": "NumberOfPokespots", "table": "Pokespots", "type": "uint16"}}
        ]}
        """
        // The word 0x0002ABCD: a uint16 count of 2, then two bytes of padding.
        let (engine, dolphin) = try writeCountedRel(countWord: 0x0002_ABCD, typeMap: typeMap, in: fst)
        let original = try XCTUnwrap(fst.readFile(at: File("/project/spots.rel"))?.allData?.rawBytes)
        try disassembleSpots(engine: engine, dolphin: dolphin, fst: fst)

        let manifest = try RelManifest(json: try XCTUnwrap(fst.readFile(at: File("/project/Out/spots.rel.json"))?.allData))
        let chunks = try XCTUnwrap(manifest.sections.first { $0.index == 2 }?.chunks)
        XCTAssertEqual(chunks.first { $0.label == "NumberOfPokespots" }?.countType, .uint16)
        let tail = try XCTUnwrap(chunks.first { $0.label == "NumberOfPokespots_tail" })
        XCTAssertEqual(tail.file, "data2/NumberOfPokespots_tail.bin")
        XCTAssertEqual(fst.readFile(at: File("/project/Out/data2/NumberOfPokespots_tail.bin"))?.allData?.rawBytes, [0xAB, 0xCD])

        _ = try assembleSpots(engine: engine, fst: fst)
        XCTAssertEqual(fst.readFile(at: File("/project/rebuilt.rel"))?.allData?.rawBytes, original)
    }

    /// Deriving is only safe where it reproduces the module, so a word that
    /// doesn't hold its table's count keeps its bytes.
    func testACountThatDisagreesWithItsTableStaysRaw() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeCountedRel(countWord: 5, typeMap: countedTypeMap, in: fst)
        let logger = RecordingLogger()
        try disassembleSpots(engine: engine, dolphin: dolphin, fst: fst, logger: logger)

        let manifest = try RelManifest(json: try XCTUnwrap(fst.readFile(at: File("/project/Out/spots.rel.json"))?.allData))
        let chunk = try XCTUnwrap(manifest.sections.first { $0.index == 2 }?.chunks?.first { $0.label == "NumberOfPokespots" })
        XCTAssertEqual(chunk.type, .binary)
        XCTAssertTrue(logger.warnings.contains { $0.contains("holds 5") }, "\(logger.warnings)")
    }

    func testACountOfAnUndeclaredOrNonTableSymbolIsAnError() throws {
        for (typeMap, declared) in [
            (#"{"chunks": [{"count": {"label": "NumberOfPokespots", "table": "Pokespots"}}]}"#, false),
            (#"{"chunks": [{"file": {"label": "Pokespots", "extension": "msg"}}, {"count": {"label": "NumberOfPokespots", "table": "Pokespots"}}]}"#, true),
        ] {
            let fst = InMemoryFST()
            let (engine, dolphin) = try writeCountedRel(countWord: 2, typeMap: typeMap, in: fst)
            XCTAssertThrowsError(try disassembleSpots(engine: engine, dolphin: dolphin, fst: fst)) { error in
                guard case let TypeMapError.countTargetNotATable(_, table, wasDeclared, _) = error else {
                    return XCTFail("expected countTargetNotATable, got \(error)")
                }
                XCTAssertEqual(table, "Pokespots")
                XCTAssertEqual(wasDeclared, declared)
            }
        }
    }

    /// The build holds a hand-edited manifest to the same rule.
    func testAManifestCountOfANonTableIsABuildError() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeCountedRel(countWord: 2, typeMap: countedTypeMap, in: fst)
        try disassembleSpots(engine: engine, dolphin: dolphin, fst: fst)
        let file = File("/project/Out/spots.rel.json")
        let json = try XCTUnwrap(fst.readFile(at: file)?.allData).string(format: .utf8)
        writeText(json.replacingOccurrences(of: #""countOf" : "Pokespots""#, with: #""countOf" : "Nope""#), at: file, in: fst)
        XCTAssertThrowsError(try assembleSpots(engine: engine, fst: fst))
    }

    // MARK: - relsDump / relsBuild

    /// Two RELs sharing one matcher, one with its own, one routed file the
    /// disc doesn't ship, two RELs sharing a stem in different folders, one
    /// the table ignores, and one REL in another folder that no route names.
    private func writeRoutedProject(in fst: InMemoryFST) throws -> (engine: Folder, dolphin: Folder) {
        let engine = Folder("/project/Engines/Game")
        let dolphin = installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        writeText("""
        { "matchers": {
            "map": { "typeMap": "Resources/map.json", "symbolIndex": "Resources/map_symbols.json" },
            "module": {}
          },
          "routes": {
            "/Rels/A.rel": "map",
            "/Rels/B.rel": "map",
            "/Rels/menu.rel": "module",
            "/Rels/French/menu.rel": "module",
            "/Rels/regional.rel": "map"
          },
          "ignored": ["/Common/common.rel"] }
        """, at: engine.file("Resources/rel_routes.json"), in: fst)
        writeText("{\"chunks\": []}", at: engine.file("Resources/map.json"), in: fst)
        writeText("{\"symbols\": {}}", at: engine.file("Resources/map_symbols.json"), in: fst)
        for path in ["Rels/A", "Rels/B", "Rels/menu", "Rels/French/menu", "Common/common", "Scenes/x/stray"] {
            try writeSampleRel(at: File("/project/Unpacked/\(path).rel"), in: fst)
        }
        return (engine, dolphin)
    }

    private func dumpConfig(engine: Folder, dolphin: Folder, overwrite: Bool = true) -> RelsDump.Config {
        .init(
            routesPath: engine.file("Resources/rel_routes.json"),
            routesEngine: engine,
            inputFolder: Folder("/project/Unpacked"),
            outputFolder: Folder("/project/Source"),
            overwrite: overwrite,
            dolphinEngine: dolphin
        )
    }

    func testRelsDumpWritesOneSourceFolderPerRoutedRel() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeRoutedProject(in: fst)
        let logger = RecordingLogger()

        try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: dolphin),
                          settings: .default, fileSystem: fst, logger: logger)

        // Sources mirror the unpacked paths, so the two `menu.rel`s don't collide.
        for path in ["Rels/A/A", "Rels/B/B", "Rels/menu/menu", "Rels/French/menu/menu"] {
            XCTAssertNotNil(fst.readFile(at: File("/project/Source/\(path).rel.json")),
                            "\(path) should be dumped")
        }
        XCTAssertNil(fst.inspectFolder(at: Folder("/project/Source/Rels/regional")),
                     "a route to a file the disc doesn't ship is skipped")
        XCTAssertTrue(logger.warnings.contains { $0.contains("/Rels/regional.rel") },
                      "…with a warning, since a wrong path looks the same: \(logger.warnings)")
        XCTAssertNil(fst.inspectFolder(at: Folder("/project/Source/Scenes")),
                     "a REL no route names isn't dumped")
        XCTAssertTrue(logger.warnings.contains { $0.contains("/Scenes/x/stray.rel") },
                      "…but it is reported wherever it sits: \(logger.warnings)")
        XCTAssertFalse(logger.warnings.contains { $0.contains("common.rel") },
                       "an ignored REL is neither dumped nor reported")
    }

    func testRelsDumpLeavesAnExistingSourceAloneWithoutOverwrite() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeRoutedProject(in: fst)
        let manifest = File("/project/Source/Rels/A/A.rel.json")
        writeText("edited", at: manifest, in: fst)

        try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: dolphin, overwrite: false),
                          settings: .default, fileSystem: fst, logger: SilentLogger())

        XCTAssertEqual(fst.readFile(at: manifest)?.allData?.string(format: .utf8), "edited")
        XCTAssertNotNil(fst.readFile(at: File("/project/Source/Rels/B/B.rel.json")))
    }

    /// A matcher pointing at a file that isn't there fails the RELs routed
    /// to it — dumping them untyped would look like success — and the rest
    /// still dump.
    func testRelsDumpFailsTheRoutesOfAMatcherWithAMissingFile() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeRoutedProject(in: fst)
        try fst.deleteFile(at: engine.file("Resources/map.json"))
        let logger = RecordingLogger()

        XCTAssertThrowsError(
            try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: dolphin),
                              settings: .default, fileSystem: fst, logger: logger)
        ) { error in
            guard case let RelsBatchError.failures(_, names, _, _) = error else {
                return XCTFail("expected a batch failure, got \(error)")
            }
            XCTAssertEqual(names, ["/Rels/A.rel", "/Rels/B.rel"])
        }
        XCTAssertNotNil(fst.readFile(at: File("/project/Source/Rels/menu/menu.rel.json")),
                        "a REL on a healthy matcher still dumps")
    }

    func testRelsDumpRejectsARouteThatIsntARel() {
        let fst = InMemoryFST()
        let engine = Folder("/project/Engines/Game")
        writeText(#"{ "matchers": { "m": {} }, "routes": { "/Rels/A": "m" } }"#,
                  at: engine.file("Resources/rel_routes.json"), in: fst)
        XCTAssertThrowsError(
            try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: Folder("/project/Engines/Dolphin")),
                              settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case RelRouteTableError.notARel = error else {
                return XCTFail("expected notARel, got \(error)")
            }
        }
    }

    func testRelsDumpRejectsARouteToAnUndefinedMatcher() {
        let fst = InMemoryFST()
        let engine = Folder("/project/Engines/Game")
        writeText(#"{ "matchers": {}, "routes": { "/Rels/A.rel": "nope" } }"#,
                  at: engine.file("Resources/rel_routes.json"), in: fst)
        XCTAssertThrowsError(
            try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: Folder("/project/Engines/Dolphin")),
                              settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case RelRouteTableError.unknownMatcher = error else {
                return XCTFail("expected unknownMatcher, got \(error)")
            }
        }
    }

    func testRelsBuildRebuildsEachDumpedRelAtItsRoutedPath() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeRoutedProject(in: fst)
        try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: dolphin),
                          settings: .default, fileSystem: fst, logger: SilentLogger())

        try RelsBuild.build(
            config: .init(
                routesPath: engine.file("Resources/rel_routes.json"),
                inputFolder: Folder("/project/Source"),
                outputFolder: Folder("/project/Rebuilt")
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let original = try RELFixtures.model().binaryData
        for path in ["A", "B", "menu", "French/menu"] {
            XCTAssertEqual(fst.readFile(at: File("/project/Rebuilt/Rels/\(path).rel"))?.allData?.data,
                           original.data, "\(path) should rebuild byte-for-byte")
        }
        XCTAssertNil(fst.readFile(at: File("/project/Rebuilt/Rels/regional.rel")),
                     "nothing was dumped for it, so nothing is built")
    }

    func testRelsBuildReportsEveryFailureAtTheEnd() throws {
        let fst = InMemoryFST()
        let (engine, dolphin) = try writeRoutedProject(in: fst)
        try RelsDump.dump(config: dumpConfig(engine: engine, dolphin: dolphin),
                          settings: .default, fileSystem: fst, logger: SilentLogger())
        writeText("not json", at: File("/project/Source/Rels/A/A.rel.json"), in: fst)
        let logger = RecordingLogger()

        XCTAssertThrowsError(
            try RelsBuild.build(
                config: .init(
                    routesPath: engine.file("Resources/rel_routes.json"),
                    inputFolder: Folder("/project/Source"),
                    outputFolder: Folder("/project/Rebuilt")
                ),
                settings: .default, fileSystem: fst, logger: logger
            )
        ) { error in
            guard case let RelsBatchError.failures(_, names, _, _) = error else {
                return XCTFail("expected a batch failure, got \(error)")
            }
            XCTAssertEqual(names, ["/Rels/A.rel"])
        }
        XCTAssertNotNil(fst.readFile(at: File("/project/Rebuilt/Rels/B.rel")),
                        "one bad source doesn't stop the rest")
    }

}
