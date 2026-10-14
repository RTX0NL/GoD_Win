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
        let file = try GODOps.inputFile(fromArgument: #"C:\Games\Disc Images\Colosseum.iso"#)
        XCTAssertEqual(file.path, "/C:/Games/Disc Images/Colosseum.iso")
        XCTAssertEqual(file.nativePath, #"C:\Games\Disc Images\Colosseum.iso"#)
        XCTAssertEqual(file.fileName, "Colosseum.iso")
        XCTAssertEqual(file.fileType, "iso")
        // The parent folder must be valid too: this is where the trap was.
        XCTAssertEqual(file.parentFolder?.path, "/C:/Games/Disc Images")
    }

    func testForwardSlashWindowsArgumentBecomesLogicalPath() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "Windows-only conversion")
        let file = try GODOps.inputFile(fromArgument: "D:/Saves/xd.gci")
        XCTAssertEqual(file.path, "/D:/Saves/xd.gci")
        XCTAssertEqual(file.fileType, "gci")
    }

    func testLogicalArgumentIsUnchanged() throws {
        let file = try GODOps.inputFile(fromArgument: "/project/Build/Unpacked/x.fsys")
        XCTAssertEqual(file.path, "/project/Build/Unpacked/x.fsys")
        XCTAssertEqual(file.fileType, "fsys")
    }

    /// A relative argument would resolve against the server's working
    /// directory, which means nothing to the client, and a bare one like
    /// "foo/x.iso" trapped in Folder.init on the way to its parent folder.
    /// Both must come back as an error the client can read.
    func testRelativeArgumentsAreRejected() {
        for argument in ["foo/x.iso", "x.iso", "./x.iso", "../x.iso"] {
            XCTAssertThrowsError(try GODOps.inputFile(fromArgument: argument), argument) { error in
                XCTAssertTrue("\(error)".contains("absolute"), "\(argument): \(error)")
            }
        }
    }
}
