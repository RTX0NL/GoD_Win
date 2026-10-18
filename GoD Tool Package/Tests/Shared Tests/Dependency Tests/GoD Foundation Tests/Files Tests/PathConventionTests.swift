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

    /// A network share has no drive letter. It used to lose its leading
    /// `\\` and become a folder on the current drive, so a project on a NAS
    /// was read and written somewhere else entirely.
    func testUNCPathsRoundTripThroughAnUNCRoot() {
        let pairs = [
            ("/UNC/nas/games/Colosseum.iso", "\\\\nas\\games\\Colosseum.iso"),
            ("/UNC/nas/games",               "\\\\nas\\games"),
        ]
        for (logical, native) in pairs {
            XCTAssertEqual(PlatformPath.native(from: logical, convention: .windows), native, logical)
            XCTAssertEqual(PlatformPath.logical(from: native, convention: .windows), logical, native)
        }
        XCTAssertEqual(PlatformPath.logical(from: "//nas/games/a.iso", convention: .windows), "/UNC/nas/games/a.iso")
    }

    /// The `\\?\` prefix only switches off Win32 path parsing; the path after
    /// it is an ordinary drive or UNC path and means the same thing.
    func testExtendedLengthPrefixIsDropped() {
        XCTAssertEqual(PlatformPath.logical(from: "\\\\?\\C:\\Games\\rom.iso", convention: .windows), "/C:/Games/rom.iso")
        XCTAssertEqual(PlatformPath.logical(from: "\\\\?\\UNC\\nas\\games\\rom.iso", convention: .windows), "/UNC/nas/games/rom.iso")
    }

    func testUNCPathsAreAcceptedByFolder() {
        let folder = Folder(PlatformPath.logical(from: "\\\\nas\\games\\Project", convention: .windows))
        XCTAssertEqual(folder.path, "/UNC/nas/games/Project")
        XCTAssertTrue(PlatformPath.isNativeSpelling("\\\\nas\\games", convention: .windows))
    }

    /// A list of paths in one environment variable is split the way the
    /// platform splits PATH. On Windows that can't be `:`, which every path
    /// there contains.
    func testPathListsSplitLikePATH() {
        XCTAssertEqual(PlatformPath.pathList("/a/b:/c/d", convention: .posix), ["/a/b", "/c/d"])
        XCTAssertEqual(
            PlatformPath.pathList(#"C:\Dumps\XD;/D:/Dumps/Colo;;"#, convention: .windows),
            [#"C:\Dumps\XD"#, "/D:/Dumps/Colo"]
        )
        XCTAssertEqual(PlatformPath.pathList("colo=C:\\a;xd=C:\\b", convention: .windows), ["colo=C:\\a", "xd=C:\\b"])
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

    // MARK: - Decoding

    /// Configs may name absolute paths, and on Windows a user writes those in
    /// native spelling. Decoding converts them like argv; `Folder` used to trap.
    func testDecodingNativeWindowsPathsYieldsLogicalPaths() throws {
        try XCTSkipUnless(PathConvention.current == .windows, "Windows-only decoding")
        for json in [#""C:/Games/Pokemon XD""#, #""C:\\Games\\Pokemon XD""#] {
            let data = Data(json.utf8)
            XCTAssertEqual(try JSONDecoder().decode(Folder.self, from: data).path, "/C:/Games/Pokemon XD", json)
            XCTAssertEqual(try JSONDecoder().decode(File.self, from: data).path, "/C:/Games/Pokemon XD", json)
        }
    }

    /// Registries and generated configs store logical paths; decoding must
    /// leave every one of them exactly as written, on any host.
    func testDecodingLeavesLogicalPathsUnchanged() throws {
        for path in ["/Assets/Models/a (2).dat", "/C:/Games/rom.iso", "./Build/ISO", "../up", "..", ".", "/"] {
            let data = Data("\"\(path)\"".utf8)
            XCTAssertEqual(try JSONDecoder().decode(Folder.self, from: data).path, path)
            XCTAssertEqual(try JSONDecoder().decode(File.self, from: data).path, path)
        }
        // Archive manifests and ATX frame lists store bare relative names that
        // get joined onto a folder later; a `./` prefix would break the join.
        for path in ["homeBtn/arc/one.brlan", "0000.bin", "atx_sample_frame_000.png"] {
            let data = Data("\"\(path)\"".utf8)
            XCTAssertEqual(try JSONDecoder().decode(File.self, from: data).path, path)
        }
    }

    func testOnlyNativeSpellingsAreConverted() {
        for native in ["C:/Games/x", "C:\\Games\\x", "d:\\x", "Config\\a.json", "C:"] {
            XCTAssertTrue(PlatformPath.isNativeSpelling(native, convention: .windows), native)
        }
        for logical in ["/C:/Games/x", "./Build", "homeBtn/arc/one.brlan", "0000.bin", "..", "/"] {
            XCTAssertFalse(PlatformPath.isNativeSpelling(logical, convention: .windows), logical)
        }
        XCTAssertFalse(PlatformPath.isNativeSpelling("C:\\Games\\x", convention: .posix))
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
