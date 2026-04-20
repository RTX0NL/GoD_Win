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

    /// Helper: fetch the unique JSON artifact for a known format extension.
    private func jsonKey(in artifacts: [File: GoDData], ext: String) -> File? {
        artifacts.keys.first { $0.path.hasSuffix(".\(ext).json") }
    }

    /// Real .gsw sample roundtrips via the registry. Wrapper + non-texture
    /// bytes already roundtrip byte-identically through GSWParser; here we
    /// just verify the registry path emits the expected artifact set
    /// and that build → bytes succeeds.
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
        XCTAssertNotNil(jsonKey(in: artifacts, ext: "gsw"))
        let textureKeys = artifacts.keys.filter { $0.path.contains("_texture_") }
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
        XCTAssertEqual(artifacts.count, 2, "fnt emits json + pgm")
        XCTAssertNotNil(jsonKey(in: artifacts, ext: "fnt"))
        XCTAssertNotNil(artifacts.keys.first { $0.path.hasSuffix(".fnt.pgm") })

        let rebuilt = try handler.build(artifacts)
        XCTAssertEqual(rebuilt.rawBytes, [UInt8](raw))
    }

    /// Real XD .gtx sample roundtrips via the registry. The JSON
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
        XCTAssertEqual(artifacts.count, 2, "gtx emits json + png")
        let jKey = try XCTUnwrap(jsonKey(in: artifacts, ext: "gtx"))
        let pngKey = try XCTUnwrap(artifacts.keys.first { $0.path.hasSuffix(".gtx.png") })

        let json = try XCTUnwrap(artifacts[jKey])
        let dto = try JSONDecoder().decode(GTXFile.DTO.self, from: json.data)
        XCTAssertEqual(dto.pngPath, pngKey.path,
                       "JSON must self-reference its PNG sidecar")

        let rebuilt = try handler.build(artifacts)
        XCTAssertGreaterThan(rebuilt.length, 0)
    }

    /// A binary MSG routed through the registry dumps to a single JSON
    /// and rebuilds byte-identical.
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
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertNotNil(jsonKey(in: artifacts, ext: "msg"))

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
        XCTAssertTrue(written.first?.fileName.hasSuffix(".msg.json") ?? false,
                      "expected *.msg.json artifact")
        XCTAssertNotNil(fs.readFile(at: written.first!))

        let rebuilt = try registry.build(
            extension: "msg",
            from: folder,
            fileSystem: fs
        )
        XCTAssertEqual(rebuilt.rawBytes, raw)
    }

    /// Real .atx sample roundtrips via the registry.
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
        XCTAssertNotNil(jsonKey(in: artifacts, ext: "atx"))

        let pngKeys = artifacts.keys.filter { $0.path.hasSuffix(".png") }
        XCTAssertEqual(pngKeys.count, 3, "airmd.atx has 3 sprite frames")

        let rebuilt = try handler.build(artifacts)
        XCTAssertGreaterThan(rebuilt.length, 0)
        let reparsed = try ATXFile(binary: rebuilt)
        XCTAssertEqual(reparsed.framePixels.count, 3)
        XCTAssertEqual(reparsed.animations.count, 2)
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
