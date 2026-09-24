//
//  FileSystemPathResolutionTests.swift
//
//  `FileSystem.extendPath` is what turns a config's relative path into the
//  one a read, a write or a launched program actually uses, and it resolves
//  against a current directory the running config moves. Nothing reaches the
//  disk here — these only exercise the string resolution — but they do move
//  the shared tree's current directory, so each restores it.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class FileSystemPathResolutionTests: XCTestCase {

    private let fileSystem = FileSystem.shared
    private var original: Folder!

    override func setUp() {
        super.setUp()
        original = fileSystem.currentDirectory
        fileSystem.changeDirectory(Folder("/project/root"))
    }

    override func tearDown() {
        fileSystem.changeDirectory(original)
        super.tearDown()
    }

    // MARK: - Absolute paths are left alone

    func testAnAbsolutePathIsNotExtended() {
        XCTAssertEqual(fileSystem.extendPath(File("/elsewhere/rom.iso")), File("/elsewhere/rom.iso"))
        XCTAssertEqual(fileSystem.extendPath(Folder("/elsewhere")), Folder("/elsewhere"))
    }

    // MARK: - Relative paths resolve against the current directory

    /// `Folder.folder` resolves `.` and `..` components as it joins, while
    /// `Folder.file` only concatenates — so a file keeps the `./` in the
    /// middle. Both name the same thing to the platform, and this is the
    /// form every read and write in the tool already goes through.
    func testAPrefixedRelativePathResolvesAgainstTheCurrentDirectory() {
        XCTAssertEqual(fileSystem.extendPath(File("./Build/rom.iso")), File("/project/root/./Build/rom.iso"))
        XCTAssertEqual(fileSystem.extendPath(Folder("./Build")), Folder("/project/root/Build"))
        XCTAssertEqual(fileSystem.extendPath(Folder("../sibling")), Folder("/project/sibling"))
    }

    /// `Folder.init` strips a trailing separator, so `"./"` — plainly
    /// relative — arrives here as `"."`. Both spell the current directory
    /// and both must resolve against it: treating the bare form as absolute
    /// made the same folder mean the config's `rootFolder` when written
    /// `./x` and the process's own working directory when written `.`.
    func testABareDotResolvesLikeAnyOtherRelativePath() {
        XCTAssertEqual(Folder("./").path, ".", "the premise: the two spellings are one path")
        XCTAssertEqual(fileSystem.extendPath(Folder(".")), Folder("/project/root"))
        XCTAssertEqual(fileSystem.extendPath(Folder("..")), Folder("/project"))
    }

    // MARK: - Through the protocol

    /// `resolvedPath(of:)` is how a caller outside the tree — the one that
    /// hands a path to a launched program — asks the same question.
    func testResolvedPathMatchesExtendPathOnDisk() {
        let tree: FileSystemTree = fileSystem
        XCTAssertEqual(tree.resolvedPath(of: File("./tools/patch.sh")), File("/project/root/./tools/patch.sh"))
        XCTAssertEqual(tree.resolvedPath(of: Folder(".")), Folder("/project/root"))
    }

    /// A streamed tree resolves through whatever backs it, so wrapping the
    /// on-disk tree keeps the resolution and wrapping an in-memory one has
    /// none to keep.
    func testStreamedResolutionFollowsTheBackingTree() {
        XCTAssertEqual(
            StreamedFileSystem(fileSystem).resolvedPath(of: Folder("./Build")),
            Folder("/project/root/Build")
        )
        XCTAssertEqual(
            StreamedFileSystem(materializing: InMemoryFST()).resolvedPath(of: Folder("./Build")),
            Folder("./Build"),
            "a tree with no current directory has nothing to resolve against"
        )
    }
}
