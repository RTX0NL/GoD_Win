//
//  PNGDeflateTruncationTests.swift
//
//  Regression guard for the DEFLATE final-flush bug patched in the vendored
//  swift-png (`Third Party/swift-png/README.md`).
//
//  Upstream chose the final block type from the leftover input count alone, so
//  when the matcher stopped with 0-2 bytes still queued it emitted a stored
//  block for those and discarded every term still in the match buffer. The
//  stream stayed structurally valid and kept the Adler-32 of the whole input,
//  so the only symptom was that it failed its own checksum on read.
//
//  These three images are the real ones it was found on, carried as raw pixels
//  because the trigger depends on the exact content — no shorter crop of any of
//  them reproduces it. Their failing levels are disjoint ({0,1,2,3}, {0,1},
//  {5,6,7}), which is what showed the level was never the cause.
//

import XCTest
import GoDFoundation
import TestSupport

final class PNGDeflateTruncationTests: XCTestCase {

    /// A GS flash menu texture from XD PAL (`title_fr_010`, texture 40).
    /// Unpatched at level 0 this encoded to 69 bytes whose deflate stream held
    /// a single byte of the 35,872 it should carry.
    func testColorImageThatUsedToTruncate() throws {
        let pixels = try Fixtures.data("png_truncation_rgba8_280x32.bin")
        let image = GoDImage(width: 280, height: 32, pixels: pixels)

        guard let png = image.pngData() else {
            XCTFail("encode returned nil")
            return
        }
        guard let decoded = GoDImage.fromPNG(png) else {
            XCTFail("encoded PNG could not be read back — deflate stream truncated")
            return
        }

        XCTAssertEqual(decoded.width, 280)
        XCTAssertEqual(decoded.height, 32)
        XCTAssertEqual(decoded.pixels.rawBytes, pixels.rawBytes)
    }

    /// A Colosseum JP font atlas (`D2_magma_3_005`). Unpatched at level 0 the
    /// final flush arrived with one byte left, discarding 3,013 bytes of terms.
    func testGreyscaleImageThatUsedToTruncateAtLevelZero() throws {
        try assertGreyscaleRoundTrips("png_truncation_v8_768x80.bin", width: 768, height: 80)
    }

    /// `D4_dome_4`, the atlas the old retry ladder was written for. It failed
    /// at levels 5-7 and not at 0, so it guards the level we ship changing.
    func testGreyscaleImageThatUsedToTruncateAtLevelSix() throws {
        try assertGreyscaleRoundTrips("png_truncation_v8_528x40.bin", width: 528, height: 40)
    }

    private func assertGreyscaleRoundTrips(
        _ fixture: String,
        width: Int,
        height: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pixels = try Fixtures.data(fixture).rawBytes
        let image = GreyscaleImage(width: width, height: height, pixels: pixels)

        guard let png = image.pngData() else {
            XCTFail("encode returned nil", file: file, line: line)
            return
        }
        guard let decoded = GreyscaleImage.fromPNG(png) else {
            XCTFail(
                "encoded PNG could not be read back — deflate stream truncated",
                file: file, line: line
            )
            return
        }

        XCTAssertEqual(decoded.width, width, file: file, line: line)
        XCTAssertEqual(decoded.height, height, file: file, line: line)
        XCTAssertEqual(decoded.pixels, pixels, file: file, line: line)
    }
}
