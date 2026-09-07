//
//  RelOperationTests.swift
//  GODOpsTests
//
//  The REL operation family used to be disabled behind `RelOperationsGate`
//  and these tests only documented that. The gate is open, so they now cover
//  the real behaviour: a disassembly writes per-section artifacts and a
//  lossless `<name>.rel.json`, an assembly rebuilds the binary from that JSON
//  byte-for-byte, and the batch wrappers keep going when one member fails.
//
//  What deliberately isn't asserted: that edits to the per-chunk artifacts
//  reach the rebuilt binary. `RelAssembly` reads only the `.rel.json`, so the
//  chunk files are a read-only view until `.s` parsing lands — see
//  `RelOperationsGate`.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
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
