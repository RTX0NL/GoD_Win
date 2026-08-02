import XCTest
@testable import GameCube
@testable import Dolphin
@testable import GoDFoundation
@testable import Structs

final class GamecubeISOTests: XCTestCase {

    private func defaultEngines() throws -> (DolphinEngine, GamecubeEngine) {
        (try DolphinEngine.defaults(), try GamecubeEngine.defaults())
    }

    /// Build a minimal valid GameCube ISO for testing.
    private func buildMinimalISO() throws -> GoDData {
        let (dolphinEngine, _) = try defaultEngines()

        let isoData = GoDData(length: 0x100000, byteOrder: .big)

        // Boot.bin at offset 0
        let bootStruct = dolphinEngine.bootDataStruct
        let boot = StructData(definition: bootStruct, byteOrder: .big)

        // Game ID
        let gameID = "TEST".data(format: .utf8)
        isoData.write(gameID, atAddress: 0)

        // Bi2.bin at offset 0x440
        let bi2Struct = dolphinEngine.bi2Struct
        let bi2 = StructData(definition: bi2Struct, byteOrder: .big)
        isoData.write(struct: bi2, atAddress: 0x440)

        // Apploader at offset 0x2440
        let apploaderStruct = dolphinEngine.apploaderHeaderStruct
        let apploader = StructData(definition: apploaderStruct, byteOrder: .big)
        apploader.date = "2024/01/01".data(format: .ascii_big)
        apploader.entry_point = UInt32(0x81200000)
        apploader.size = 64
        apploader.trailer_size = 0
        isoData.write(struct: apploader, atAddress: 0x2440)
        // Write apploader code (64 bytes of zeros is fine)

        // DOL at offset 0x2500 (aligned after apploader)
        let dolOffset = 0x2500
        let dolStruct = dolphinEngine.dolHeaderStruct
        let dolHeader = StructData(definition: dolStruct, byteOrder: .big)
        dolHeader.entry_point = UInt32(0x80003100)
        dolHeader.BSS_size = UInt32(0)
        dolHeader.BSS_RAM_address = UInt32(0)
        dolHeader.text_sections_offsets = [UInt32](repeating: 0, count: 7)
        dolHeader.text_sections_sizes = [UInt32](repeating: 0, count: 7)
        dolHeader.text_sections_RAM_addresses = [UInt32](repeating: 0, count: 7)
        dolHeader.data_sections_offsets = [UInt32](repeating: 0, count: 11)
        dolHeader.data_sections_sizes = [UInt32](repeating: 0, count: 11)
        dolHeader.data_sections_RAM_addresses = [UInt32](repeating: 0, count: 11)
        isoData.write(struct: dolHeader, atAddress: dolOffset)

        // FST at offset 0x2600 (right after DOL header, which is 0x100 bytes)
        let fstOffset = dolOffset + dolStruct.length

        // Build a minimal FST: root + 1 file
        let fstRootStruct = dolphinEngine.fstRootEntryStruct
        let fstFileStruct = dolphinEngine.fstFileEntryStruct

        let rootEntry = StructData(definition: fstRootStruct, byteOrder: .big)
        rootEntry.is_directory = true
        rootEntry.entry_count = 2

        let fileEntry = StructData(definition: fstFileStruct, byteOrder: .big)
        fileEntry.is_directory = false
        fileEntry.name_offset = 0  // "test.bin" at string offset 0
        fileEntry.file_offset = UInt32(0x8000)  // file at user offset 0x8000
        fileEntry.file_size = UInt32(64)

        isoData.write(struct: rootEntry, atAddress: fstOffset)
        isoData.write(struct: fileEntry, atAddress: fstOffset + 12)

        // String table: "test.bin\0"
        let stringTableOffset = fstOffset + 24  // 2 entries × 12 bytes
        isoData.write("test.bin".data(format: .utf8), atAddress: stringTableOffset)
        isoData.write(UInt8(0), atAddress: stringTableOffset + 8)

        let fstSize = 24 + 9  // 2 entries + "test.bin\0"

        // User data section
        let userOffset = 0x8000
        // Write test file data
        let testFileData = GoDData(byteStream: (0..<64).map { UInt8($0) }, byteOrder: .big)
        isoData.write(testFileData, atAddress: userOffset)

        // Update boot.bin
        boot.main_executable_offset = dolOffset
        boot.fst_offset = fstOffset
        boot.fst_size = fstSize
        boot.max_fst_size = fstSize
        boot.user_data_offset = userOffset
        boot.user_data_length = 64
        isoData.write(struct: boot, atAddress: 0)

        return isoData
    }

