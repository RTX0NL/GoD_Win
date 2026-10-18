//
//  WorkingDirectoryIsolationTests.swift
//  GODOpsTests
//
//  Relative paths resolve against the shared file system's current
//  directory. A config moves it to its `rootFolder`; it used to leave it
//  there, so in the MCP server a later `run_operation` with `./` paths
//  quietly resolved against whichever config ran last. Each entry point now
//  sets the directory it needs and puts the previous one back.
//
//  These run against the real disk, in a temporary folder, because the
//  current directory only exists on the on-disk tree.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GODOps

final class WorkingDirectoryIsolationTests: XCTestCase {

    private let fileSystem = FileSystem.shared
    private var scratch: Folder!
    private var original: Folder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        original = fileSystem.currentDirectory
        scratch = Folder(nativePath: NSTemporaryDirectory())
            .folder("goddess-cwd-\(UUID().uuidString.prefix(8))")
        for name in ["A", "B"] {
            try fileSystem.writeFile(
                GoDData(byteStream: [UInt8](repeating: 0x41, count: 64), byteOrder: .big),
                at: scratch.folder(name).file("in.bin"),
                overwrite: true
            )
        }
    }

    override func tearDownWithError() throws {
        fileSystem.changeDirectory(original)
        try? fileSystem.deleteFolder(at: scratch)
        try super.tearDownWithError()
    }

    private let compressOperation = """
    { "compress": { "config": {
      "inputFile": "./in.bin", "format": "yaz0", "outputFile": "./out.szs", "overwrite": true
    } } }
    """

    private func writeConfig(in folder: Folder) throws -> File {
        let file = folder.file("config.json")
        try fileSystem.writeFile(
            GoDData(string: """
            { "name": "cwd-test", "rootFolder": ".",
              "operations": [ { "operation": \(compressOperation), "enabled": "YES" } ] }
            """, format: .utf8),
            at: file,
            overwrite: true
        )
        return file
    }

    func testRunningAConfigPutsTheCurrentDirectoryBack() throws {
        let before = fileSystem.currentDirectory
        try GODOps.runConfig(at: try writeConfig(in: scratch.folder("A")), logger: SilentLogger())

        XCTAssertNotNil(fileSystem.readFile(at: scratch.folder("A").file("out.szs")), "the config ran in its root")
        XCTAssertEqual(fileSystem.currentDirectory, before)
    }

    func testAConfigThatFailsStillPutsTheCurrentDirectoryBack() throws {
        let before = fileSystem.currentDirectory
        try fileSystem.deleteFile(at: scratch.folder("A").file("in.bin"))
        XCTAssertThrowsError(try GODOps.runConfig(at: try writeConfig(in: scratch.folder("A")), logger: SilentLogger()))
        XCTAssertEqual(fileSystem.currentDirectory, before)
    }

    func testAnOperationRunsInTheRootFolderItIsGiven() throws {
        let before = fileSystem.currentDirectory
        try GODOps.runOperation(
            json: Data(compressOperation.utf8),
            rootFolder: scratch.folder("B"),
            logger: SilentLogger()
        )
        XCTAssertNotNil(fileSystem.readFile(at: scratch.folder("B").file("out.szs")))
        XCTAssertEqual(fileSystem.currentDirectory, before)
    }

    /// The bug itself: after a config ran in A, an operation with no root
    /// must not pick up A's `./in.bin`.
    func testAnOperationWithoutARootDoesNotInheritTheLastConfigsRoot() throws {
        try GODOps.runConfig(at: try writeConfig(in: scratch.folder("A")), logger: SilentLogger())
        try fileSystem.deleteFile(at: scratch.folder("A").file("out.szs"))

        XCTAssertThrowsError(try GODOps.runOperation(json: Data(compressOperation.utf8), logger: SilentLogger()))
        XCTAssertNil(fileSystem.readFile(at: scratch.folder("A").file("out.szs")),
                     "the operation resolved ./ against the previous config's root")
    }
}
