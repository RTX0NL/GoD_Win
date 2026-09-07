import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX

/// One test per protocol member per format. Each asserts a single step:
///
///   init(binary:)    — given specific bytes, construct a value with
///                      specific expected properties.
///   binaryData       — given specific properties, produce bytes whose
///                      values at specific offsets match expectations.
///   init(outputs:)   — given specific output artifacts, construct a
///                      value with specific expected properties.
///   outputs          — given specific properties, produce the expected
///                      artifact set (keys + spot-checked contents).
///
/// Roundtrip (binary → outputs → binary) tests are intentionally avoided
/// — each test targets exactly one of the four members so a failure
/// points at the member at fault.
final class FileFormatProtocolTests: XCTestCase {

    // MARK: - Registry mechanics

    func testBuiltinsRegistersEveryKnownFormat() {
        let registry = FileFormatRegistry.builtins()
        XCTAssertTrue(registry.isRegistered("msg"))
        XCTAssertTrue(registry.isRegistered("MSG"))   // case-insensitive
        XCTAssertTrue(registry.isRegistered("fnt"))
        XCTAssertTrue(registry.isRegistered("gtx"))
        XCTAssertTrue(registry.isRegistered("gsw"))
        XCTAssertTrue(registry.isRegistered("atx"))
        XCTAssertFalse(registry.isRegistered("unknown"))
    }

    func testRegistryHandlerFormatTypeIsRecorded() {
        let registry = FileFormatRegistry.builtins()
        XCTAssertTrue(registry.handler(for: "msg")?.formatType == MSGFile.self)
        XCTAssertTrue(registry.handler(for: "fnt")?.formatType == GSFont.self)
        XCTAssertTrue(registry.handler(for: "gtx")?.formatType == GTXFile.self)
        XCTAssertTrue(registry.handler(for: "atx")?.formatType == ATXFile.self)
        XCTAssertTrue(registry.handler(for: "gsw")?.formatType == GSWFile.self)
    }

    func testRegistryReregisterExtensionOverwrites() {
        var registry = FileFormatRegistry()
        registry.register("msg", MSGFile.self)
        XCTAssertNotNil(registry.handler(for: "msg"))
        registry.register("msg", MSGFile.self)
        XCTAssertTrue(registry.handler(for: "msg")?.formatType == MSGFile.self)
    }

    func testRegistryNoArtifactsFoundThrows() {
        let fs = InMemoryFST()
        let folder = Folder("/empty")
        try? fs.createFolder(at: folder, overwrite: true)
        XCTAssertThrowsError(try FileFormatRegistry.builtins().build(
            extension: "msg", from: folder, fileSystem: fs
        ))
    }

    // MARK: - MSGFile

