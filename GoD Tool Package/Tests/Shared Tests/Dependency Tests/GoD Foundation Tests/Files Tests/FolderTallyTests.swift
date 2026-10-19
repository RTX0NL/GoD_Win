//
//  FolderTallyTests.swift
//  GoDFoundationTests
//
//  `tally(of:)` counts the files under a folder and their bytes. On disk it
//  has its own fast path on Windows (one directory listing per folder, sizes
//  included), so it is checked against the same folder in memory.
//

import XCTest
@testable import GoDFoundation

final class FolderTallyTests: XCTestCase {

    private let sizes = ["a.bin": 10, "sub/b.bin": 2000, "sub/deeper/c.bin": 3, "sub/deeper/d.bin": 0, "other/e.bin": 70000]

    private func populate(_ tree: FileSystemTree, under root: Folder) throws {
        for (path, size) in sizes {
            try tree.writeFile(
                GoDData(byteStream: [UInt8](repeating: 0x41, count: size), byteOrder: .big),
                at: root.file(path),
                overwrite: true
            )
        }
    }

    func testTallyInMemory() throws {
        let tree = InMemoryFST()
        let root = Folder("/root")
        try populate(tree, under: root)

        XCTAssertEqual(tree.tally(of: root), FolderTally(files: 5, bytes: 72013))
        XCTAssertEqual(tree.tally(of: root.folder("sub")), FolderTally(files: 3, bytes: 2003))
        XCTAssertNil(tree.tally(of: Folder("/missing")))
    }

    func testTallyOnDisk() throws {
        let disk = FileSystem.shared
        let root = Folder(nativePath: NSTemporaryDirectory()).folder("goddess-tally-\(UUID().uuidString.prefix(8))")
        defer { try? disk.deleteFolder(at: root) }
        try populate(disk, under: root)
        try disk.createFolder(at: root.folder("empty"), overwrite: true)

        XCTAssertEqual(disk.tally(of: root), FolderTally(files: 5, bytes: 72013))
        XCTAssertEqual(disk.tally(of: root.folder("sub")), FolderTally(files: 3, bytes: 2003))
        XCTAssertEqual(disk.tally(of: root.folder("empty")), FolderTally(files: 0, bytes: 0))
        XCTAssertNil(disk.tally(of: root.folder("missing")))
        XCTAssertEqual(StreamedFileSystem(disk).tally(of: root), FolderTally(files: 5, bytes: 72013))
    }

    func testTallyFollowsTheCurrentDirectory() throws {
        let disk = FileSystem.shared
        let root = Folder(nativePath: NSTemporaryDirectory()).folder("goddess-tally-\(UUID().uuidString.prefix(8))")
        defer { try? disk.deleteFolder(at: root) }
        try populate(disk, under: root)

        let tally = disk.withCurrentDirectory(root) { disk.tally(of: Folder("./sub")) }
        XCTAssertEqual(tally, FolderTally(files: 3, bytes: 2003))
    }
}
