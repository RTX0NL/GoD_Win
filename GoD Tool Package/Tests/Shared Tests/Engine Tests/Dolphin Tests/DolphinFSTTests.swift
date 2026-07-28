import XCTest
@testable import Dolphin
@testable import GoDFoundation
@testable import Structs

final class DolphinFSTTests: XCTestCase {

    private func defaultEngine() throws -> DolphinEngine {
        try DolphinEngine.defaults()
    }

    /// Build an FST binary using the actual StructData API.
    private func buildFST(engine: DolphinEngine, entries: [(isDir: Bool, nameOffset: Int, field1: UInt32, field2: UInt32)], stringTable: String) throws -> GoDData {
        let entrySize = 12
        let stringData = stringTable.data(using: .utf8)!
        let totalSize = entries.count * entrySize + stringData.count
        let data = GoDData(length: totalSize, byteOrder: .big)

        for (i, entry) in entries.enumerated() {
            let offset = i * entrySize
            if i == 0 {
                let root = StructData(definition: engine.fstRootEntryStruct, byteOrder: .big)
                root.is_directory = true
                root.entry_count = Int(entry.field2)
                data.write(struct: root, atAddress: offset)
            } else if entry.isDir {
                let dir = StructData(definition: engine.fstDirectoryEntryStruct, byteOrder: .big)
                dir.is_directory = true
                dir.name_offset = entry.nameOffset
                dir.parent_entry = Int(entry.field1)
                dir.next_entry = Int(entry.field2)
                data.write(struct: dir, atAddress: offset)
            } else {
                let file = StructData(definition: engine.fstFileEntryStruct, byteOrder: .big)
                file.is_directory = false
                file.name_offset = entry.nameOffset
                file.file_offset = entry.field1
                file.file_size = entry.field2
                data.write(struct: file, atAddress: offset)
            }
        }

        let stringBytes = GoDData(byteStream: [UInt8](stringData), byteOrder: .big)
        data.write(stringBytes, atAddress: entries.count * entrySize)
        return data
    }

    private func stringOffsets(_ strings: [String]) -> (offsets: [Int], table: String) {
        var offsets = [Int]()
        var table = ""
        for s in strings {
            offsets.append(table.utf8.count)
            table += s + "\0"
        }
        return (offsets, table)
    }

    // MARK: - Flat file list

    func testParseFlatFileList() throws {
        let engine = try defaultEngine()
        let (off, table) = stringOffsets(["", "a.bin", "b.bin", "c.bin"])
        let fstData = try buildFST(engine: engine, entries: [
            (true, off[0], 0, 4),
            (false, off[1], 0x1000, 0x100),
            (false, off[2], 0x2000, 0x200),
            (false, off[3], 0x3000, 0x300),
        ], stringTable: table)

        let fst = try DolphinFST(tocData: fstData, userSectionOffset: 0, dolphinEngine: engine)
        XCTAssertEqual(fst.files.count, 3)
        XCTAssertEqual(fst.folders.count, 0)
        XCTAssertNotNil(fst.files[File("/files/a.bin")])
        XCTAssertEqual(fst.files[File("/files/a.bin")]?.size, 0x100)
    }

    // MARK: - Nested directories

    func testParseNestedDirectories() throws {
        let engine = try defaultEngine()
        let (off, table) = stringOffsets(["", "dir1", "file1.bin", "dir2", "file2.bin", "file3.bin"])
        let fstData = try buildFST(engine: engine, entries: [
            (true, off[0], 0, 6),
            (true, off[1], 0, 3),
            (false, off[2], 0x1000, 0x100),
            (true, off[3], 0, 5),
            (false, off[4], 0x2000, 0x200),
            (false, off[5], 0x3000, 0x300),
        ], stringTable: table)

        let fst = try DolphinFST(tocData: fstData, userSectionOffset: 0, dolphinEngine: engine)
        XCTAssertEqual(fst.files.count, 3)
        XCTAssertNotNil(fst.files[File("/files/dir1/file1.bin")])
        XCTAssertNotNil(fst.files[File("/files/dir2/file2.bin")])
        XCTAssertNotNil(fst.files[File("/files/file3.bin")])
    }

    // MARK: - Multiple directories ending at same index

    func testMultipleDirectoriesEndAtSameIndex() throws {
        let engine = try defaultEngine()
        let (off, table) = stringOffsets(["", "outer", "inner", "deep.bin", "top.bin"])
        let fstData = try buildFST(engine: engine, entries: [
            (true, off[0], 0, 5),
            (true, off[1], 0, 4),
            (true, off[2], 1, 4),
            (false, off[3], 0x1000, 0x100),
            (false, off[4], 0x2000, 0x200),
        ], stringTable: table)

        let fst = try DolphinFST(tocData: fstData, userSectionOffset: 0, dolphinEngine: engine)
        XCTAssertEqual(fst.files.count, 2)
        XCTAssertNotNil(fst.files[File("/files/outer/inner/deep.bin")])
        XCTAssertNotNil(fst.files[File("/files/top.bin")], "top.bin should be at root level")
    }

    // MARK: - Sibling directories

    func testSiblingDirectoriesNotNested() throws {
        let engine = try defaultEngine()
        let (off, table) = stringOffsets(["", "alpha", "a.bin", "beta", "b.bin", "gamma", "g.bin"])
        let fstData = try buildFST(engine: engine, entries: [
            (true, off[0], 0, 7),
            (true, off[1], 0, 3),
            (false, off[2], 0x1000, 0x100),
            (true, off[3], 0, 5),
            (false, off[4], 0x2000, 0x200),
            (true, off[5], 0, 7),
            (false, off[6], 0x3000, 0x300),
        ], stringTable: table)

        let fst = try DolphinFST(tocData: fstData, userSectionOffset: 0, dolphinEngine: engine)
        XCTAssertEqual(fst.folders.count, 3)
        XCTAssertNotNil(fst.files[File("/files/alpha/a.bin")])
        XCTAssertNotNil(fst.files[File("/files/beta/b.bin")])
        XCTAssertNotNil(fst.files[File("/files/gamma/g.bin")])
        XCTAssertNil(fst.files[File("/files/alpha/beta/b.bin")])
    }

    // MARK: - Round-trip via filesystem init

    func testRoundTripViaFileSystem() throws {
        let engine = try defaultEngine()

        // Build FST from a file system (the other init path)
        let fst = InMemoryFST()
        let root = Folder("/files")
        try fst.createFolder(at: root, overwrite: true)
        try fst.writeFile(GoDData(length: 100, byteOrder: .big), at: File("/files/a.bin"), overwrite: true)
        try fst.writeFile(GoDData(length: 200, byteOrder: .big), at: File("/files/b.bin"), overwrite: true)

        let manifest = DolphinFST(fileSystem: fst, root: root)
        XCTAssertEqual(manifest.files.count, 2)

        let tocData = try manifest.tocData(userOffset: 0x8000, dolphinEngine: engine)
        let reparsed = try DolphinFST(tocData: tocData, userSectionOffset: 0x8000, dolphinEngine: engine)

        XCTAssertEqual(reparsed.files.count, 2)
        for (file, value) in manifest.files {
            XCTAssertEqual(reparsed.files[file]?.size, value.size, "Size mismatch for \(file.path)")
        }
    }
}
