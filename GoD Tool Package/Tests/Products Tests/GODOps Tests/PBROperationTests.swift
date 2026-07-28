//
//  PBROperationTests.swift
//  GODOpsTests
//
//  PBR dump is currently a logged placeholder: it emits a single info entry
//  ("PBR dump not yet implemented") and must not touch the tree. These tests
//  document that placeholder behavior and should be replaced with real output
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

    func testPBRDumpLogsNotImplementedAtInfoLevel() throws {
        let logger = RecordingLogger()
        try PBROps.dump(config: dumpConfig(), settings: .default, fileSystem: InMemoryFST(), logger: logger)
        let infos = logger.entries.compactMap { entry -> String? in
            if case .info(let message) = entry { return message } else { return nil }
        }
        XCTAssertEqual(infos, ["PBR dump not yet implemented"])
        XCTAssertTrue(logger.warnings.isEmpty)
    }
}
