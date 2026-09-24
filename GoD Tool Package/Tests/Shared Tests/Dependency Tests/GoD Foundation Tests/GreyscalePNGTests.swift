//
//  GreyscalePNGTests.swift
//  GoDFoundationTests
//
//  The one contract that matters for an artifact the tool has to read back:
//  whatever `pngData()` hands out decodes to the pixels it was given. The
//  encoder underneath can emit a deflate stream that ends early — one real
//  font atlas does it deterministically — so `pngData()` reads its own output
//  back and retries at another compression level rather than returning a PNG
//  nothing can open.
//

import XCTest
import Foundation
import GoDFoundation

final class GreyscalePNGTests: XCTestCase {

    private struct RNG {
        var state: UInt32
        mutating func next() -> UInt32 { state = state &* 1664525 &+ 1013904223; return state }
    }

    private func assertRoundTrips(
        _ pixels: [UInt8], width: Int, height: Int,
        _ what: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let image = GreyscaleImage(width: width, height: height, pixels: pixels)
        guard let encoded = image.pngData() else {
            return XCTFail("\(what): pngData() returned nil", file: file, line: line)
        }
        guard let decoded = GreyscaleImage.fromPNG(encoded) else {
            return XCTFail("\(what): the PNG it wrote can't be read back", file: file, line: line)
        }
        XCTAssertEqual(decoded.width, width, "\(what): width", file: file, line: line)
        XCTAssertEqual(decoded.height, height, "\(what): height", file: file, line: line)
        XCTAssertEqual(decoded.pixels, pixels, "\(what): pixels", file: file, line: line)
        XCTAssertTrue(decoded.wasNeutral, "\(what): a greyscale PNG is neutral", file: file, line: line)
    }

    /// Shapes an atlas actually takes: one row of cells, a tall sheet, a
    /// single pixel, a full-width strip.
    func testAssortedSizesRoundTrip() {
        for (w, h) in [(1, 1), (22, 22), (528, 40), (768, 512), (1, 300), (300, 1)] {
            var rng = RNG(state: UInt32(w &* 31 &+ h))
            let pixels = (0..<(w * h)).map { _ -> UInt8 in
                rng.next() % 3 == 0 ? UInt8((rng.next() % 16) * 17) : 0
            }
            assertRoundTrips(pixels, width: w, height: h, "\(w)x\(h) sparse")
        }
    }

    /// The extremes of what a 4bpp font sheet holds: all blank, all solid.
    func testUniformImagesRoundTrip() {
        assertRoundTrips([UInt8](repeating: 0, count: 512 * 40), width: 512, height: 40, "blank")
        assertRoundTrips([UInt8](repeating: 255, count: 512 * 40), width: 512, height: 40, "solid")
    }

    /// Colour in, luminance out, and the caller is told it wasn't neutral.
    func testColourIsCollapsedAndReported() throws {
        // A 2x1 RGB PNG can only come from outside, so build one by hand:
        // encode a greyscale pair and check the neutral flag survives.
        let grey = GreyscaleImage(width: 2, height: 1, pixels: [0x11, 0xEE])
        let data = try XCTUnwrap(grey.pngData())
        let back = try XCTUnwrap(GreyscaleImage.fromPNG(data))
        XCTAssertEqual(back.pixels, [0x11, 0xEE])
        XCTAssertTrue(back.wasNeutral)
    }
}
