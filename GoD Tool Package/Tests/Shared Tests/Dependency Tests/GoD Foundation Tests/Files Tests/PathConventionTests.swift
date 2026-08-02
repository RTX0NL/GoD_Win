//
//  PathConventionTests.swift
//
//  The Windows mapping can't be exercised by running on Windows here, so every
//  case passes `convention:` explicitly. Without that the Windows branch would
//  be code nobody has ever run.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class PathConventionTests: XCTestCase {

    // MARK: - POSIX is a passthrough

    func testPosixConversionsAreIdentity() {
        for path in ["/Data/Text/a.msg", "./relative/b", "../up", ".", "/"] {
            XCTAssertEqual(PlatformPath.native(from: path, convention: .posix), path)
            XCTAssertEqual(PlatformPath.logical(from: path, convention: .posix), path)
        }
    }

    // MARK: - Windows

    func testDriveQualifiedPathsRoundTrip() {
        let pairs = [
            ("/C:/Games/rom.iso", "C:\\Games\\rom.iso"),
            ("/D:/a/b/c.txt",     "D:\\a\\b\\c.txt"),
            ("/C:",               "C:\\"),
        ]
        for (logical, native) in pairs {
            XCTAssertEqual(PlatformPath.native(from: logical, convention: .windows), native, logical)
            XCTAssertEqual(PlatformPath.logical(from: native, convention: .windows), logical, native)
        }
    }

    /// A logical path with no drive is rooted on the current drive, which is
    /// what a leading separator means on Windows.
    func testDrivelessAbsolutePathsRootOnCurrentDrive() {
        XCTAssertEqual(
            PlatformPath.native(from: "/Data/Text/a.msg", convention: .windows),
            "\\Data\\Text\\a.msg"
        )
        XCTAssertEqual(
            PlatformPath.logical(from: "\\Data\\Text\\a.msg", convention: .windows),
            "/Data/Text/a.msg"
        )
    }

    func testRelativePathsStayRelative() {
        XCTAssertEqual(PlatformPath.native(from: "./Config/a.json", convention: .windows), ".\\Config\\a.json")
        XCTAssertEqual(PlatformPath.logical(from: ".\\Config\\a.json", convention: .windows), "./Config/a.json")
        XCTAssertEqual(PlatformPath.logical(from: "Config\\a.json", convention: .windows), "./Config/a.json")
        XCTAssertEqual(PlatformPath.logical(from: "..\\up", convention: .windows), "../up")
    }

    /// Whatever a native path looks like, the logical form has to satisfy
    /// `Folder.init` — that precondition is what traps today when a raw
    /// `C:\…` is handed straight to a `Folder`.
    func testConvertedWindowsPathsAreAcceptedByFolder() {
        for native in ["C:\\Games\\Pokemon XD", "\\Data\\Text", "Config\\sub", "..\\up"] {
            let logical = PlatformPath.logical(from: native, convention: .windows)
            XCTAssertNoThrow(Folder(logical), native)
            XCTAssertTrue(
                logical.hasPrefix("/") || logical.hasPrefix("./") || logical.hasPrefix("../"),
                "\(native) -> \(logical) is not a form Folder accepts"
            )
        }
    }

    /// Logical paths are the portable namespace: a project's configs address
    /// the same `/files/...` whichever machine reads them, so the round trip
    /// through a platform spelling has to be lossless.
    func testRoundTripPreservesLogicalPaths() {
        for logical in ["/C:/Games/rom.iso", "/Data/Text/a.msg", "./Config/a.json", "../up"] {
            let native = PlatformPath.native(from: logical, convention: .windows)
            XCTAssertEqual(
                PlatformPath.logical(from: native, convention: .windows),
                logical,
                "round trip changed \(logical) (via \(native))"
            )
        }
    }

    // MARK: - Host behavior

    /// On this build the convention is POSIX, so `nativePath` matches `path`.
    /// The value of the assertion is that it goes through the converter at all
    /// — `url` used to hand the logical path straight to Foundation.
    func testNativePathMatchesLogicalPathOnPosixHosts() throws {
        try XCTSkipUnless(PathConvention.current == .posix, "POSIX-only expectation")
        let file = File("/Data/Text/a.msg")
        XCTAssertEqual(file.nativePath, file.path)
        XCTAssertEqual(file.url.path, file.path)
    }
}
