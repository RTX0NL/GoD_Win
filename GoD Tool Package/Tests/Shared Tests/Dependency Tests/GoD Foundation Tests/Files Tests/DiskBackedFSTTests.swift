//
//  DiskBackedFSTTests.swift
//
//  `DiskBackedFST` only earns its keep if it can be dropped in wherever
//  `InMemoryFST` is used, so most of this runs the *same* assertions against
//  both trees. A behavioural difference between them would show up as a bug
//  that only appears with one backing store — the worst kind to chase.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class DiskBackedFSTTests: XCTestCase {

    private var scratch: DiskBackedFST!

    override func setUpWithError() throws {
        scratch = try DiskBackedFST.temporary(name: "GODDESSTests")
    }

    override func tearDownWithError() throws {
        try scratch?.removeBackingStore()
        scratch = nil
    }

    private func data(_ string: String) -> GoDData {
        GoDData(string: string, format: .utf8)
    }

    /// Every tree the protocol is meant to cover, so a contract assertion
    /// runs against all of them.
    private func allTrees() throws -> [(name: String, tree: FileSystemTree)] {
        [
            ("InMemoryFST", InMemoryFST()),
            ("DiskBackedFST", try DiskBackedFST.temporary(name: "GODDESSTests")),
        ]
    }

    // MARK: - Contract parity

    func testWriteReadRoundTripMatchesAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            let file = File("/folder/nested/hello.txt")
            try tree.writeFile(data("hello world"), at: file, overwrite: false)
            XCTAssertEqual(tree.readFile(at: file)?.string(format: .utf8), "hello world", name)
            XCTAssertEqual(tree.inspectFile(at: file)?.filename, "hello.txt", name)
            XCTAssertEqual(tree.inspectFile(at: file)?.filetype, "txt", name)
            XCTAssertEqual(tree.inspectFile(at: file)?.filesize, 11, name)
        }
    }

    func testMissingReadsReturnNilAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            XCTAssertNil(tree.readFile(at: File("/nope.txt")), name)
            XCTAssertNil(tree.inspectFile(at: File("/nope.txt")), name)
            XCTAssertNil(tree.inspectFolder(at: Folder("/nope")), name)
        }
    }

    func testOverwriteRulesMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            let file = File("/a.txt")
            try tree.writeFile(data("first"), at: file, overwrite: false)
            XCTAssertThrowsError(try tree.writeFile(data("second"), at: file, overwrite: false), name)
            XCTAssertEqual(tree.readFile(at: file)?.string(format: .utf8), "first", name)
            try tree.writeFile(data("second"), at: file, overwrite: true)
            XCTAssertEqual(tree.readFile(at: file)?.string(format: .utf8), "second", name)
        }
    }

    /// The no-op rules settled when writes became throwing: ensuring a folder
    /// exists and deleting something absent are both fine.
    func testNoOpRulesMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            try tree.createFolder(at: Folder("/f"), overwrite: false)
            XCTAssertNoThrow(try tree.createFolder(at: Folder("/f"), overwrite: false), name)
            XCTAssertNoThrow(try tree.deleteFile(at: File("/ghost.txt")), name)
            XCTAssertNoThrow(try tree.deleteFolder(at: Folder("/ghost")), name)
        }
    }

    func testCreateFolderOverAFileThrowsAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            try tree.writeFile(data("x"), at: File("/thing"), overwrite: false)
            XCTAssertThrowsError(try tree.createFolder(at: Folder("/thing"), overwrite: false), name)
        }
    }

    func testFolderListingAndDeepSizeMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            try tree.writeFile(data("12345"), at: File("/root/a.txt"), overwrite: false)
            try tree.writeFile(data("678"), at: File("/root/sub/b.txt"), overwrite: false)
            try tree.writeFile(data("9012"), at: File("/root/sub/deep/c.txt"), overwrite: false)

            let meta = tree.inspectFolder(at: Folder("/root"))
            XCTAssertEqual(meta?.size, 12, "\(name): deep size covers the whole subtree")
            XCTAssertEqual(meta?.files.map(\.path), ["/root/a.txt"], name)
            XCTAssertEqual(meta?.subFolders.map(\.path), ["/root/sub"], name)
        }
    }

    func testMoveAndDeleteMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            try tree.writeFile(data("payload"), at: File("/dir/a.txt"), overwrite: false)
            try tree.moveFile(at: File("/dir/a.txt"), to: File("/dir/b.txt"), overwrite: false)
            XCTAssertNil(tree.readFile(at: File("/dir/a.txt")), name)
            XCTAssertEqual(tree.readFile(at: File("/dir/b.txt"))?.string(format: .utf8), "payload", name)
            XCTAssertThrowsError(try tree.moveFile(at: File("/dir/ghost.txt"), to: File("/x"), overwrite: false), name)

            try tree.deleteFolder(at: Folder("/dir"))
            XCTAssertNil(tree.inspectFolder(at: Folder("/dir")), name)
        }
    }

    // MARK: - Random access

    func testRangeReadsMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            let file = File("/bytes.bin")
            try tree.writeFile(GoDData(byteStream: Array(0..<32).map { UInt8($0) }, byteOrder: .big),
                               at: file, overwrite: false)

            XCTAssertEqual(tree.readFile(at: file, range: 4..<8)?.rawBytes, [4, 5, 6, 7], name)
            XCTAssertEqual(tree.fileSize(at: file), 32, name)
            // A range past the end clamps rather than failing.
            XCTAssertEqual(tree.readFile(at: file, range: 30..<64)?.rawBytes, [30, 31], name)
            XCTAssertEqual(tree.readFile(at: file, range: 64..<80)?.rawBytes, [], name)
            XCTAssertNil(tree.readFile(at: File("/missing.bin"), range: 0..<4), name)
        }
    }

    func testPadFileGrowsWithZerosAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            let file = File("/iso.bin")
            try tree.writeFile(GoDData(byteStream: [1, 2, 3, 4], byteOrder: .big), at: file, overwrite: false)

            try tree.padFile(at: file, toAtLeast: 10)
            XCTAssertEqual(tree.fileSize(at: file), 10, name)
            XCTAssertEqual(tree.readFile(at: file)?.rawBytes, [1, 2, 3, 4, 0, 0, 0, 0, 0, 0], name)

            // Already long enough: leave it alone rather than truncating.
            try tree.padFile(at: file, toAtLeast: 5)
            XCTAssertEqual(tree.fileSize(at: file), 10, name)
        }
    }

    func testAppendAndOffsetWritesMatchAcrossTrees() throws {
        for (name, tree) in try allTrees() {
            guard let tree = tree as? RandomAccessFileSystemTree else {
                return XCTFail("\(name) should offer random access")
            }
            let file = File("/x.bin")
            try tree.writeFile(GoDData(byteStream: [1, 2], byteOrder: .big), at: file, overwrite: false)
            try tree.appendToFile(GoDData(byteStream: [3, 4], byteOrder: .big), at: file)
            XCTAssertEqual(tree.readFile(at: file)?.rawBytes, [1, 2, 3, 4], name)

            try tree.writeFile(GoDData(byteStream: [9], byteOrder: .big), at: file, offset: 1)
            XCTAssertEqual(tree.readFile(at: file)?.rawBytes, [1, 9, 3, 4], name)

            // Writing past the end zero-fills the gap rather than leaving it
            // undefined.
            try tree.writeFile(GoDData(byteStream: [7], byteOrder: .big), at: file, offset: 6)
            XCTAssertEqual(tree.readFile(at: file)?.rawBytes, [1, 9, 3, 4, 0, 0, 7], name)

            try tree.resizeFile(at: file, to: 2)
            XCTAssertEqual(tree.readFile(at: file)?.rawBytes, [1, 9], name)
        }
    }

    // MARK: - Backing store

    func testBackingStoreMirrorsTheLogicalTree() throws {
        try scratch.writeFile(data("hi"), at: File("/Data/Text/a.msg"), overwrite: false)
        // Deliberately a plain mirror, so a failed run can be inspected by hand.
        let real = URL(fileURLWithPath: scratch.root.path)
            .appendingPathComponent("Data/Text/a.msg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path))
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "hi")
    }

    /// A logical path can't address anything outside the backing directory,
    /// however many `..` components it carries — paths come from engine config
    /// and archive metadata, so the tree has to be a sandbox.
    func testPathsCannotEscapeTheBackingDirectory() throws {
        try scratch.writeFile(data("contained"), at: File("/../../escape.txt"), overwrite: true)

        let inside = URL(fileURLWithPath: scratch.root.path).appendingPathComponent("escape.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inside.path))

        let outside = URL(fileURLWithPath: scratch.root.path)
            .deletingLastPathComponent()
            .appendingPathComponent("escape.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRemoveBackingStoreIsIdempotent() throws {
        let tree = try DiskBackedFST.temporary(name: "GODDESSTests")
        try tree.writeFile(data("x"), at: File("/a.txt"), overwrite: false)
        let root = tree.root.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: root))

        try tree.removeBackingStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root))
        XCTAssertNoThrow(try tree.removeBackingStore())
    }

    /// A temporary tree cleans up after itself, so a long run doesn't leave
    /// scratch directories behind.
    func testTemporaryTreeIsRemovedWhenReleased() throws {
        var tree: DiskBackedFST? = try DiskBackedFST.temporary(name: "GODDESSTests")
        let root = try XCTUnwrap(tree?.root.path)
        try tree?.writeFile(data("x"), at: File("/a.txt"), overwrite: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root))

        tree = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: root))
    }

    /// A caller-supplied directory is left alone — only `temporary()` trees
    /// own their storage.
    func testSuppliedRootSurvivesRelease() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GODDESSTests-kept-\(UUID().uuidString)")
        var tree: DiskBackedFST? = try DiskBackedFST(root: Folder(base.path))
        try tree?.writeFile(data("x"), at: File("/a.txt"), overwrite: false)
        tree = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: base.path))
        try FileManager.default.removeItem(at: base)
    }
}
