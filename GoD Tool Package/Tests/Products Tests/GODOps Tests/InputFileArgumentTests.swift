//
//  InputFileArgumentTests.swift
//  GODOpsTests
//
//  Covers GODOps.inputFile(fromArgument:), which turns an MCP tool's `path`
//  argument into a `File`. On Windows, MCP clients send native `C:\...`
//  paths; holding one as a logical path made `setup_project` trap in
//  `Folder.init` and take the whole MCP server down.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class InputFileArgumentTests: XCTestCase {

    func testNativeWindowsArgumentBecomesLogicalPath() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "Windows-only conversion")
        let file = GODOps.inputFile(fromArgument: #"C:\Games\Disc Images\Colosseum.iso"#)
        XCTAssertEqual(file.path, "/C:/Games/Disc Images/Colosseum.iso")
        XCTAssertEqual(file.nativePath, #"C:\Games\Disc Images\Colosseum.iso"#)
        XCTAssertEqual(file.fileName, "Colosseum.iso")
        XCTAssertEqual(file.fileType, "iso")
        // The parent folder must be valid too: this is where the trap was.
        XCTAssertEqual(file.parentFolder?.path, "/C:/Games/Disc Images")
    }

    func testForwardSlashWindowsArgumentBecomesLogicalPath() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "Windows-only conversion")
        let file = GODOps.inputFile(fromArgument: "D:/Saves/xd.gci")
        XCTAssertEqual(file.path, "/D:/Saves/xd.gci")
        XCTAssertEqual(file.fileType, "gci")
    }

    func testLogicalArgumentIsUnchanged() {
        let file = GODOps.inputFile(fromArgument: "/project/Build/Unpacked/x.fsys")
        XCTAssertEqual(file.path, "/project/Build/Unpacked/x.fsys")
        XCTAssertEqual(file.fileType, "fsys")
    }
}
