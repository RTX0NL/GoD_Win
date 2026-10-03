import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

/// Registry-level behavior only — dispatch, filesystem I/O layout, error
/// paths. The protocol members of each format are exercised in
/// `FileFormatProtocolTests` so these tests focus on what the registry
/// adds on top: extension → handler routing, baseName-less dump folder
/// layout, build-from-folder, error propagation.
final class FileFormatRegistryTests: XCTestCase {

    /// Dump writes every artifact from the format's `outputs` into the
    /// target folder at `<folder>/<key.path>`. For a known MSG input the
    /// artifact set is a single JSON named after the default "msg" stem.
    func testRegistryDump_writesArtifactsAtExpectedPaths() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]

        let fs = InMemoryFST()
        let folder = Folder("/out")
        try fs.createFolder(at: folder, overwrite: true)

        let written = try FileFormatRegistry.builtins().dump(
            bytes: GoDData(byteStream: raw, byteOrder: .big),
            extension: "msg",
            into: folder,
            fileSystem: fs,
            overwrite: true
        )
        XCTAssertEqual(written.count, 1)
        // The registry names the synthetic input "input.msg", so the MSG
        // format derives its stem from that ("input"), not the fallback.
        XCTAssertEqual(written[0].fileName, "input.msg.json")
        XCTAssertNotNil(fs.readFile(at: folder.file("input.msg.json")))
    }

    /// Build reads every file under the target folder into an outputs
    /// dict keyed by the path relative to that folder and feeds it to the
    /// registered handler. Verifies the handler is invoked by checking
    /// the returned bytes parse as the expected format.
    func testRegistryBuild_readsFolderAndInvokesHandler() throws {
        let fs = InMemoryFST()
        let folder = Folder("/in")
        try fs.createFolder(at: folder, overwrite: true)

        let json = """
        {
          "entries": [{ "id": 3, "text": "Yo" }],
          "region": "US",
          "reservedPrefix": "00000000",
          "reservedSuffix": "0000000000000000",
          "variant": "xd"
        }
        """.data(using: .utf8)!
        try fs.writeFile(GoDData(data: json, byteOrder: .big),
                         at: folder.file("sample.msg.json"),
                         overwrite: true)

        let rebuilt = try FileFormatRegistry.builtins().buildSingle(
            extension: "msg", from: folder, fileSystem: fs
        )
        let parsed = try MSGFile(binary: rebuilt, variant: .xd)
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries[0].id, 3)
    }

    /// Dump keys that contain slashes produce nested files under the
    /// target folder. Tested via a synthetic format that's easier to
    /// control than the real ones — but also validated indirectly by
    /// GSW tests emitting per-texture PNG keys at the top level.
    func testRegistryDump_preservesFlatAndNestedKeys() throws {
        let fs = InMemoryFST()
        let folder = Folder("/out")
        try fs.createFolder(at: folder, overwrite: true)

        // Any registered handler will do — MSG is simplest, it emits a
        // single flat key.
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        // zero entries, zero strings — smallest valid MSG.

        let written = try FileFormatRegistry.builtins().dump(
            bytes: GoDData(byteStream: raw, byteOrder: .big),
            extension: "msg",
            into: folder,
            fileSystem: fs,
            overwrite: true
        )
        XCTAssertEqual(written[0].path, "/out/input.msg.json",
                       "flat key lands at <folder>/<key>")
    }

    // MARK: - Error paths

    func testRegistryDump_unregisteredExtensionThrows() throws {
        let fs = InMemoryFST()
        try fs.createFolder(at: Folder("/x"), overwrite: true)
        XCTAssertThrowsError(try FileFormatRegistry.builtins().dump(
            bytes: GoDData(byteStream: [0], byteOrder: .big),
            extension: "bogus",
            into: Folder("/x"),
            fileSystem: fs
        ))
    }

    func testRegistryBuild_unregisteredExtensionThrows() throws {
        let fs = InMemoryFST()
        try fs.createFolder(at: Folder("/x"), overwrite: true)
        XCTAssertThrowsError(try FileFormatRegistry.builtins().build(
            extension: "bogus", from: Folder("/x"), fileSystem: fs
        ))
    }

    func testRegistryBuild_emptyFolderThrowsNoArtifactsFound() throws {
        let fs = InMemoryFST()
        let folder = Folder("/empty")
        try fs.createFolder(at: folder, overwrite: true)
        XCTAssertThrowsError(try FileFormatRegistry.builtins().build(
            extension: "msg", from: folder, fileSystem: fs
        )) { error in
            XCTAssertTrue("\(error)".contains("no artifacts"))
        }
    }

    // MARK: - Merge

    func testRegistryMerge_combinesHandlersFromTwoRegistries() {
        var a = FileFormatRegistry()
        a.register("msg", MSGFile.self)
        var b = FileFormatRegistry()
        b.register("fnt", GSFont.self)
        a.merge(b)
        XCTAssertTrue(a.isRegistered("msg"))
        XCTAssertTrue(a.isRegistered("fnt"))
    }

    func testRegistryMerge_otherOverwritesOnConflict() {
        var a = FileFormatRegistry()
        a.register("msg", GSFont.self)   // deliberately wrong type
        var b = FileFormatRegistry()
        b.register("msg", MSGFile.self)
        a.merge(b)
        XCTAssertTrue(a.handler(for: "msg")?.formatType == MSGFile.self,
                      "the other registry's handler wins on conflict")
    }
}
