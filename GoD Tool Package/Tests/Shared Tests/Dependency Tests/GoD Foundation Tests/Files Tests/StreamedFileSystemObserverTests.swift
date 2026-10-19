//
//  StreamedFileSystemObserverTests.swift
//  GoDFoundationTests
//
//  A `StreamedFileSystem` tells its observer about every change before it
//  makes it, and doesn't make a change the observer throws on. The MCP
//  server stops a cancelled run and lists what a run wrote through this.
//

import XCTest
@testable import GoDFoundation

final class StreamedFileSystemObserverTests: XCTestCase {

    private final class Recorder: FileSystemObserver {
        var changes: [FileSystemChange] = []
        var refuse = false

        func willChange(_ change: FileSystemChange) throws {
            changes.append(change)
            if refuse { throw CancellationError() }
        }
    }

    private func bytes(_ count: Int) -> GoDData {
        GoDData(byteStream: [UInt8](repeating: 0x41, count: count), byteOrder: .big)
    }

    func testObserverSeesEveryChangeInOrder() throws {
        let tree = InMemoryFST()
        let recorder = Recorder()
        let fileSystem = StreamedFileSystem(materializing: tree, observer: recorder)

        try fileSystem.writeFile(bytes(4), at: File("/a/one.bin"), overwrite: true)
        try fileSystem.moveFile(at: File("/a/one.bin"), to: File("/a/two.bin"), overwrite: true)
        try fileSystem.resizeFile(at: File("/a/two.bin"), to: 8)
        try fileSystem.createFolder(at: Folder("/b"), overwrite: true)
        try fileSystem.deleteFile(at: File("/a/two.bin"))
        try fileSystem.moveFolder(at: Folder("/b"), to: Folder("/c"), overwrite: true)
        try fileSystem.deleteFolder(at: Folder("/c"))

        XCTAssertEqual(recorder.changes, [
            .writeFile(File("/a/one.bin")),
            .moveFile(from: File("/a/one.bin"), to: File("/a/two.bin")),
            .resizeFile(File("/a/two.bin")),
            .createFolder(Folder("/b")),
            .deleteFile(File("/a/two.bin")),
            .moveFolder(from: Folder("/b"), to: Folder("/c")),
            .deleteFolder(Folder("/c")),
        ])
    }

    func testRefusedChangeIsNotMade() throws {
        let tree = InMemoryFST()
        let recorder = Recorder()
        let fileSystem = StreamedFileSystem(materializing: tree, observer: recorder)
        try fileSystem.writeFile(bytes(4), at: File("/kept.bin"), overwrite: true)

        recorder.refuse = true
        XCTAssertThrowsError(try fileSystem.writeFile(bytes(4), at: File("/new.bin"), overwrite: true)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertThrowsError(try fileSystem.deleteFile(at: File("/kept.bin")))

        XCTAssertNil(tree.readFile(at: File("/new.bin")))
        XCTAssertNotNil(tree.readFile(at: File("/kept.bin")))
    }

    func testWrittenFileIsWhereNewContentsLand() {
        XCTAssertEqual(FileSystemChange.writeFile(File("/a")).writtenFile, File("/a"))
        XCTAssertEqual(FileSystemChange.resizeFile(File("/a")).writtenFile, File("/a"))
        XCTAssertEqual(FileSystemChange.moveFile(from: File("/a"), to: File("/b")).writtenFile, File("/b"))
        XCTAssertNil(FileSystemChange.deleteFile(File("/a")).writtenFile)
        XCTAssertNil(FileSystemChange.createFolder(Folder("/a")).writtenFile)
    }

    /// On disk, a `./` path is reported where it really lands, so a caller
    /// listing a run's outputs doesn't have to know the run's root.
    func testOnDiskPathsAreReportedResolved() throws {
        let disk = FileSystem.shared
        let scratch = Folder(nativePath: NSTemporaryDirectory())
            .folder("goddess-observer-\(UUID().uuidString.prefix(8))")
        defer { try? disk.deleteFolder(at: scratch) }
        try disk.createFolder(at: scratch, overwrite: true)

        let recorder = Recorder()
        let fileSystem = StreamedFileSystem(disk, observer: recorder)
        try fileSystem.withCurrentDirectory(scratch) {
            try fileSystem.writeFile(bytes(4), at: File("./out.bin"), overwrite: true)
        }

        XCTAssertEqual(recorder.changes, [.writeFile(scratch.file("out.bin"))])
    }
}
