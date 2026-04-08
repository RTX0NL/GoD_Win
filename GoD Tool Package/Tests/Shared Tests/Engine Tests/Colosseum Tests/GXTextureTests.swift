import XCTest
import GoDFoundation
import GTX

final class GXTextureTests: XCTestCase {

    func testParseHeader() {
        var header = [UInt8](repeating: 0, count: 0x80)
        header[0] = 0x00; header[1] = 0x04
        header[2] = 0x00; header[3] = 0x04
        header[4] = 32
        header[0x0B] = 0x45
        header[0x28] = 0; header[0x29] = 0; header[0x2A] = 0; header[0x2B] = 0x80

        let data = GoDData(byteStream: header, byteOrder: .big)
        let decoder = GXTextureDecoder()
        let meta = decoder.parseHeader(data: data)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.width, 4)
        XCTAssertEqual(meta?.height, 4)
        XCTAssertEqual(meta?.format, .rgba32)
    }

    func testSimpleRGB() {
        var d = [UInt8](repeating: 0, count: 0xA0)
        d[1] = 4; d[3] = 4; d[4] = 16; d[0x0B] = 0x44; d[0x2B] = 0x80
        let data = GoDData(byteStream: d, byteOrder: .big)
        let decoder = GXTextureDecoder()
        let result = decoder.decode(data: data)
        XCTAssertNotNil(result)
    }
}
