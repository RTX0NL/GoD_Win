//
//  AudioDumpWarningTests.swift
//  GODOpsTests
//
//  dumpAudios pairs each `.ish` with the `.isd` of the same stem. A header
//  with no data half was reported as a generic "file not found" plus a
//  source-code trace, 388 times for XD's cries; the warning should say what
//  is missing and why the file was skipped.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class AudioDumpWarningTests: XCTestCase {

    func testAHeaderWithoutItsDataHalfIsReportedClearly() throws {
        let fst = InMemoryFST()
        let audio = Folder("/project/Streamed")
        try fst.writeFile(
            GoDData(byteStream: [UInt8](repeating: 0, count: 0x80), byteOrder: .big),
            at: audio.file("cry_000.ish"), overwrite: true
        )

        let logger = RecordingLogger()
        try ColoXD.dump(config: ColoXD.DumpConfig(operations: [
            OperationConfig(operation: .dumpAudios(
                audioFolder: audio, outputFolder: Folder("/project/Audio"), overwrite: true
            ), enabled: .yes)
        ]), settings: .default, fileSystem: fst, logger: logger)

        let warning = try XCTUnwrap(logger.warnings.first { $0.contains("cry_000.ish") }, "\(logger.warnings)")
        XCTAssertTrue(warning.contains("cry_000.isd"), warning)
        XCTAssertTrue(warning.contains("no matching"), warning)
        XCTAssertFalse(warning.contains(" at line #"), "no source trace in a user-facing warning: \(warning)")
        XCTAssertTrue(logger.warnings.contains { $0.contains("Skipped 1 of 1") }, "\(logger.warnings)")
    }
}
