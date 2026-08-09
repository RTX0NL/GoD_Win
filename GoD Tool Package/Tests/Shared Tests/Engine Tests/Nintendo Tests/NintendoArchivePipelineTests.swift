//
//  NintendoArchivePipelineTests.swift
//  NintendoTests
//
//  Unpacking to a project folder and packing back from the manifest. The
//  property that matters is that the manifest plus the extracted files are
//  *sufficient* — nothing is read back from the original archive — so every
//  test here packs from a fresh filesystem read rather than from the object
//  the unpack returned.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Nintendo

final class NintendoArchivePipelineTests: XCTestCase {

    private func engine() throws -> NintendoEngine { try .defaults() }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func u8Archive(byteOrder: ByteOrder = .big) -> U8Archive {
        U8Archive(
            byteOrder: byteOrder,
            nodes: [
                .init(path: "arc", kind: .directory),
                .init(path: "arc/anim", kind: .directory),
                .init(path: "arc/anim/one.brlan", kind: .file(payload("first"))),
                .init(path: "arc/timg", kind: .directory),
                .init(path: "arc/timg/tex.tpl", kind: .file(payload("texture"))),
                .init(path: "empty", kind: .directory),
                .init(path: "top.txt", kind: .file(payload("top level"))),
            ]
        )
    }

    private func narcArchive(byteOrder: ByteOrder = .big, named: Bool = false) -> NARCArchive {
        NARCArchive(
            byteOrder: byteOrder,
            entries: (0 ..< 5).map { index in
                .init(
                    name: named ? "entry\(index).bin" : nil,
                    data: payload(String(repeating: "abc", count: index + 1))
                )
            }
        )
    }

    // MARK: - U8

    func testU8UnpackThenPackReproducesTheArchive() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let original = try u8Archive().data(engine: engine)
        let folder = Folder("/project/archives")

        let result = try engine.unpackArchive(
            data: original, archiveName: "homeBtn.arc", into: folder, fileSystem: fileSystem
        )
        XCTAssertEqual(result.registry.format, .u8)
        XCTAssertEqual(result.registry.byteOrder, .big)
        XCTAssertEqual(result.registry.archiveName, "homeBtn.arc")

        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    func testU8UnpackWritesContentsUnderTheArchivesOwnTree() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let folder = Folder("/project/archives")

        try engine.unpackArchive(
            data: try u8Archive().data(engine: engine),
            archiveName: "homeBtn.arc", into: folder, fileSystem: fileSystem
        )

