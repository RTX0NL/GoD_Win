import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class FileFormatRegistryTests: XCTestCase {

    func testBuiltinsRegistersMSG() {
        let registry = FileFormatRegistry.builtins()
        XCTAssertTrue(registry.isRegistered("msg"))
        XCTAssertTrue(registry.isRegistered("MSG"))   // case-insensitive
        XCTAssertFalse(registry.isRegistered("unknown"))
        XCTAssertNotNil(registry.handler(for: "msg"))
    }

    /// A binary MSG routed through the registry should dump to a JSON
    /// artifact keyed "json" and rebuild byte-identical.
    func testRegistryMSGDumpAndBuildRoundTrip() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]  // "Hi\0"

        let registry = FileFormatRegistry.builtins()
        let handler = try XCTUnwrap(registry.handler(for: "msg"))

        let input = GoDData(byteStream: raw, byteOrder: .big)
        let artifacts = try handler.dump(input)
        XCTAssertEqual(Set(artifacts.keys), ["json"])
        XCTAssertGreaterThan(artifacts["json"]!.length, 0)

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
            baseName: "test",
            into: folder,
            fileSystem: fs,
            overwrite: true
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.fileName, "test.json")
        XCTAssertNotNil(fs.readFile(at: folder.file("test.json")))

        let rebuilt = try registry.build(
            extension: "msg",
            baseName: "test",
            from: folder,
            fileSystem: fs
        )
        XCTAssertEqual(rebuilt.rawBytes, raw)
    }

    func testUnregisteredExtensionThrows() {
        let registry = FileFormatRegistry.builtins()
        let fs = InMemoryFST()
        _ = fs.createFolder(at: Folder("/x"), overwrite: true)

        XCTAssertThrowsError(
            try registry.dump(
                bytes: GoDData(byteStream: [0, 1, 2, 3], byteOrder: .big),
                extension: "bogus",
                baseName: "foo",
                into: Folder("/x"),
                fileSystem: fs
            )
        )
    }
}
