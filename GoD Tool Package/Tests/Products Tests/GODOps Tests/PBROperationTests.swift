//
//  PBROperationTests.swift
//  GODOpsTests
//
//  PBR dump is a placeholder. It must not touch the tree, and it must say so
//  loudly: project setup wires it in *enabled* for a PBR disc, so a quiet
//  info line plus a success status made a no-op look like a finished dump.
//  These tests pin that reporting and should be replaced with real output
//  assertions when PBR dump is implemented.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GODOps

final class PBROperationTests: XCTestCase {

    // The placeholder never reads these paths, so nothing needs seeding.
    private func dumpConfig() -> PBROps.DumpConfig {
        PBROps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpPBR(
                    fstFolder: Folder("/project/Unpacked"),
                    outputFolder: Folder("/project/Output"),
                    overwrite: true,
                    dolphinEngine: Folder("/project/Engines/Dolphin Engine"),
                    geniusSonorityEngine: Folder("/project/Engines/GeniusSonority Engine")
                ),
                enabled: .yes
            )
        ])
    }

    func testPBRDumpCompletesWithoutThrowingOnEmptyTree() {
        XCTAssertNoThrow(
            try PBROps.dump(config: dumpConfig(), settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        )
    }

    func testPBRDumpWritesNothing() throws {
        let fst = InMemoryFST()
        try PBROps.dump(config: dumpConfig(), settings: .default, fileSystem: fst, logger: SilentLogger())
        XCTAssertNil(fst.inspectFolder(at: Folder("/project/Output")), "placeholder must not create the output folder")
        XCTAssertNil(fst.inspectFolder(at: Folder("/")), "placeholder must not write anything to the tree")
    }

    /// The warning names the paths, so it's clear which input was skipped and
    /// where the absent output would have gone.
    func testPBRDumpWarnsThatItIsNotImplemented() throws {
        let logger = RecordingLogger()
        try PBROps.dump(config: dumpConfig(), settings: .default, fileSystem: InMemoryFST(), logger: logger)

        XCTAssertEqual(logger.warnings.count, 1, "expected exactly one warning; got \(logger.warnings)")
        let warning = try XCTUnwrap(logger.warnings.first)
        XCTAssertTrue(warning.contains("not implemented"), warning)
        XCTAssertTrue(warning.contains("/project/Unpacked"), warning)
        XCTAssertTrue(warning.contains("/project/Output"), warning)
    }

    /// Reported as a failed task, not a completed one — otherwise a run that
    /// produced nothing still looked successful in the log.
    func testPBRDumpReportsTheTaskAsFailed() throws {
        let logger = RecordingLogger()
        try PBROps.dump(config: dumpConfig(), settings: .default, fileSystem: InMemoryFST(), logger: logger)

        let completions = logger.entries.compactMap { entry -> Bool? in
            if case .taskStatus(_, .completed(let success)) = entry { return success }
            return nil
        }
        XCTAssertEqual(completions, [false])
    }
}
