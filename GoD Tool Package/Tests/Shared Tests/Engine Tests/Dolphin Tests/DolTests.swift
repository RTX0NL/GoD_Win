import XCTest
@testable import Dolphin
@testable import GoDFoundation
@testable import Structs

final class DolTests: XCTestCase {

    private func defaultEngine() throws -> DolphinEngine {
        try DolphinEngine.defaults()
    }

    // MARK: - StructData field round-trips

    func testStructDataScalarFieldRoundTrip() throws {
        let engine = try defaultEngine()
        let dolStruct = engine.dolHeaderStruct

        let header = StructData(definition: dolStruct, byteOrder: .big)
        header.entryPoint = UInt32(0x80003100)
        header.bssSize = UInt32(0x1000)
        header.bssRAMAddress = UInt32(0x80500000)

        let readEntry: UInt32 = try header.entryPoint
        let readBSS: UInt32 = try header.bssSize
        let readBSSAddr: UInt32 = try header.bssRAMAddress
        XCTAssertEqual(readEntry, 0x80003100)
        XCTAssertEqual(readBSS, 0x1000)
        XCTAssertEqual(readBSSAddr, 0x80500000)
    }

    // MARK: - Section structure

    func testEmptySections() throws {
        let engine = try defaultEngine()

        let dol = Dol(dolphinEngine: engine, textSections: [], dataSections: [],
                      bssRAMAddress: 0, bssSize: 0, entryPoint: 0x80003100)

        let serialized = try dol.data
        let reparsed = try Dol(data: serialized, dolphinEngine: engine)

        XCTAssertEqual(reparsed.entryPoint, 0x80003100)
        for section in reparsed.textSections { XCTAssertEqual(section.assembly.length, 0) }
        for section in reparsed.dataSections { XCTAssertEqual(section.data.length, 0) }
    }

    func testSectionSlotCount() throws {
        let engine = try defaultEngine()

        let dol = Dol(dolphinEngine: engine,
                      textSections: [Dol.TextSection(RAMAddress: 0x80003100, assembly: GoDData(length: 16, byteOrder: .big))],
                      dataSections: [],
                      bssRAMAddress: 0, bssSize: 0, entryPoint: 0x80003100)

        let reparsed = try Dol(data: dol.data, dolphinEngine: engine)
        XCTAssertEqual(reparsed.textSections.count, 7, "DOL always has 7 text section slots")
        XCTAssertEqual(reparsed.dataSections.count, 11, "DOL always has 11 data section slots")
    }

    // MARK: - Parse from big-endian data (real-world case)

    func testParseFromBigEndianData() throws {
        let engine = try defaultEngine()
        let dolStruct = engine.dolHeaderStruct

        // Manually construct a big-endian DOL header the way a real ISO would have it
        let headerData = GoDData(length: dolStruct.length + 128 + 64, byteOrder: .big)

        // Text section 0: offset=0x100 (header length), RAM=0x80003100, size=128
        headerData.write(UInt32(0x00000100), atAddress: 0)    // textOffsets[0]
        headerData.write(UInt32(0x80003100), atAddress: 0x48) // textRAMAddresses[0]
        headerData.write(UInt32(0x00000080), atAddress: 0x90) // textSizes[0]

        // Data section 0: offset=0x180 (after text), RAM=0x80400000, size=64
        headerData.write(UInt32(0x00000180), atAddress: 0x1C) // dataOffsets[0]
        headerData.write(UInt32(0x80400000), atAddress: 0x64) // dataRAMAddresses[0]
        headerData.write(UInt32(0x00000040), atAddress: 0xAC) // dataSizes[0]

        // Entry point, BSS
        headerData.write(UInt32(0x80003100), atAddress: 0xE0) // entryPoint
        headerData.write(UInt32(0x80500000), atAddress: 0xD8) // bssRAMAddress
        headerData.write(UInt32(0x00001000), atAddress: 0xDC) // bssSize

        let dol = try Dol(data: headerData, dolphinEngine: engine)

        XCTAssertEqual(dol.entryPoint, 0x80003100)
        XCTAssertEqual(dol.bssSize, 0x1000)
        XCTAssertEqual(dol.bssRAMAddress, 0x80500000)
        XCTAssertEqual(dol.textSections[0].RAMAddress, 0x80003100)
        XCTAssertEqual(dol.textSections[0].assembly.length, 128)
        XCTAssertEqual(dol.dataSections[0].RAMAddress, 0x80400000)
        XCTAssertEqual(dol.dataSections[0].data.length, 64)
    }

    // NOTE: DOL double round-trip (parse → serialize → reparse) was previously broken for
    // array fields due to a byte order issue with Array<UInt32>.rawData using .unspecified
    // byte order. This has been fixed: rawData now requires an explicit byteOrder parameter.
}
