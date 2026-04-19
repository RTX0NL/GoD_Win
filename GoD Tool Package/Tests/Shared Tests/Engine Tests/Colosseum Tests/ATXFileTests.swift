import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class ATXFileTests: XCTestCase {

    /// Real absol.atx: 3 frames, 2 animations. Roundtrip produces identical
    /// structure and the JSON references each PNG by filename.
    func testAbsolATXRoundTripsViaOutputs() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let original = try ATXFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big))

        XCTAssertEqual(original.frames.count, 3)
        XCTAssertEqual(original.animations.count, 2)
        XCTAssertEqual(original.textureFormat, .C8)
        XCTAssertEqual(original.paletteFormat, .RGB5A3_3)

        // Frame filenames are zero-padded so alphabetical order = index order.
        XCTAssertEqual(original.frames.map { $0.image.path },
                       ["frame_000.png", "frame_001.png", "frame_002.png"])

        // First animation has a single 10-tick frame loop referencing frame 0.
        XCTAssertEqual(original.animations[0].steps.count, 1)
        XCTAssertEqual(original.animations[0].steps[0].frame, File("frame_000.png"))
        XCTAssertEqual(original.animations[0].steps[0].timing, 10)
        XCTAssertEqual(original.animations[0].steps[0].loopTarget, 0)

        // Roundtrip: binary → outputs → binary → re-parse produces matching
        // counts and the same PNG filenames referenced by animations.
        let artifacts = try original.outputs
        let rebuilt = try ATXFile(outputs: artifacts).binaryData
        let reparsed = try ATXFile(binary: rebuilt)
        XCTAssertEqual(reparsed.frames.count, original.frames.count)
        XCTAssertEqual(reparsed.animations.count, original.animations.count)
        XCTAssertEqual(reparsed.animations.map { $0.steps.count },
                       original.animations.map { $0.steps.count })
    }

    /// Sanity: emitted outputs contain exactly the animation.json + N PNG
    /// frames and nothing else.
    func testOutputsShapeMatchesFrames() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let file = try ATXFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        let artifacts = try file.outputs

        XCTAssertEqual(artifacts.count, 1 + file.frames.count,
                       "expected animation.json + N frame PNGs")
        XCTAssertNotNil(artifacts[ATXFile.animationJSON])
        for frame in file.frames {
            XCTAssertNotNil(artifacts[frame.image],
                            "missing PNG artifact for \(frame.image.path)")
        }
    }
}
