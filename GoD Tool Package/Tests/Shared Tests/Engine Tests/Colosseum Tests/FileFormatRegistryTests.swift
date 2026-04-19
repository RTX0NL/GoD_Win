import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class FileFormatRegistryTests: XCTestCase {

    func testBuiltinsRegistersKnownFormats() {
        let registry = FileFormatRegistry.builtins()
        XCTAssertTrue(registry.isRegistered("msg"))
        XCTAssertTrue(registry.isRegistered("MSG"))   // case-insensitive
        XCTAssertTrue(registry.isRegistered("fnt"))
        XCTAssertTrue(registry.isRegistered("gtx"))
        XCTAssertTrue(registry.isRegistered("gsw"))
        XCTAssertTrue(registry.isRegistered("atx"))
        XCTAssertFalse(registry.isRegistered("unknown"))
        XCTAssertNotNil(registry.handler(for: "msg"))
    }

    /// Real .gsw sample roundtrips via the registry. Wrapper + non-texture
    /// bytes already roundtrip byte-identically through GSWParser; here we
    /// just verify the registry path emits the expected artifact set
    /// (flashmenu.json + textures/*.png) and that build → bytes succeeds.
    func testRegistryGSWArtifactsAndRebuilds() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/battle_disk_ge/battle_disk_ge 0012.gsw"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("battle_disk_ge 0012.gsw not available")
        }

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "gsw"))

        let input = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertNotNil(artifacts[GSWFile.flashMenuJSON])
        let textureKeys = artifacts.keys.filter { $0.path.hasPrefix("textures/") }
        XCTAssertEqual(textureKeys.count, 1, "small sample has 1 embedded texture")

        let rebuilt = try handler.build(artifacts)
        XCTAssertGreaterThan(rebuilt.length, 0)
    }

    /// Real XD .fnt sample roundtrips through the registry. The decoded
    /// atlas+metadata rebuilds to byte-identical binary.
    func testRegistryGSFontDumpAndBuildRoundTrip() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.fnt"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pda_menu.fnt not available")
        }

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "fnt"))

        let input = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertEqual(Set(artifacts.keys), [GSFont.fontJSON, GSFont.atlasPGM])

        let rebuilt = try handler.build(artifacts)
        XCTAssertEqual(rebuilt.rawBytes, [UInt8](raw))
    }

    /// Real XD .gtx sample roundtrips via the registry. Pixel equality on
    /// decode-re-decode is asserted in GXTextureTests for every format; here
    /// we just verify the registry wires decode→encode correctly and emits
    /// both the texture.png and texture.json keys, and that the JSON
    /// self-references its PNG via `pngPath`.
    func testRegistryGTXArtifactsAndRebuilds() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/world_map/menu_038.gtx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("menu_038.gtx not available")
        }

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "gtx"))

        let input = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertEqual(Set(artifacts.keys), [GTXFile.texturePNG, GTXFile.textureJSON])

        let json = try XCTUnwrap(artifacts[GTXFile.textureJSON])
        let dto = try JSONDecoder().decode(GTXFile.DTO.self, from: json.data)
        XCTAssertEqual(dto.pngPath, GTXFile.texturePNG.path,
                       "JSON must self-reference its PNG sidecar")

        let rebuilt = try handler.build(artifacts)
        XCTAssertGreaterThan(rebuilt.length, 0)
    }

    /// A binary MSG routed through the registry dumps to messages.json and
    /// rebuilds byte-identical.
    func testRegistryMSGDumpAndBuildRoundTrip() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "msg"))

        let input = GoDData(byteStream: raw, byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertEqual(Set(artifacts.keys), [MSGFile.messagesJSON])

        let rebuilt = try handler.build(artifacts)
        XCTAssertEqual(rebuilt.rawBytes, raw)
    }

    /// End-to-end through the filesystem helpers: dump writes artifacts to
    /// disc, build reads them back into an identical binary.
    func testRegistryWritesAndReadsArtifactsViaFileSystem() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x02]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x01] + [0x00, 0x00, 0x00, 0x20]
        raw += [0x00, 0x00, 0x00, 0x02] + [0x00, 0x00, 0x00, 0x26]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]
        raw += [0x00, 0x59, 0x00, 0x6F, 0x00, 0x21, 0x00, 0x00]

        let fs = InMemoryFST()
        let folder = Folder("/work")
        _ = fs.createFolder(at: folder, overwrite: true)

        let registry = FileFormatRegistry.builtins()
        let input = GoDData(byteStream: raw, byteOrder: .big)

        let written = try registry.dump(
            bytes: input,
            extension: "msg",
            into: folder,
            fileSystem: fs,
            overwrite: true
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.fileName, MSGFile.messagesJSON.path)
        XCTAssertNotNil(fs.readFile(at: folder.file(MSGFile.messagesJSON.path)))

        let rebuilt = try registry.build(
            extension: "msg",
            from: folder,
            fileSystem: fs
        )
        XCTAssertEqual(rebuilt.rawBytes, raw)
    }

    /// Real .atx sample roundtrips via the registry. The wrapper + inner
    /// header are byte-identical; only the texture body re-quantizes (the
    /// same guarantee GXTextureTests already asserts at the decoder level).
    func testRegistryATXArtifactsAndRebuilds() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/airmd.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("airmd.atx not available")
        }

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "atx"))

        let input = GoDData(byteStream: [UInt8](raw), byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertEqual(Set(artifacts.keys), [ATXFile.animationPNG, ATXFile.animationJSON])

        let json = try XCTUnwrap(artifacts[ATXFile.animationJSON])
        let dto = try JSONDecoder().decode(ATXFile.DTO.self, from: json.data)
        XCTAssertEqual(dto.pngPath, ATXFile.animationPNG.path,
                       "JSON must self-reference its PNG sidecar")

        let rebuilt = try handler.build(artifacts)
        XCTAssertEqual(rebuilt.length, [UInt8](raw).count,
                       "ATX rebuild preserves total file size")
    }

    func testUnregisteredExtensionThrows() {
        let registry = FileFormatRegistry.builtins()
        let fs = InMemoryFST()
        _ = fs.createFolder(at: Folder("/x"), overwrite: true)

        XCTAssertThrowsError(
            try registry.dump(
                bytes: GoDData(byteStream: [0, 1, 2, 3], byteOrder: .big),
                extension: "bogus",
                into: Folder("/x"),
                fileSystem: fs
            )
        )
    }
}
