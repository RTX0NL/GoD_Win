//
//  RunMonitorTests.swift
//  GODOpsTests
//
//  A `RunMonitor` watches one run for the MCP server: it stops the run when
//  the client cancels, reports progress, and lists the files the run wrote.
//  A SpyOperationHandler stands in for the engine; its `work` hook writes
//  through the tree the run hands it, the way a real operation does.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class RunMonitorTests: XCTestCase {

    private let compress = """
    { "compress": { "config": {
      "inputFile": "/project/in.bin", "format": "yaz0", "outputFile": "/project/out.szs", "overwrite": true
    } } }
    """

    private func bytes(_ count: Int = 4) -> GoDData {
        GoDData(byteStream: [UInt8](repeating: 0x41, count: count), byteOrder: .big)
    }

    /// Runs a config of `operationCount` compress entries (plus one disabled
    /// one) through the spy, with the run's tree watched by `monitor`.
    private func runConfig(
        operationCount: Int,
        monitor: RunMonitor,
        handler: SpyOperationHandler,
        tree: InMemoryFST = InMemoryFST()
    ) throws {
        let entries = (0 ..< operationCount).map { _ in "{ \"operation\": \(compress), \"enabled\": \"YES\" }" }
            + ["{ \"operation\": \(compress), \"enabled\": \"NO\" }"]
        writeText("""
        { "name": "monitor-test", "rootFolder": ".", "operations": [ \(entries.joined(separator: ", ")) ] }
        """, at: File("/project/config.json"), in: tree)
        try GODOps.runConfig(
            at: File("/project/config.json"),
            fileSystem: StreamedFileSystem(materializing: tree, observer: monitor),
            logger: SilentLogger(),
            handler: handler,
            monitor: monitor
        )
    }

    // MARK: - Outputs

    func testRecordsEachFileTheRunWritesOnceInOrder() throws {
        let monitor = RunMonitor()
        let spy = SpyOperationHandler()
        var call = 0
        spy.work = { fileSystem in
            call += 1
            try fileSystem.writeFile(self.bytes(), at: File("/project/out/\(call).bin"), overwrite: true)
            try fileSystem.writeFile(self.bytes(), at: File("/project/out/shared.bin"), overwrite: true)
            try fileSystem.resizeFile(at: File("/project/out/shared.bin"), to: 16)
        }

        try runConfig(operationCount: 2, monitor: monitor, handler: spy)

        XCTAssertEqual(monitor.writtenFiles, [
            File("/project/out/1.bin"),
            File("/project/out/shared.bin"),
            File("/project/out/2.bin"),
        ])
    }

    func testRunOperationIsWatchedToo() throws {
        let monitor = RunMonitor()
        let spy = SpyOperationHandler()
        spy.work = { try $0.writeFile(self.bytes(), at: File("/project/single.bin"), overwrite: true) }

        try GODOps.runOperation(
            json: Data(compress.utf8),
            settingsJSON: nil,
            fileSystem: StreamedFileSystem(materializing: InMemoryFST(), observer: monitor),
            logger: SilentLogger(),
            handler: spy,
            monitor: monitor
        )

        XCTAssertEqual(monitor.writtenFiles, [File("/project/single.bin")])
    }

    // MARK: - Cancellation

    func testCancelledBeforeTheRunStartsRunsNothing() {
        let monitor = RunMonitor()
        let spy = SpyOperationHandler()
        monitor.cancel()

        XCTAssertThrowsError(try runConfig(operationCount: 2, monitor: monitor, handler: spy)) {
            XCTAssertTrue($0 is CancellationError, "got \($0)")
        }
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testCancelRefusesTheNextWriteAndStopsTheRun() {
        let monitor = RunMonitor()
        let spy = SpyOperationHandler()
        let tree = InMemoryFST()
        spy.work = { fileSystem in
            try fileSystem.writeFile(self.bytes(), at: File("/project/before.bin"), overwrite: true)
            monitor.cancel()
            try fileSystem.writeFile(self.bytes(), at: File("/project/after.bin"), overwrite: true)
        }

        XCTAssertThrowsError(try runConfig(operationCount: 2, monitor: monitor, handler: spy, tree: tree)) {
            XCTAssertTrue($0 is CancellationError, "got \($0)")
        }
        XCTAssertNotNil(tree.readFile(at: File("/project/before.bin")))
        XCTAssertNil(tree.readFile(at: File("/project/after.bin")))
        XCTAssertEqual(spy.calls.count, 1, "the second operation must not start")
        XCTAssertEqual(monitor.writtenFiles, [File("/project/before.bin")])
    }

    /// Some engine code writes with `try?`. A cancelled run must still not
    /// come back as a success just because the refused write was swallowed.
    func testCancelledRunFailsEvenWhenTheRefusedWriteIsSwallowed() {
        let monitor = RunMonitor()
        let spy = SpyOperationHandler()
        spy.work = { fileSystem in
            monitor.cancel()
            try? fileSystem.writeFile(self.bytes(), at: File("/project/after.bin"), overwrite: true)
        }

        XCTAssertThrowsError(try runConfig(operationCount: 1, monitor: monitor, handler: spy)) {
            XCTAssertTrue($0 is CancellationError, "got \($0)")
        }
    }

    // MARK: - Progress

    func testProgressReportsOperationsAndWrites() throws {
        var events: [RunProgress] = []
        let monitor = RunMonitor(onProgress: { events.append($0) })
        let spy = SpyOperationHandler()
        spy.work = { try $0.writeFile(self.bytes(), at: File("/project/\(events.count).bin"), overwrite: true) }

        try runConfig(operationCount: 2, monitor: monitor, handler: spy)

        XCTAssertEqual(events.map(\.event), [
            .operationStarted,
            .fileWritten(File("/project/1.bin")),
            .operationCompleted,
            .operationStarted,
            .fileWritten(File("/project/4.bin")),
            .operationCompleted,
        ])
        XCTAssertEqual(events.map(\.operationIndex), [1, 1, 1, 2, 2, 2])
        XCTAssertEqual(Set(events.map(\.operationCount)), [2])
        XCTAssertEqual(Set(events.map(\.operation)), [.compress])
        XCTAssertEqual(events.map(\.filesWritten), [0, 1, 1, 1, 2, 2])
    }

    func testProgressSummaryText() {
        func progress(_ event: RunProgress.Event, operation: OperationName? = .coloXDDump, files: Int) -> String {
            RunProgress(event: event, operationIndex: 2, operationCount: 3, operation: operation, filesWritten: files).summary
        }
        XCTAssertEqual(progress(.operationStarted, files: 0), "Operation 2 of 3 (coloXDDump) started")
        XCTAssertEqual(progress(.operationCompleted, files: 1), "Operation 2 of 3 (coloXDDump) done; 1 file written so far")
        XCTAssertEqual(
            progress(.fileWritten(File("/p/Source/a.wav")), files: 1234),
            "Operation 2 of 3 (coloXDDump): 1,234 files written, latest a.wav"
        )
        XCTAssertEqual(
            progress(.fileWritten(File("/p/a.wav")), operation: nil, files: 2),
            "2 files written, latest a.wav"
        )
    }

    // MARK: - Output summary

    private func monitor(writing paths: [String]) throws -> RunMonitor {
        let monitor = RunMonitor()
        for path in paths {
            try monitor.willChange(.writeFile(File(path)))
        }
        return monitor
    }

    func testOutputSummaryGroupsFilesByFolderUnderTheirCommonRoot() throws {
        let summary = try monitor(writing: [
            "/p/Source/Audio/MusyX/bank1/1.wav",
            "/p/Source/Audio/MusyX/bank1/2.wav",
            "/p/Source/Audio/MusyX/bank2/1.wav",
            "/p/Source/Audio/MusyX/bank2/deeper/x.wav",
            "/p/Source/Audio/Songs/song.mid",
        ]).outputSummary()

        XCTAssertEqual(summary, """
        Wrote 5 files under \(Folder("/p/Source/Audio").nativePath):
          MusyX/bank1: 2 files
          MusyX/bank2: 2 files
          Songs: 1 file
        """)
    }

    func testOutputSummaryCountsFilesDirectlyInTheRoot() throws {
        let summary = try monitor(writing: ["/p/out/a.bin", "/p/out/b.bin", "/p/out/sub/c.bin"]).outputSummary()

        XCTAssertEqual(summary, """
        Wrote 3 files under \(Folder("/p/out").nativePath):
          (top level): 2 files
          sub: 1 file
        """)
    }

    func testOutputSummaryCapsTheFolderList() throws {
        let paths = (1 ... 5).map { "/p/f\($0)/x.bin" }
        let summary = try monitor(writing: paths).outputSummary(maxFolders: 3)

        XCTAssertEqual(summary, """
        Wrote 5 files under \(Folder("/p").nativePath):
          f1: 1 file
          f2: 1 file
          f3: 1 file
          … and 2 more folders
        """)
    }

    func testOutputSummaryForASingleFile() throws {
        let summary = try monitor(writing: ["/p/out/game.iso"]).outputSummary()
        XCTAssertEqual(summary, "Wrote 1 file: \(File("/p/out/game.iso").nativePath)")
    }

    func testOutputSummaryWhenNothingWasWritten() {
        XCTAssertEqual(RunMonitor().outputSummary(), "Wrote no files.")
    }
}
