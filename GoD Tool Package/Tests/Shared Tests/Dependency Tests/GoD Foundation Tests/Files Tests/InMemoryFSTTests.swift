//
//  InMemoryFSTTests.swift
//
//  Coverage for the in-memory file system tree, including a regression test
//  for the moveFolder deep-rekey bug.
//
//  Writes throw rather than returning a Bool, so "this should fail" cases
//  assert on the thrown error instead of a `false` return. Creating a folder
//  that already exists and deleting something that isn't there are both
//  deliberate no-ops.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class InMemoryFSTTests: XCTestCase {

    private func data(_ string: String) -> GoDData {
        GoDData(string: string, format: .utf8)
    }

    // MARK: - Files

    func testWriteReadInspectFile() throws {
        let fst = InMemoryFST()
        let file = File("/folder/hello.txt")
        try fst.writeFile(data("hello world"), at: file, overwrite: false)

        let read = fst.readFile(at: file)
        XCTAssertEqual(read?.string(format: .utf8), "hello world")

        let meta = fst.inspectFile(at: file)
        XCTAssertEqual(meta?.filename, "hello.txt")
        XCTAssertEqual(meta?.filetype, "txt")
        XCTAssertEqual(meta?.filesize, data("hello world").length)
    }

    func testReadMissingFileReturnsNil() {
        let fst = InMemoryFST()
        XCTAssertNil(fst.readFile(at: File("/nope.txt")))
        XCTAssertNil(fst.inspectFile(at: File("/nope.txt")))
    }

    func testWriteOverwriteFalseRejectsExisting() throws {
        let fst = InMemoryFST()
        let file = File("/a.txt")
        try fst.writeFile(data("first"), at: file, overwrite: false)
        XCTAssertThrowsError(try fst.writeFile(data("second"), at: file, overwrite: false))
        XCTAssertEqual(fst.readFile(at: file)?.string(format: .utf8), "first")

        try fst.writeFile(data("second"), at: file, overwrite: true)
        XCTAssertEqual(fst.readFile(at: file)?.string(format: .utf8), "second")
    }

    func testMoveFile() throws {
        let fst = InMemoryFST()
        let src = File("/dir/a.txt")
        let dst = File("/dir/b.txt")
        try fst.writeFile(data("payload"), at: src, overwrite: false)

        try fst.moveFile(at: src, to: dst, overwrite: false)
        XCTAssertNil(fst.readFile(at: src))
        XCTAssertEqual(fst.readFile(at: dst)?.string(format: .utf8), "payload")

        // Old path removed from parent listing.
        let contents = fst.inspectFolder(at: Folder("/dir"))
        XCTAssertEqual(contents?.files.map(\.path), ["/dir/b.txt"])
    }

    func testMoveFileRejectedWhenDestinationExistsWithoutOverwrite() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("a"), at: File("/a.txt"), overwrite: false)
        try fst.writeFile(data("b"), at: File("/b.txt"), overwrite: false)
        XCTAssertThrowsError(try fst.moveFile(at: File("/a.txt"), to: File("/b.txt"), overwrite: false))
        try fst.moveFile(at: File("/a.txt"), to: File("/b.txt"), overwrite: true)
        XCTAssertEqual(fst.readFile(at: File("/b.txt"))?.string(format: .utf8), "a")
    }

    func testMoveMissingFileThrows() {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try fst.moveFile(at: File("/ghost.txt"), to: File("/x.txt"), overwrite: false))
    }

    func testDeleteFile() throws {
        let fst = InMemoryFST()
        let file = File("/dir/a.txt")
        try fst.writeFile(data("x"), at: file, overwrite: false)
        try fst.deleteFile(at: file)
        XCTAssertNil(fst.readFile(at: file))
        XCTAssertEqual(fst.inspectFolder(at: Folder("/dir"))?.files.count ?? 0, 0)
    }

    func testDeleteMissingFileIsNoOp() {
        let fst = InMemoryFST()
        XCTAssertNoThrow(try fst.deleteFile(at: File("/ghost.txt")))
    }

    // MARK: - Folders

    func testCreateAndInspectEmptyFolder() throws {
        let fst = InMemoryFST()
        try fst.createFolder(at: Folder("/empty"), overwrite: false)
        let meta = fst.inspectFolder(at: Folder("/empty"))
        XCTAssertEqual(meta?.name, "empty")
        XCTAssertEqual(meta?.size, 0)
        XCTAssertTrue(meta?.files.isEmpty ?? false)
        XCTAssertTrue(meta?.subFolders.isEmpty ?? false)
    }

    func testInspectMissingFolderReturnsNil() {
        let fst = InMemoryFST()
        XCTAssertNil(fst.inspectFolder(at: Folder("/missing")))
    }

    /// Ensuring a folder exists is idempotent — callers do it routinely
    /// before writing, so a second create must not be an error.
    func testCreateFolderIsIdempotent() throws {
        let fst = InMemoryFST()
        try fst.createFolder(at: Folder("/f"), overwrite: false)
        XCTAssertNoThrow(try fst.createFolder(at: Folder("/f"), overwrite: false))
        XCTAssertNotNil(fst.inspectFolder(at: Folder("/f")))
    }

    /// Re-creating a folder must not drop the files already inside it.
    func testCreateFolderPreservesExistingContents() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("keep me"), at: File("/f/a.txt"), overwrite: false)
        try fst.createFolder(at: Folder("/f"), overwrite: false)
        XCTAssertEqual(fst.readFile(at: File("/f/a.txt"))?.string(format: .utf8), "keep me")
    }

    func testInspectFolderDeepSizeAcrossSubfolders() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("12345"), at: File("/root/a.txt"), overwrite: false)          // 5
        try fst.writeFile(data("678"), at: File("/root/sub/b.txt"), overwrite: false)         // 3
        try fst.writeFile(data("9012"), at: File("/root/sub/deep/c.txt"), overwrite: false)   // 4

        let meta = fst.inspectFolder(at: Folder("/root"))
        XCTAssertEqual(meta?.size, 12)
        XCTAssertEqual(meta?.files.map(\.path), ["/root/a.txt"])
        XCTAssertEqual(meta?.subFolders.map(\.path), ["/root/sub"])
    }

    func testDeleteFolderRecursive() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("a"), at: File("/root/a.txt"), overwrite: false)
        try fst.writeFile(data("b"), at: File("/root/sub/b.txt"), overwrite: false)

        try fst.deleteFolder(at: Folder("/root"))
        XCTAssertNil(fst.readFile(at: File("/root/a.txt")))
        XCTAssertNil(fst.readFile(at: File("/root/sub/b.txt")))
        XCTAssertNil(fst.inspectFolder(at: Folder("/root")))
        XCTAssertNil(fst.inspectFolder(at: Folder("/root/sub")))
    }

    func testDeleteMissingFolderIsNoOp() {
        let fst = InMemoryFST()
        XCTAssertNoThrow(try fst.deleteFolder(at: Folder("/ghost")))
    }

    func testMoveFolderRejectedWhenDestinationExistsWithoutOverwrite() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("x"), at: File("/A/f.txt"), overwrite: false)
        try fst.createFolder(at: Folder("/B"), overwrite: false)
        XCTAssertThrowsError(try fst.moveFolder(at: Folder("/A"), to: Folder("/B"), overwrite: false))
    }

    func testMoveMissingFolderThrows() {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try fst.moveFolder(at: Folder("/ghost"), to: Folder("/x"), overwrite: false))
    }

    // MARK: - moveFolder regression (would FAIL before the deep-rekey fix)

    func testMoveFolderRekeysDescendants() throws {
        let fst = InMemoryFST()
        try fst.createFolder(at: Folder("/A"), overwrite: false)
        try fst.writeFile(data("nested-data"), at: File("/A/sub/file"), overwrite: false)
        try fst.writeFile(data("top-data"), at: File("/A/top.txt"), overwrite: false)

        try fst.moveFolder(at: Folder("/A"), to: Folder("/B"), overwrite: false)

        // New paths resolve to the moved data.
        XCTAssertEqual(fst.readFile(at: File("/B/sub/file"))?.string(format: .utf8), "nested-data")
        XCTAssertEqual(fst.readFile(at: File("/B/top.txt"))?.string(format: .utf8), "top-data")

        // Old paths are gone.
        XCTAssertNil(fst.readFile(at: File("/A/sub/file")))
        XCTAssertNil(fst.readFile(at: File("/A/top.txt")))
        XCTAssertNil(fst.inspectFolder(at: Folder("/A")))

        // Folder listing reflects the moved (rekeyed) children, not stale ones.
        let bMeta = fst.inspectFolder(at: Folder("/B"))
        XCTAssertEqual(bMeta?.files.map(\.path), ["/B/top.txt"])
        XCTAssertEqual(bMeta?.subFolders.map(\.path), ["/B/sub"])
        XCTAssertEqual(bMeta?.size, data("nested-data").length + data("top-data").length)

        let subMeta = fst.inspectFolder(at: Folder("/B/sub"))
        XCTAssertEqual(subMeta?.files.map(\.path), ["/B/sub/file"])
    }

    // MARK: - Convenience protocol helpers

    func testRenameFileHelper() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("x"), at: File("/dir/old.txt"), overwrite: false)
        try fst.rename(file: File("/dir/old.txt"), to: "new.txt")
        XCTAssertEqual(fst.readFile(at: File("/dir/new.txt"))?.string(format: .utf8), "x")
    }

    func testItemExists() throws {
        let fst = InMemoryFST()
        try fst.writeFile(data("x"), at: File("/dir/a.txt"), overwrite: false)
        XCTAssertTrue(fst.itemExists(at: File("/dir/a.txt")))
        XCTAssertFalse(fst.itemExists(at: File("/dir/none.txt")))
        XCTAssertTrue(fst.itemExists(at: Folder("/dir")))
        XCTAssertFalse(fst.itemExists(at: Folder("/nope")))
    }

    func testCodableRoundTripViaFST() throws {
        struct Payload: Codable, Equatable { let a: Int; let b: String }
        let fst = InMemoryFST()
        let value = Payload(a: 7, b: "seven")
        try fst.writeFile(value, at: File("/data.json"), overwrite: false)
        let decoded: Payload? = fst.readFile(at: File("/data.json"))
        XCTAssertEqual(decoded, value)
    }
}
