import XCTest
@testable import Dolphin
@testable import GoDFoundation
@testable import Structs

final class ApploaderTests: XCTestCase {

    private func defaultEngine() throws -> DolphinEngine {
        try DolphinEngine.defaults()
    }

    func testRoundTrip() throws {
        let engine = try defaultEngine()

        let appCode = GoDData(byteStream: [UInt8](repeating: 0xCC, count: 1024), byteOrder: .big)
        let trailerCode = GoDData(byteStream: [UInt8](repeating: 0xDD, count: 256), byteOrder: .big)

        // Build an apploader manually: header + appCode + trailerCode
        let headerStruct = engine.apploaderHeaderStruct
        let header = StructData(definition: headerStruct, data: GoDData(length: headerStruct.length, byteOrder: .big))
        header.date = "2024/06/01".data(format: .ascii_big)
        header.entry_point = UInt32(0x81200000)
        header.size = appCode.length
        header.trailer_size = trailerCode.length

        let rawData = header.data
        rawData.append(appCode)
        rawData.append(trailerCode)

        // Parse
        let apploader = try Apploader(data: rawData, engine: engine)
        XCTAssertEqual(apploader.entryPoint, 0x81200000)
        XCTAssertEqual(apploader.appCode.length, 1024)
        XCTAssertEqual(apploader.trailerCode.length, 256)
        XCTAssertTrue(apploader.date.contains("2024"))

        // Re-serialize
        let reserialized = try apploader.data
        XCTAssertEqual(reserialized.rawBytes, rawData.rawBytes, "Apploader round-trip should be byte-identical")
    }

    func testEmptyTrailer() throws {
        let engine = try defaultEngine()

        let headerStruct = engine.apploaderHeaderStruct
        let header = StructData(definition: headerStruct, data: GoDData(length: headerStruct.length, byteOrder: .big))
        header.date = "2024/01/01".data(format: .ascii_big)
        header.entry_point = UInt32(0x81200000)
        header.size = 64
        header.trailer_size = 0

        let appCode = GoDData(byteStream: [UInt8](repeating: 0xAA, count: 64), byteOrder: .big)
        let rawData = header.data
        rawData.append(appCode)

        let apploader = try Apploader(data: rawData, engine: engine)
        XCTAssertEqual(apploader.appCode.length, 64)
        XCTAssertEqual(apploader.trailerCode.length, 0)

        let reserialized = try apploader.data
        XCTAssertEqual(reserialized.length, rawData.length)
    }
}
