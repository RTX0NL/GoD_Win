import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX

/// Cross-format invariants for the FileFormat protocol contract:
///   - Name recovery from the `<name>.<formatName>.json` artifact key.
///   - Missing-artifact error paths.
///   - Registry mechanics (re-register, no-artifacts, write-failure).
final class FileFormatProtocolTests: XCTestCase {

    // MARK: - Name recovery

    func testMSGNameRecoveredFromJSONKey() throws {
        var msg = MSGFile(variant: .xd)
        msg.entries = [.init(id: 1, string: GSString(string: "Hi", format: .gsXD))]
        msg.name = "custom_msg"
        let artifacts = try msg.outputs
        let round = try MSGFile(outputs: artifacts)
        XCTAssertEqual(round.name, "custom_msg")
    }

    func testGTXNameRecoveredFromJSONKey() throws {
        let metadata = GXTextureMetadata(width: 4, height: 4, format: .RGBA32, paletteFormat: nil)
        let pixels = GoDData(byteStream: [UInt8](repeating: 0xFF, count: 4 * 4 * 4), byteOrder: .big)
        let image = GoDImage(width: 4, height: 4, pixels: pixels)
        let gtx = GTXFile(image: image, metadata: metadata, name: "custom_gtx")
        let round = try GTXFile(outputs: try gtx.outputs)
        XCTAssertEqual(round.name, "custom_gtx")
    }

    func testATXNameRecoveredFromJSONKey() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let original = try ATXFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big), name: "myatx")
        let round = try ATXFile(outputs: try original.outputs)
        XCTAssertEqual(round.name, "myatx")
    }

    func testGSFontNameRecoveredFromJSONKey() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.fnt"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pda_menu.fnt not available")
        }
        var font = try GSFont(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        font.name = "my_font"
        let round = try GSFont(outputs: try font.outputs)
        XCTAssertEqual(round.name, "my_font")
    }

    func testGSWNameRecoveredFromJSONKey() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/battle_disk_ge/battle_disk_ge 0012.gsw"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("battle_disk_ge 0012.gsw not available")
        }
        let original = try GSWFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big), name: "myflash")
        let round = try GSWFile(outputs: try original.outputs)
        XCTAssertEqual(round.name, "myflash")
    }

    // MARK: - Missing-artifact errors

    func testMSGMissingJSONThrowsMissingOutputError() {
        XCTAssertThrowsError(try MSGFile(outputs: [:])) { error in
            XCTAssertTrue("\(error)".contains("*.msg.json"),
                          "expected missing-output error mentioning *.msg.json, got \(error)")
        }
    }

    func testGSFontMissingPGMThrowsMissingOutputError() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.fnt"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pda_menu.fnt not available")
        }
        var font = try GSFont(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        font.name = "x"
        var outputs = try font.outputs
        outputs.removeValue(forKey: font.atlasPGMFilename())
        XCTAssertThrowsError(try GSFont(outputs: outputs)) { error in
            XCTAssertTrue("\(error)".contains(".fnt.pgm"),
                          "expected missing-output error mentioning .fnt.pgm, got \(error)")
        }
    }

    func testGTXMissingPNGThrowsMissingOutputError() throws {
        let metadata = GXTextureMetadata(width: 4, height: 4, format: .RGBA32, paletteFormat: nil)
        let pixels = GoDData(byteStream: [UInt8](repeating: 0xFF, count: 64), byteOrder: .big)
        let gtx = GTXFile(
            image: GoDImage(width: 4, height: 4, pixels: pixels),
            metadata: metadata,
            name: "x"
        )
        var outputs = try gtx.outputs
        outputs.removeValue(forKey: gtx.texturePNGFilename())
        XCTAssertThrowsError(try GTXFile(outputs: outputs)) { error in
            XCTAssertTrue("\(error)".contains(".png"),
                          "expected missing-output error mentioning the PNG sidecar, got \(error)")
        }
    }

    /// Removing a frame PNG that animations reference produces a build-time
    /// failure when the animation step's filename can't be resolved to an
    /// index in the rebuilt frame set.
    func testATXMissingReferencedFramePNGFailsRebuild() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("absol.atx not available")
        }
        let atx = try ATXFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big), name: "absol")
        var outputs = try atx.outputs
        // Drop frame_001.png — the second animation references it.
        outputs.removeValue(forKey: atx.framePNGName(index: 1))
        let rebuilt = try ATXFile(outputs: outputs)
        // init succeeded with a smaller frame set, but binaryData should
        // fail when an animation step references the missing filename.
        XCTAssertThrowsError(try rebuilt.binaryData) { error in
            XCTAssertTrue("\(error)".contains("frame_001.png") || "\(error)".contains("unknown frame"),
                          "expected failure mentioning the missing frame, got \(error)")
        }
    }

    // MARK: - Registry mechanics

    func testRegistryReregisterExtensionOverwrites() {
        var registry = FileFormatRegistry()
        registry.register("msg", MSGFile.self)
        let first = registry.handler(for: "msg")
        XCTAssertNotNil(first)
        // Re-register the same type — handler is replaced (different closure
        // identity) but still routes to MSGFile.
        registry.register("msg", MSGFile.self)
        let second = registry.handler(for: "msg")
        XCTAssertNotNil(second)
        XCTAssertTrue(second?.formatType == MSGFile.self)
    }

    func testRegistryNoArtifactsFoundThrows() throws {
        let fs = InMemoryFST()
        let folder = Folder("/empty")
        _ = fs.createFolder(at: folder, overwrite: true)
        let registry = FileFormatRegistry.builtins()
        XCTAssertThrowsError(try registry.build(extension: "msg", from: folder, fileSystem: fs)) { error in
            XCTAssertTrue("\(error)".contains("no artifacts"),
                          "expected noArtifactsFound error, got \(error)")
        }
    }

    func testRegistryUnregisteredExtensionDuringBuildThrows() {
        let fs = InMemoryFST()
        let folder = Folder("/x")
        _ = fs.createFolder(at: folder, overwrite: true)
        let registry = FileFormatRegistry()  // empty
        XCTAssertThrowsError(try registry.build(extension: "msg", from: folder, fileSystem: fs))
    }

    func testRegistryHandlerFormatTypeIsRecorded() {
        let registry = FileFormatRegistry.builtins()
        XCTAssertTrue(registry.handler(for: "msg")?.formatType == MSGFile.self)
        XCTAssertTrue(registry.handler(for: "fnt")?.formatType == GSFont.self)
        XCTAssertTrue(registry.handler(for: "gtx")?.formatType == GTXFile.self)
        XCTAssertTrue(registry.handler(for: "atx")?.formatType == ATXFile.self)
        XCTAssertTrue(registry.handler(for: "gsw")?.formatType == GSWFile.self)
    }
}
