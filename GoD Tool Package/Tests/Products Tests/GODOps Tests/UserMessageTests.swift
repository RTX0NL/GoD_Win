//
//  UserMessageTests.swift
//  GODOpsTests
//
//  The MCP server used to return "Error: \(error)" for every failure. Most
//  error descriptions already start with "Error:" and end with an
//  ErrorTrace ("in <function> of <source file> at line #N"), so a client saw
//  "Error: Error: ... in setup(iso:...) of C:\...\ProjectSetupOperation.swift".
//

import XCTest
import GoDFoundation
@testable import GODOps

final class UserMessageTests: XCTestCase {

    private struct PlainError: Error, CustomStringConvertible {
        let description: String
    }

    func testDoubledPrefixAndTraceAreRemoved() {
        let file = File("/project/missing.iso")
        let message = GODOps.userMessage(for: ProjectSetupErrors.isoNotFound(file, ErrorTrace()))
        XCTAssertEqual(message, "Error: Couldn't load iso file: \(file.nativePath)")
    }

    func testATraceInTheMiddleIsRemovedAndTheAdviceKept() {
        let error = FSTErrors.failedToWriteFile(File("/Build/a.bin"), ErrorTrace())
        let message = GODOps.userMessage(for: error)
        XCTAssertFalse(message.contains(" at line #"), message)
        XCTAssertFalse(message.hasPrefix("Error: Error:"), message)
        XCTAssertTrue(message.hasPrefix("Error: failed to write file: "), message)
        XCTAssertTrue(message.hasSuffix("Please check free space and write permissions"), message)
    }

    func testAnErrorWithoutPrefixGetsOne() {
        XCTAssertEqual(GODOps.userMessage(for: PlainError(description: "boom")), "Error: boom")
    }

    func testSetupErrorsUseTheNativeSpellingOnWindows() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "Windows-only spelling")
        let file = File(nativePath: #"C:\Games\missing.iso"#)
        let message = GODOps.userMessage(for: ProjectSetupErrors.isoNotFound(file, ErrorTrace()))
        XCTAssertEqual(message, #"Error: Couldn't load iso file: C:\Games\missing.iso"#)
    }
}
