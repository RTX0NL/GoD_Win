//
//  WindowsLongPathsTests.swift
//
//  A write past Windows' MAX_PATH used to fail with "Please check free
//  space and write permissions". These check that such failures name the
//  limit and the setting instead, and that other failures keep the
//  generic advice.
//

import XCTest
@testable import GoDFoundation

final class WindowsLongPathsTests: XCTestCase {

    private func path(length: Int) -> String {
        let prefix = #"C:\"#
        return prefix + String(repeating: "a", count: length - prefix.count)
    }

    // MARK: - Thresholds

    func testFilePathsBelowMaxPathGetNoHint() {
        XCTAssertNil(WindowsLongPaths.hint(forNativePath: path(length: 259), isFolder: false, longPathsEnabled: false))
    }

    func testFilePathsAtMaxPathGetAHint() {
        XCTAssertNotNil(WindowsLongPaths.hint(forNativePath: path(length: 260), isFolder: false, longPathsEnabled: false))
    }

    func testFolderLimitLeavesRoomForAFileName() {
        XCTAssertNil(WindowsLongPaths.hint(forNativePath: path(length: 247), isFolder: true, longPathsEnabled: false))
        XCTAssertNotNil(WindowsLongPaths.hint(forNativePath: path(length: 248), isFolder: true, longPathsEnabled: false))
    }

    // MARK: - Wording

    func testDisabledHintNamesTheRegistrySetting() throws {
        let hint = try XCTUnwrap(WindowsLongPaths.hint(forNativePath: path(length: 273), isFolder: false, longPathsEnabled: false))
        XCTAssertTrue(hint.contains("273 characters"), hint)
        XCTAssertTrue(hint.contains("MAX_PATH"), hint)
        XCTAssertTrue(hint.contains(#"HKLM\SYSTEM\CurrentControlSet\Control\FileSystem"#), hint)
        XCTAssertTrue(hint.contains("LongPathsEnabled"), hint)
    }

    func testEnabledHintPointsAtTheManifest() throws {
        let hint = try XCTUnwrap(WindowsLongPaths.hint(forNativePath: path(length: 273), isFolder: false, longPathsEnabled: true))
        XCTAssertTrue(hint.contains("MAX_PATH"), hint)
        XCTAssertTrue(hint.contains("longPathAware manifest"), hint)
    }

    // MARK: - FSTErrors

    func testShortPathWriteFailureKeepsGenericAdvice() {
        let error = FSTErrors.failedToWriteFile(File("/Build/a.bin"), .init())
        XCTAssertTrue(error.description.contains("Please check free space and write permissions"))
    }

    func testLongPathWriteFailureNamesMaxPathOnWindows() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "MAX_PATH only applies on Windows")
        let file = File(nativePath: path(length: 273))
        let fileError = FSTErrors.failedToWriteFile(file, .init()).description
        XCTAssertTrue(fileError.contains("MAX_PATH"), fileError)
        XCTAssertFalse(fileError.contains("free space"), fileError)

        let folder = Folder(nativePath: path(length: 250))
        let folderError = FSTErrors.failedToCreateFolder(folder, .init()).description
        XCTAssertTrue(folderError.contains("MAX_PATH"), folderError)
    }
}