    // MARK: - Parse and verify

    func testParseMinimalISO() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()

        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        // System files should exist
        XCTAssertNotNil(iso.readFile(at: File("/sys/boot.bin"))?.allData)
        XCTAssertNotNil(iso.readFile(at: File("/sys/bi2.bin"))?.allData)
        XCTAssertNotNil(iso.readFile(at: File("/sys/apploader.img"))?.allData)
        XCTAssertNotNil(iso.readFile(at: File("/sys/main.dol"))?.allData)
        XCTAssertNotNil(iso.readFile(at: File("/sys/fst.bin"))?.allData)

        // User file should exist
        let testFile = iso.readFile(at: File("/files/test.bin"))?.allData
        XCTAssertNotNil(testFile)
        XCTAssertEqual(testFile?.length, 64)
    }

    /// The parser takes a `GoDReadable`, so it must produce the same tree
    /// whether the disc is resident in memory or streamed off disk. This is
    /// the property that lets a dump avoid holding a 1.4 GB image: if the two
    /// sources ever disagreed, they would disagree only on real discs.
    func testParsingFromAStreamedFileMatchesParsingFromMemory() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GamecubeISOStreamed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let discURL = scratch.appendingPathComponent("disc.iso")
        try Data(isoData.rawBytes).write(to: discURL)
        let streamed = try GoDStreamedData(file: File(nativePath: discURL.path))

        let fromMemory = try GamecubeISO(
            data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine
        )
        let fromDisk = try GamecubeISO(
            data: streamed, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine
        )

        for path in ["/sys/boot.bin", "/sys/bi2.bin", "/sys/apploader.img",
                     "/sys/main.dol", "/sys/fst.bin", "/files/test.bin"] {
            let memory = fromMemory.readFile(at: File(path))?.allData?.rawBytes
            XCTAssertNotNil(memory, path)
            XCTAssertEqual(fromDisk.readFile(at: File(path))?.allData?.rawBytes, memory, path)
        }
    }

    /// A little-endian source would read every offset byte-swapped and fail
    /// somewhere far from the cause, so it is rejected at the door.
    func testLittleEndianSourceIsRejected() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let littleEndian = GoDData(byteStream: try buildMinimalISO().rawBytes, byteOrder: .little)
        XCTAssertThrowsError(
            try GamecubeISO(data: littleEndian, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
        )
    }

    // MARK: - Round-trip

    func testRoundTripFromFST() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()

        // Parse
        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        // Rebuild from FST
        let rebuilt = try GamecubeISO(
            fst: iso,
            rootFolder: Folder("/"),
            dolphinEngine: dolphinEngine,
            gamecubeEngine: gamecubeEngine
        )

        // Verify rebuilt ISO has the same files
        XCTAssertNotNil(rebuilt.readFile(at: File("/sys/boot.bin"))?.allData)
        XCTAssertNotNil(rebuilt.readFile(at: File("/files/test.bin"))?.allData)

        let originalFile = iso.readFile(at: File("/files/test.bin"))?.allData
        let rebuiltFile = rebuilt.readFile(at: File("/files/test.bin"))?.allData
        XCTAssertEqual(originalFile?.rawBytes, rebuiltFile?.rawBytes, "User file data should survive round-trip")
    }

    // MARK: - File system operations

    func testWriteAndReadFile() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()
        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        let newData = GoDData(byteStream: [UInt8(1), UInt8(2), UInt8(3), UInt8(4)], byteOrder: .big)
        try iso.writeFile(newData, at: File("/files/new.bin"), overwrite: true)

        let readBack = iso.readFile(at: File("/files/new.bin"))?.allData
        XCTAssertEqual(readBack?.rawBytes, newData.rawBytes)
    }

    func testFolderInspection() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()
        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        let root = iso.inspectFolder(at: Folder("/"))
        XCTAssertNotNil(root)
        XCTAssertTrue(root!.subFolders.contains(Folder("/sys")))
        XCTAssertTrue(root!.subFolders.contains(Folder("/files")))
    }
}
