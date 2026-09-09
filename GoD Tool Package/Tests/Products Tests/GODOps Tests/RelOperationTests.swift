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

    // MARK: - mapRels batch behaviour

    func testMapRelsDumpBatchProcessesEveryRel() throws {
        let fst = InMemoryFST()
        let gameEngine = try installXDEngine(in: fst)
        try writeSampleRel(at: File("/project/Rels/M1_1.rel"), in: fst)
        try writeSampleRel(at: File("/project/Rels/M1_2.rel"), in: fst)
        writeText("{\"chunks\": [], \"engines\": []}", at: File("/project/typemap.json"), in: fst)

        try MapRelDump.dump(
            config: .init(
                relsFolder: Folder("/project/Rels"),
                outputFolder: Folder("/project/Out"),
                overwrite: true,
                typeMapPath: File("/project/typemap.json"),
                dolphinEngine: installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst),
                gameEngine: gameEngine,
                filter: .all
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        for name in ["M1_1", "M1_2"] {
            XCTAssertNotNil(
                fst.readFile(at: File("/project/Out/\(name)/\(name).rel.json")),
                "batch dump should produce a manifest for \(name)"
            )
        }
    }

    func testMapRelsDumpBatchMissingFolderReturnsWithoutThrowing() {
        // Missing relsFolder: the op logs a warning and returns early.
        let logger = RecordingLogger()
        let config = MapRelDump.BatchConfig(
            relsFolder: Folder("/project/MissingRels"),
            outputFolder: Folder("/project/Out"),
            overwrite: true,
            typeMapPath: File("/project/typemap.json"),
            dolphinEngine: Folder("/project/Engines/Dolphin"),
            gameEngine: Folder("/project/Engines/XD"),
            filter: .all
        )
        XCTAssertNoThrow(
            try MapRelDump.dump(config: config, settings: .default, fileSystem: InMemoryFST(), logger: logger)
        )
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("folder not found"))
    }

    func testMapRelsBuildBatchKeepsGoingAfterAFailedSubfolder() {
        // A subfolder with no manifest can't assemble; the batch op catches
        // that, logs a warning naming the subfolder, and does not throw.
        let fst = InMemoryFST()
        try? fst.writeFile(
            GoDData(byteStream: [0x00], byteOrder: .big),
            at: File("/project/MapDisasm/B1_1/placeholder.bin"),
            overwrite: true
        )
        let logger = RecordingLogger()
        let config = MapRelBuild.BatchConfig(
            inputFolder: Folder("/project/MapDisasm"),
            outputFolder: Folder("/project/Rels")
        )
        XCTAssertNoThrow(
            try MapRelBuild.build(config: config, settings: .default, fileSystem: fst, logger: logger)
        )
        XCTAssertFalse(logger.warnings.isEmpty, "per-subfolder failure must be logged as a warning")
        XCTAssertTrue(logger.warnings.contains { $0.contains("B1_1") })
        XCTAssertNil(fst.readFile(at: File("/project/Rels/B1_1.rel")))
    }

    func testMapRelsBuildBatchMissingFolderReturnsWithoutThrowing() {
        // Missing inputFolder: warning + early return (the source does log).
        let logger = RecordingLogger()
        let config = MapRelBuild.BatchConfig(
            inputFolder: Folder("/project/MissingDisasm"),
            outputFolder: Folder("/project/Rels")
        )
        XCTAssertNoThrow(
            try MapRelBuild.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: logger)
        )
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("folder not found"))
    }
}
