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
        apploader.entryPoint = UInt32(0x81200000)
        apploader.size = 64
        apploader.trailerSize = 0
        isoData.write(struct: apploader, atAddress: 0x2440)
        // Write apploader code (64 bytes of zeros is fine)

        // DOL at offset 0x2500 (aligned after apploader)
        let dolOffset = 0x2500
        let dolStruct = dolphinEngine.dolHeaderStruct
        let dolHeader = StructData(definition: dolStruct, byteOrder: .big)
        dolHeader.entryPoint = UInt32(0x80003100)
        dolHeader.bssSize = UInt32(0)
        dolHeader.bssRAMAddress = UInt32(0)
        dolHeader.textSectionsOffsets = [UInt32](repeating: 0, count: 7)
        dolHeader.textSectionsSizes = [UInt32](repeating: 0, count: 7)
        dolHeader.textSectionsRAMAddresses = [UInt32](repeating: 0, count: 7)
        dolHeader.dataSectionsOffsets = [UInt32](repeating: 0, count: 11)
        dolHeader.dataSectionsSizes = [UInt32](repeating: 0, count: 11)
        dolHeader.dataSectionsRAMAddresses = [UInt32](repeating: 0, count: 11)
        isoData.write(struct: dolHeader, atAddress: dolOffset)

        // FST at offset 0x2600 (right after DOL header, which is 0x100 bytes)
        let fstOffset = dolOffset + dolStruct.length

        // Build a minimal FST: root + 1 file
        let fstRootStruct = dolphinEngine.fstRootEntryStruct
        let fstFileStruct = dolphinEngine.fstFileEntryStruct

        let rootEntry = StructData(definition: fstRootStruct, byteOrder: .big)
        rootEntry.isDirectory = true
        rootEntry.entryCount = 2

        let fileEntry = StructData(definition: fstFileStruct, byteOrder: .big)
        fileEntry.isDirectory = false
        fileEntry.nameOffset = 0  // "test.bin" at string offset 0
        fileEntry.fileOffset = UInt32(0x8000)  // file at user offset 0x8000
        fileEntry.fileSize = UInt32(64)

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
        boot.mainExecutableOffset = dolOffset
        boot.fstOffset = fstOffset
        boot.fstSize = fstSize
        boot.maxFstSize = fstSize
        boot.userDataOffset = userOffset
        boot.userDataLength = 64
        isoData.write(struct: boot, atAddress: 0)

        return isoData
    }

    // MARK: - Parse and verify

    func testParseMinimalISO() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()

        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        // System files should exist
        XCTAssertNotNil(iso.readFile(at: File("/sys/boot.bin")))
        XCTAssertNotNil(iso.readFile(at: File("/sys/bi2.bin")))
        XCTAssertNotNil(iso.readFile(at: File("/sys/apploader.img")))
        XCTAssertNotNil(iso.readFile(at: File("/sys/main.dol")))
        XCTAssertNotNil(iso.readFile(at: File("/sys/fst.bin")))

        // User file should exist
        let testFile = iso.readFile(at: File("/files/test.bin"))
        XCTAssertNotNil(testFile)
        XCTAssertEqual(testFile?.length, 64)
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
        XCTAssertNotNil(rebuilt.readFile(at: File("/sys/boot.bin")))
        XCTAssertNotNil(rebuilt.readFile(at: File("/files/test.bin")))

        let originalFile = iso.readFile(at: File("/files/test.bin"))
        let rebuiltFile = rebuilt.readFile(at: File("/files/test.bin"))
        XCTAssertEqual(originalFile?.rawBytes, rebuiltFile?.rawBytes, "User file data should survive round-trip")
    }

    // MARK: - File system operations

    func testWriteAndReadFile() throws {
        let (dolphinEngine, gamecubeEngine) = try defaultEngines()
        let isoData = try buildMinimalISO()
        let iso = try GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)

        let newData = GoDData(byteStream: [UInt8(1), UInt8(2), UInt8(3), UInt8(4)], byteOrder: .big)
        iso.writeFile(newData, at: File("/files/new.bin"), overwrite: true)

        let readBack = iso.readFile(at: File("/files/new.bin"))
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