    /// Builds the 16-byte header + 1-entry table + "Hi\0" string for a
    /// minimal valid MSG file.
    private static func minimalMSGBytes() -> [UInt8] {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]                  // reservedPrefix
        raw += [0x00, 0x01]                              // entry count = 1
        raw += [0x55, 0x53]                              // region "US"
        raw += [UInt8](repeating: 0, count: 8)           // reservedSuffix
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]  // id=5, off=0x18
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]      // "Hi\0"
        return raw
    }

    func testMSG_initBinary_parsesHeaderAndEntries() throws {
        let bytes = Self.minimalMSGBytes()
        let parsed = try MSGFile(binary: GoDData(byteStream: bytes, byteOrder: .big), variant: .xd)
        XCTAssertEqual(parsed.variant, .xd)
        XCTAssertEqual(parsed.reservedPrefix, [0, 0, 0, 0])
        XCTAssertEqual(parsed.region, [0x55, 0x53])
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries[0].id, 5)
        XCTAssertEqual(parsed.entries[0].string.string(format: .gsXD), "Hi")
    }

    func testMSG_binaryData_producesExpectedHeaderAndPayload() throws {
        let msg = MSGFile(
            variant: .xd,
            region: [0x55, 0x53],
            entries: [.init(id: 5, string: GSString(string: "Hi", format: .gsXD))]
        )
        let bytes = try msg.binaryData.rawBytes

        // Header
        XCTAssertEqual(bytes[0x04], 0x00); XCTAssertEqual(bytes[0x05], 0x01)  // count = 1
        XCTAssertEqual(Array(bytes[0x06..<0x08]), [0x55, 0x53])               // region
        // Entry table at 0x10: id (4) + offset (4)
        XCTAssertEqual(Array(bytes[0x10..<0x14]), [0x00, 0x00, 0x00, 0x05])
        XCTAssertEqual(Array(bytes[0x14..<0x18]), [0x00, 0x00, 0x00, 0x18])
        // String pool at 0x18: UTF-16 BE "Hi\0"
        XCTAssertEqual(Array(bytes[0x18..<0x1E]), [0x00, 0x48, 0x00, 0x69, 0x00, 0x00])
    }

    func testMSG_initOutputs_parsesJSONIntoEntries() throws {
        let json = """
        {
          "entries": [
            { "id": 7, "text": "Hello" }
          ],
          "region": "US",
          "reservedPrefix": "00000000",
          "reservedSuffix": "0000000000000000",
          "variant": "xd"
        }
        """.data(using: .utf8)!
        let outputs: [FileData] = [
            FileData(file: File("sample.msg.json"), data: GoDData(data: json, byteOrder: .big))
        ]
        let parsed = try MSGFile(outputs: outputs)
        XCTAssertEqual(parsed.name, "sample")
        XCTAssertEqual(parsed.variant, .xd)
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries[0].id, 7)
        XCTAssertEqual(parsed.entries[0].string.string(format: .gsXD), "Hello")
    }

    func testMSG_outputs_producesSingleJSONArtifact() throws {
        var msg = MSGFile(
            variant: .xd,
            entries: [.init(id: 7, string: GSString(string: "Hello", format: .gsXD))]
        )
        msg.name = "sample"
        let artifacts = try msg.outputs

        XCTAssertEqual(artifacts.count, 1, "MSG emits a single JSON artifact")
        let byFile = artifacts.byFile
        let jsonKey = File("sample.msg.json")
        XCTAssertNotNil(byFile[jsonKey])
        let text = String(data: byFile[jsonKey]!.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"id\" : 7"), "JSON should mention id 7")
        XCTAssertTrue(text.contains("\"text\" : \"Hello\""),
                      "JSON should include the pretty-printed entry text")
    }

    // MARK: - GSFont

    private var realFontBytes: [UInt8]? {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.fnt"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](raw)
    }

    func testGSFont_initBinary_parsesPrimaryBlock() throws {
        guard let raw = realFontBytes else { throw XCTSkip("pda_menu.fnt not available") }
        let font = try GSFont(binary: GoDData(byteStream: raw, byteOrder: .big))
        XCTAssertEqual(font.fontId, 0, "primary block has fontId 0")
        XCTAssertGreaterThan(font.glyphWidth, 0)
        XCTAssertGreaterThan(font.glyphHeight, 0)
        XCTAssertFalse(font.glyphs.isEmpty, "primary block should parse at least one glyph")
    }

    func testGSFont_binaryData_startsWithExpectedHeaderFields() throws {
        guard let raw = realFontBytes else { throw XCTSkip("pda_menu.fnt not available") }
        let font = try GSFont(binary: GoDData(byteStream: raw, byteOrder: .big))
        let bytes = try font.binaryData.rawBytes
        // Header: fontId (u16), glyphWidth (u8), glyphHeight (u8)
        XCTAssertEqual(UInt16(bytes[0]) << 8 | UInt16(bytes[1]), font.fontId)
        XCTAssertEqual(bytes[2], UInt8(font.glyphWidth))
        XCTAssertEqual(bytes[3], UInt8(font.glyphHeight))
    }

    func testGSFont_initOutputs_parsesAtlasAndMetadata() throws {
        guard let raw = realFontBytes else { throw XCTSkip("pda_menu.fnt not available") }
        var font = try GSFont(binary: GoDData(byteStream: raw, byteOrder: .big))
        font.name = "pda_menu"
        let artifacts = try font.outputs    // use these as fixed input

        let parsed = try GSFont(outputs: artifacts)
        XCTAssertEqual(parsed.name, "pda_menu")
        XCTAssertEqual(parsed.fontId, font.fontId)
        XCTAssertEqual(parsed.glyphWidth, font.glyphWidth)
        XCTAssertEqual(parsed.glyphHeight, font.glyphHeight)
        XCTAssertEqual(parsed.glyphs.count, font.glyphs.count)
    }

    func testGSFont_outputs_emitsJSONAndGreyscalePNGUnderName() throws {
        guard let raw = realFontBytes else { throw XCTSkip("pda_menu.fnt not available") }
        var font = try GSFont(binary: GoDData(byteStream: raw, byteOrder: .big))
        font.name = "pda_menu"
        let artifacts = try font.outputs

        XCTAssertEqual(artifacts.count, 2)
        let byFile = artifacts.byFile
        XCTAssertNotNil(byFile[File("pda_menu.fnt.json")])
        let atlas = try XCTUnwrap(byFile[File("pda_menu.fnt.png")])
        // The atlas is a greyscale PNG. It was a binary PGM, which opens
        // nowhere on Windows without extra software and is an order of
        // magnitude larger for a sheet that is mostly empty.
        let bytes = atlas.rawBytes
        XCTAssertEqual(Array(bytes[0..<8]), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR colour type at +25: 0 = greyscale, 8 bits per sample at +24.
        XCTAssertEqual(bytes[25], 0, "intensity-only data should not be stored as RGB/RGBA")
        XCTAssertEqual(bytes[24], 8)
    }

    // MARK: - GTXFile

    private func makeKnownGTX() -> GTXFile {
        // A 4×4 RGBA32 with every pixel set to (0xFF, 0xAA, 0x55, 0xFF).
        let rgba: [UInt8] = (0..<16).flatMap { _ in [0xFF, 0xAA, 0x55, 0xFF] }
        return GTXFile(
            image: GoDImage(
                width: 4, height: 4,
                pixels: GoDData(byteStream: rgba, byteOrder: .big)
            ),
            format: .RGBA32,
            paletteFormat: nil,
            name: "sample"
        )
    }

    func testGTX_initBinary_parsesDimensionsAndFormat() throws {
        let bytes = try makeKnownGTX().binaryData
        let parsed = try GTXFile(binary: bytes)
        XCTAssertEqual(parsed.image.width, 4)
        XCTAssertEqual(parsed.image.height, 4)
        XCTAssertEqual(parsed.format, .RGBA32)
        XCTAssertNil(parsed.paletteFormat)
    }

    func testGTX_binaryData_writesKnownHeaderBytes() throws {
        let bytes = try makeKnownGTX().binaryData.rawBytes
        // Header layout: width u16 BE @ 0x00, height u16 BE @ 0x02,
        // bpp u8 @ 0x04, format u8 @ 0x0B, texture pointer u32 BE @ 0x28.
        XCTAssertEqual(UInt16(bytes[0]) << 8 | UInt16(bytes[1]), 4)
        XCTAssertEqual(UInt16(bytes[2]) << 8 | UInt16(bytes[3]), 4)
        XCTAssertEqual(bytes[4], 32)          // RGBA32 bitsPerPixel
        XCTAssertEqual(bytes[0x0B], UInt8(GXTextureFormat.RGBA32.rawValue))
        XCTAssertEqual(bytes[0x2B], 0x80)     // texture data begins at 0x80
    }

    func testGTX_initOutputs_readsPNGReferencedByJSON() throws {
        let gtx = makeKnownGTX()
        let artifacts = try gtx.outputs

        let parsed = try GTXFile(outputs: artifacts)
        XCTAssertEqual(parsed.name, "sample")
        XCTAssertEqual(parsed.image.width, 4)
        XCTAssertEqual(parsed.image.height, 4)
        XCTAssertEqual(parsed.format, .RGBA32)
    }

    func testGTX_outputs_emitsNamedJSONAndPNG() throws {
        let artifacts = try makeKnownGTX().outputs
        XCTAssertEqual(artifacts.count, 2)
        let byFile = artifacts.byFile
        XCTAssertNotNil(byFile[File("sample.gtx.json")])
        XCTAssertNotNil(byFile[File("sample.gtx.png")])

        // JSON's pngPath field should point at the sidecar by name; format
        // is present but width/height are derivable from the PNG and NOT
        // stored in the DTO.
        let json = byFile[File("sample.gtx.json")]!
        let dto = try JSONDecoder().decode(GTXFile.DTO.self, from: json.data)
        XCTAssertEqual(dto.pngPath, "sample.gtx.png")
        XCTAssertEqual(dto.format, .RGBA32)
        XCTAssertNil(dto.paletteFormat)
    }

    // MARK: - ATXFile

    private var realATXBytes: [UInt8]? {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/poke_dance/absol.atx"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](raw)
    }

    func testATX_initBinary_parsesFramesAndAnimations() throws {
        guard let raw = realATXBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")
        XCTAssertEqual(atx.name, "absol")
        XCTAssertEqual(atx.textureFormat, .C8)
        XCTAssertEqual(atx.paletteFormat, .RGB5A3_3)
        XCTAssertEqual(atx.framePixels.count, 3)
        XCTAssertEqual(atx.animations.count, 2)
        XCTAssertEqual(atx.xOffset, -31)
        XCTAssertEqual(atx.yOffset, -64)
        XCTAssertTrue(atx.frameOverrides.isEmpty, "absol uses the same anchor on every frame")
    }

    func testATX_binaryData_writesWrapperHeader() throws {
        guard let raw = realATXBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")
        let bytes = try atx.binaryData.rawBytes

        // Header: animationCount u32 BE @ 0x00.
        let animCount = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                      | UInt32(bytes[2]) << 8  | UInt32(bytes[3])
        XCTAssertEqual(animCount, 2)

        // Header: innerTextureOffset u32 BE @ 0x0C must land on the inner
        // GTX's `W\x00H...` header.
        let innerOff = Int(UInt32(bytes[0x0C]) << 24 | UInt32(bytes[0x0D]) << 16
                         | UInt32(bytes[0x0E]) << 8  | UInt32(bytes[0x0F]))
        // Inner header at offset 0x0B is the texture format (C8).
        XCTAssertEqual(bytes[innerOff + 0x0B], UInt8(GXTextureFormat.C8.rawValue))
    }

    func testATX_initOutputs_recoversNameAndAnimations() throws {
        guard let raw = realATXBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")
        let artifacts = try atx.outputs
        let parsed = try ATXFile(outputs: artifacts)
        XCTAssertEqual(parsed.name, "absol")
        XCTAssertEqual(parsed.framePixels.count, 3)
        XCTAssertEqual(parsed.animations.count, 2)
        XCTAssertEqual(parsed.animations[0].steps.first?.frame, File("absol_frame_000.png"))
    }

    func testATX_outputs_emitsNamedJSONAndFramePNGs() throws {
        guard let raw = realATXBytes else { throw XCTSkip("absol.atx not available") }
        let atx = try ATXFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "absol")
        let artifacts = try atx.outputs

        XCTAssertEqual(artifacts.count, 1 + atx.framePixels.count)
        let byFile = artifacts.byFile
        XCTAssertNotNil(byFile[File("absol.atx.json")])
        XCTAssertNotNil(byFile[File("absol_frame_000.png")])
        XCTAssertNotNil(byFile[File("absol_frame_001.png")])
        XCTAssertNotNil(byFile[File("absol_frame_002.png")])

        // Flat layout — no keys should contain a "/".
        for artifact in artifacts {
            XCTAssertFalse(artifact.file.path.contains("/"),
                           "expected flat layout; got \(artifact.file.path)")
        }
    }

    // MARK: - GSWFile

    private var realGSWBytes: [UInt8]? {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/battle_disk_ge/battle_disk_ge 0012.gsw"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](raw)
    }

    func testGSW_initBinary_parsesHeaderAndTagCount() throws {
        guard let raw = realGSWBytes else { throw XCTSkip("GSW sample not available") }
        let gsw = try GSWFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "flash")
        XCTAssertEqual(gsw.name, "flash")
        XCTAssertEqual(gsw.header.version, 7, "XD GSWs are always version 7")
        XCTAssertEqual(gsw.header.frameRate, 0x3200)
        XCTAssertFalse(gsw.tags.isEmpty)
        XCTAssertEqual(gsw.images.count, gsw.allTextureRefs.count,
                       "decoded images should be parallel to texture refs")
    }

    func testGSW_binaryData_startsWithHeaderVersionSeven() throws {
        guard let raw = realGSWBytes else { throw XCTSkip("GSW sample not available") }
        let gsw = try GSWFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "flash")
        let bytes = try gsw.binaryData.rawBytes

        // GSW header's first u32 BE is the version field = 0x00000007.
        XCTAssertEqual(Array(bytes[0..<4]), [0x00, 0x00, 0x00, 0x07])
        XCTAssertGreaterThan(bytes.count, 0x30, "header is 0x30 bytes")
    }

    func testGSW_initOutputs_rebuildsFromNamedArtifacts() throws {
        guard let raw = realGSWBytes else { throw XCTSkip("GSW sample not available") }
        let gsw = try GSWFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "flash")
        let artifacts = try gsw.outputs
        let parsed = try GSWFile(outputs: artifacts)
        XCTAssertEqual(parsed.name, "flash")
        XCTAssertEqual(parsed.tags.count, gsw.tags.count)
        XCTAssertEqual(parsed.images.count, gsw.images.count)
    }

    func testGSW_outputs_emitsJSONAndFlatTexturePNGs() throws {
        guard let raw = realGSWBytes else { throw XCTSkip("GSW sample not available") }
        let gsw = try GSWFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "flash")
        let artifacts = try gsw.outputs

        let byFile = artifacts.byFile
        XCTAssertNotNil(byFile[File("flash.gsw.json")])
        let textureKeys = byFile.keys.filter { $0.path.hasPrefix("flash_texture_") }
        XCTAssertEqual(textureKeys.count, gsw.allTextureRefs.count)
        // Flat layout — no "textures/" prefix on any key.
        for artifact in artifacts {
            XCTAssertFalse(artifact.file.path.contains("/"),
                           "expected flat layout; got \(artifact.file.path)")
        }
    }
}