        // The archive's directory structure is reproduced on disk, so the
        // extracted files sit where the game's own paths say they do.
        XCTAssertNotNil(fileSystem.readFile(at: folder.file("homeBtn/arc/anim/one.brlan")))
        XCTAssertNotNil(fileSystem.readFile(at: folder.file("homeBtn/arc/timg/tex.tpl")))
        XCTAssertNotNil(fileSystem.readFile(at: folder.file("homeBtn/top.txt")))
        XCTAssertNotNil(fileSystem.readFile(at: folder.file("homeBtn.arc.json")))
    }

    /// A directory with nothing in it has no extracted file to stand for it,
    /// so the manifest is the only thing that can carry it.
    func testU8ManifestRecordsEmptyDirectories() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let result = try engine.unpackArchive(
            data: try u8Archive().data(engine: engine),
            archiveName: "homeBtn.arc", into: Folder("/p"), fileSystem: fileSystem
        )
        let empty = result.registry.entries.first { $0.archivePath == "empty" }
        XCTAssertEqual(empty?.isDirectory, true)
        XCTAssertNil(empty?.file)
    }

    func testU8LittleEndianSurvivesTheManifest() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let original = try u8Archive(byteOrder: .little).data(engine: engine)
        let result = try engine.unpackArchive(
            data: original, archiveName: "le.arc", into: Folder("/p"), fileSystem: fileSystem
        )
        XCTAssertEqual(result.registry.byteOrder, .little)
        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    /// The manifest holds paths relative to its own folder, so the whole
    /// unpacked folder can be moved and still pack.
    func testU8PacksAfterTheFolderIsMoved() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let original = try u8Archive().data(engine: engine)
        let source = Folder("/first/place")
        let result = try engine.unpackArchive(
            data: original, archiveName: "homeBtn.arc", into: source, fileSystem: fileSystem
        )

        // Copy every artifact to a different root and pack from there.
        let moved = Folder("/somewhere/else")
        let registry: NintendoArchiveRegistry = try fileSystem.decodeJSON(from: result.manifestFile)
        for entry in registry.entries {
            guard let file = entry.file,
                  let data = fileSystem.readFile(at: source.file(file.path))?.allData else { continue }
            try fileSystem.writeFile(data, at: moved.file(file.path), overwrite: true)
        }
        let repacked = try engine.packArchive(
            registry: registry, sourceFolder: moved, fileSystem: fileSystem
        )
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    // MARK: - NARC

    func testNARCUnpackThenPackReproducesTheArchive() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let original = try narcArchive().data(engine: engine)
        let result = try engine.unpackArchive(
            data: original, archiveName: "waza_seq_rev.narc", into: Folder("/p"), fileSystem: fileSystem
        )
        XCTAssertEqual(result.registry.format, .narc)
        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    /// A nameless entry is identified by its index, so the extracted files
    /// are numbered and zero-padded to keep a directory listing in that
    /// order.
    func testNARCNamelessEntriesAreWrittenByIndex() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let folder = Folder("/p")
        let result = try engine.unpackArchive(
            data: try narcArchive().data(engine: engine),
            archiveName: "waza_seq_rev.narc", into: folder, fileSystem: fileSystem
        )
        for index in 0 ..< 5 {
            let name = String(format: "%04d.bin", index)
            XCTAssertNotNil(
                fileSystem.readFile(at: folder.file("waza_seq_rev/" + name)),
                "missing \(name)"
            )
        }
        XCTAssertTrue(result.registry.entries.allSatisfy { $0.archivePath == nil })
    }

    func testNARCNamedEntriesKeepTheirNames() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let folder = Folder("/p")
        let original = try narcArchive(named: true).data(engine: engine)
        let result = try engine.unpackArchive(
            data: original, archiveName: "named.narc", into: folder, fileSystem: fileSystem
        )
        XCTAssertNotNil(fileSystem.readFile(at: folder.file("named/entry0.bin")))
        XCTAssertEqual(result.registry.entries.first?.archivePath, "entry0.bin")
        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    func testNARCLittleEndianSurvivesTheManifest() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let original = try narcArchive(byteOrder: .little).data(engine: engine)
        let result = try engine.unpackArchive(
            data: original, archiveName: "le.narc", into: Folder("/p"), fileSystem: fileSystem
        )
        XCTAssertEqual(result.registry.byteOrder, .little)
        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertEqual(repacked.rawBytes, original.rawBytes)
    }

    /// Editing an extracted file has to change the rebuilt archive — the
    /// whole point of unpacking to a project folder.
    func testEditingAnExtractedFileChangesTheRebuiltArchive() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let folder = Folder("/p")
        let original = try u8Archive().data(engine: engine)
        let result = try engine.unpackArchive(
            data: original, archiveName: "homeBtn.arc", into: folder, fileSystem: fileSystem
        )

        try fileSystem.writeFile(
            payload("EDITED, and a different length"),
            at: folder.file("homeBtn/arc/anim/one.brlan"),
            overwrite: true
        )
        let repacked = try engine.packArchive(manifestFile: result.manifestFile, fileSystem: fileSystem)
        XCTAssertNotEqual(repacked.rawBytes, original.rawBytes)

        let reparsed = try U8Archive(data: repacked, engine: engine)
        let edited = reparsed.nodes.first { $0.path == "arc/anim/one.brlan" }
        guard case let .file(data)? = edited?.kind else {
            return XCTFail("the edited entry is missing from the rebuilt archive")
        }
        XCTAssertEqual(data.string(format: .utf8), "EDITED, and a different length")
    }

    // MARK: - Errors

    func testUnpackRejectsSomethingThatIsNotAnArchive() throws {
        let engine = try engine()
        XCTAssertThrowsError(
            try engine.unpackArchive(
                data: payload("not an archive at all"),
                archiveName: "x.arc", into: Folder("/p"), fileSystem: InMemoryFST()
            )
        ) { error in
            guard case NintendoArchiveError.unrecognizedMagic = error else {
                return XCTFail("expected unrecognizedMagic, got \(error)")
            }
        }
    }

    func testPackFailsWhenAnExtractedFileIsMissing() throws {
        let engine = try engine()
        let fileSystem = InMemoryFST()
        let registry = NintendoArchiveRegistry(
            format: .narc,
            byteOrder: .big,
            archiveName: "gone.narc",
            entries: [.init(archivePath: nil, file: File("gone/0000.bin"), isDirectory: false)]
        )
        XCTAssertThrowsError(
            try engine.packArchive(registry: registry, sourceFolder: Folder("/p"), fileSystem: fileSystem)
        )
    }
}
