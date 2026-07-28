//
//  RelOperationTests.swift
//  GODOpsTests
//
//  The REL operation family is temporarily disabled via RelOperationsGate
//  (enabled = false): every op throws RelOperationsGate.DisabledError, either
//  immediately or after its pre-gate setup (engine resolution, folder scans).
//  These tests document the gate — REPLACE them with real coverage when the
//  gate lifts.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
import XD
import FixtureCatalog
@testable import GODOps

final class RelOperationTests: XCTestCase {

    private func assertDisabled(
        _ body: @autoclosure () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertTrue(
                error is RelOperationsGate.DisabledError,
                "Expected RelOperationsGate.DisabledError, got \(error)",
                file: file,
                line: line
            )
        }
    }

    private func installXDEngine(in fst: InMemoryFST) throws -> Folder {
        installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
    }

    // MARK: - relDisassembly / relAssembly (gate is the first statement)

    func testRelDisassemblyIsGated() {
        let config = RelDisassembly.Config(
            relPath: File("/project/sample.rel"),
            outputFolder: Folder("/project/Out"),
            dolphinEngine: Folder("/project/Engines/Dolphin")
        )
        assertDisabled(
            try RelDisassembly.disassemble(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        )
    }

    func testRelAssemblyIsGated() {
        let config = RelAssembly.Config(
            inputFolder: Folder("/project/In"),
            relName: "sample",
            outputPath: File("/project/sample.rel")
        )
        assertDisabled(
            try RelAssembly.assemble(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        )
    }

    // MARK: - commonRelDump (game-engine resolution runs BEFORE the gate)

    func testCommonRelDumpWithValidEngineIsGated() throws {
        let fst = InMemoryFST()
        let gameEngine = try installXDEngine(in: fst)
        let config = CommonRelDump.Config(
            relPath: File("/project/common.rel"),
            outputFolder: Folder("/project/Out"),
            overwrite: true,
            dolphinEngine: Folder("/project/Engines/Dolphin"),
            gameEngine: gameEngine
        )
        assertDisabled(
            try CommonRelDump.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        )
    }

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

    func testCommonRelBuildIsGated() {
        let config = CommonRelBuild.Config(
            inputFolder: Folder("/project/In"),
            outputPath: File("/project/common.rel")
        )
        assertDisabled(
            try CommonRelBuild.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        )
    }

    // MARK: - mapRelDump / mapRelBuild (single)

    func testMapRelDumpSingleIsGated() throws {
        let fst = InMemoryFST()
        let gameEngine = try installXDEngine(in: fst)
        let config = MapRelDump.SingleConfig(
            relPath: File("/project/M1_1.rel"),
            outputFolder: Folder("/project/Out"),
            overwrite: true,
            typeMapPath: File("/project/typemap.json"),
            dolphinEngine: Folder("/project/Engines/Dolphin"),
            gameEngine: gameEngine
        )
        assertDisabled(
            try MapRelDump.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        )
    }

    func testMapRelBuildSingleIsGated() {
        let config = MapRelBuild.SingleConfig(
            inputFolder: Folder("/project/In"),
            relName: "M1_1",
            outputPath: File("/project/M1_1.rel")
        )
        assertDisabled(
            try MapRelBuild.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        )
    }

    // MARK: - mapRelsDump (batch)

    func testMapRelsDumpBatchIsGatedOnFirstFile() throws {
        let fst = InMemoryFST()
        let gameEngine = try installXDEngine(in: fst)
        let relBytes = try RELFixtures.model().binaryData
        try fst.writeFile(relBytes, at: File("/project/Rels/sample.rel"), overwrite: true)
        writeText("{\"chunks\": [], \"engines\": []}", at: File("/project/typemap.json"), in: fst)

        let config = MapRelDump.BatchConfig(
            relsFolder: Folder("/project/Rels"),
            outputFolder: Folder("/project/Out"),
            overwrite: true,
            typeMapPath: File("/project/typemap.json"),
            dolphinEngine: Folder("/project/Engines/Dolphin"),
            gameEngine: gameEngine,
            filter: .all
        )
        assertDisabled(
            try MapRelDump.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        )
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

    // MARK: - mapRelsBuild (batch)

    func testMapRelsBuildBatchCatchesPerSubfolderGateErrors() {
        // Each subfolder's assemble hits the gate; the batch op catches the
        // error, logs a warning, and keeps going — no throw.
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
