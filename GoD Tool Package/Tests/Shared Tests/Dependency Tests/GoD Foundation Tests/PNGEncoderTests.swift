import XCTest
import GoDFoundation

final class PNGEncoderTests: XCTestCase {

    func testEncode() {
        let pixels: [UInt8] = [
            255, 0, 0, 255,    0, 255, 0, 255,
            0, 0, 255, 255,    255, 255, 255, 255,
        ]

        let image = GoDImage(width: 2, height: 2, pixels: GoDData(byteStream: pixels, byteOrder: .big))
        let pngData = image.pngData()

        XCTAssertNotNil(pngData)
        if let png = pngData {
            let sig = png.rawBytes.prefix(8)
            XCTAssertEqual(Array(sig), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }
    }

    func testRejectsWrongSize() {
        let image = GoDImage(width: 3, height: 3, pixels: GoDData(byteStream: [0, 0, 0, 255], byteOrder: .big))
        XCTAssertNil(image.pngData())
    }

    func testRoundTrip() {
        let pixels: [UInt8] = [
            255, 0, 0, 255,    0, 255, 0, 255,
            0, 0, 255, 255,    255, 255, 255, 255,
        ]

        let original = GoDImage(width: 2, height: 2, pixels: GoDData(byteStream: pixels, byteOrder: .big))
        guard let pngData = original.pngData() else { XCTFail("Encode failed"); return }
        guard let decoded = GoDImage.fromPNG(pngData) else { XCTFail("Decode failed"); return }

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.pixels.rawBytes, pixels)
    }
}
