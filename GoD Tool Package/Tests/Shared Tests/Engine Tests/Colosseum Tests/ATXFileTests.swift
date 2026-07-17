import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX

/// Format-specific tests for ATXFile that go beyond the minimum 4-member
/// coverage in FileFormatProtocolTests — per-frame offset overrides,
/// frame PNG naming, animation step decoding.
final class ATXFileTests: XCTestCase {

    private var absolBytes: [UInt8]? {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](raw)
    }

    /// Animation 0 is a single 10-tick frame looping on frame 0.
    /// Animation 1 cycles through four 5-tick frames then loops to 0.
    /// Confirms the animation decoder resolves frameDelta → filename.
    func testATX_initBinary_resolvesAnimationStepsToFrameFilenames() throws {
        guard let raw = absolBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")

        XCTAssertEqual(atx.animations[0].steps,
                       [.init(timing: 10, frame: File("absol_frame_000.png"), loopTarget: 0)])
        XCTAssertEqual(atx.animations[1].steps.map(\.frame),
                       [File("absol_frame_000.png"),
                        File("absol_frame_001.png"),
                        File("absol_frame_002.png"),
                        File("absol_frame_001.png")])
        XCTAssertEqual(atx.animations[1].steps.last?.loopTarget, 0)
    }

    /// airmd.atx has per-frame yOffset variation — frame 1 anchors at
    /// yOffset = -63 while frames 0 and 2 use -64. Verifies that
    /// init(binary:) surfaces the difference as a `frameOverrides` entry.
    func testATX_initBinary_capturesPerFrameOffsetOverrides() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/airmd.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("airmd.atx not available")
        }
        let atx = try ATXFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
                              name: "airmd")
        XCTAssertEqual(atx.xOffset, -32)
        XCTAssertEqual(atx.yOffset, -64)
        XCTAssertEqual(atx.frameOverrides.count, 1)
        XCTAssertEqual(atx.frameOverrides[File("airmd_frame_001.png")],
                       ATXFile.FrameOverride(yOffset: -63))
    }

    /// framePNGName() produces the expected zero-padded filename.
    func testATX_framePNGName_producesZeroPaddedFilename() {
        var atx = ATXFile(
            textureFormat: .C8,
            paletteFormat: .RGB5A3,
            xOffset: 0,
            yOffset: 0,
            framePixels: [],
            animations: []
        )
        atx.name = "foo"
        XCTAssertEqual(atx.framePNGName(index: 0), File("foo_frame_000.png"))
        XCTAssertEqual(atx.framePNGName(index: 7), File("foo_frame_007.png"))
        XCTAssertEqual(atx.framePNGName(index: 142), File("foo_frame_142.png"))
    }

    /// Missing frame PNG referenced by an animation step surfaces at
    /// binaryData time with a helpful error.
    func testATX_binaryData_withMissingReferencedFrame_throws() throws {
        guard let raw = absolBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")
        let frameToRemove = atx.framePNGName(index: 1)
        let outputs = try atx.outputs.filter { $0.file != frameToRemove }
        // Missing frame now surfaces at init(outputs:) time because the
        // JSON's `framePaths` list drives the lookup and the missing PNG
        // is reported up-front.
        XCTAssertThrowsError(try ATXFile(outputs: outputs)) { error in
            XCTAssertTrue("\(error)".contains("frame_001.png") || "\(error)".contains("unknown frame"))
        }
    }
}
