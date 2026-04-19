import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class ATXFileTests: XCTestCase {

    /// Real absol.atx: 3 frames, 2 animations, all frames share the same
    /// anchor offsets. Filenames reflect the ATX name ("absol").
    func testAbsolATXRoundTripsViaOutputs() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let original = try ATXFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            name: "absol"
        )

        XCTAssertEqual(original.framePixels.count, 3)
        XCTAssertEqual(original.animations.count, 2)
        XCTAssertEqual(original.textureFormat, .C8)
        XCTAssertEqual(original.paletteFormat, .RGB5A3_3)

        // All frames share the same anchor — no per-frame overrides.
        XCTAssertEqual(original.xOffset, -31)
        XCTAssertEqual(original.yOffset, -64)
        XCTAssertTrue(original.frameOverrides.isEmpty)

        // First animation: single 10-tick step referencing absol_frame_000.png.
        XCTAssertEqual(original.animations[0].steps.count, 1)
        XCTAssertEqual(original.animations[0].steps[0].frame, File("absol_frame_000.png"))
        XCTAssertEqual(original.animations[0].steps[0].timing, 10)
        XCTAssertEqual(original.animations[0].steps[0].loopTarget, 0)

        // binary → outputs → binary → re-parse yields the same structure.
        let artifacts = try original.outputs
        let rebuilt = try ATXFile(outputs: artifacts).binaryData
        let reparsed = try ATXFile(binary: rebuilt, name: "absol")
        XCTAssertEqual(reparsed.framePixels.count, original.framePixels.count)
        XCTAssertEqual(reparsed.animations.count, original.animations.count)
    }

    /// Emitted outputs contain exactly the `<name>.atx.json` + N PNG
    /// frames, all in the same flat folder (no nested "textures/").
    func testOutputsShapeMatchesFrames() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let file = try ATXFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            name: "absol"
        )
        let artifacts = try file.outputs

        XCTAssertEqual(artifacts.count, 1 + file.framePixels.count,
                       "expected <name>.atx.json + N frame PNGs")
        XCTAssertNotNil(artifacts[File("absol.atx.json")])
        XCTAssertNotNil(artifacts[File("absol_frame_000.png")])
        XCTAssertNotNil(artifacts[File("absol_frame_001.png")])
        XCTAssertNotNil(artifacts[File("absol_frame_002.png")])
        // Flat layout — no nested directory components.
        for key in artifacts.keys {
            XCTAssertFalse(key.path.contains("/"),
                           "expected flat layout; got \(key.path)")
        }
    }

    /// airmd.atx has per-frame yOffset variation (frame 1 uses -63 while
    /// the others use -64). That surfaces as a `frameOverrides` entry.
    func testPerFrameOffsetOverride() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/airmd.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("airmd.atx not available")
        }
        let file = try ATXFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            name: "airmd"
        )
        XCTAssertEqual(file.xOffset, -32)
        XCTAssertEqual(file.yOffset, -64)
        // Frame 1 differs: yOffset = -63
        XCTAssertEqual(
            file.frameOverrides[File("airmd_frame_001.png")],
            ATXFile.FrameOverride(yOffset: -63)
        )
        XCTAssertEqual(file.frameOverrides.count, 1)
    }

    /// init(outputs:) recovers the base name from the JSON filename.
    func testInitOutputsRecoversName() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let original = try ATXFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            name: "absol"
        )
        let round = try ATXFile(outputs: try original.outputs)
        XCTAssertEqual(round.name, "absol")
    }
}
