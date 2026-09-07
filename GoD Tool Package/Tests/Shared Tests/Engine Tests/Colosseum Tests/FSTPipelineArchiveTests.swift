//
//  FSTPipelineArchiveTests.swift
//  ColosseumTests
//
//  The disc-level pipeline's handling of Nintendo containers: unpacking the
//  `.arc` and `.narc` files a disc carries alongside its FSYS archives, and
//  the raw-bytes fallback that keeps one unreadable file from failing a
//  whole dump.
//
//  Both halves of the round trip are exercised, because the `.nintendoArchive`
//  FST entry type is only useful if the dump emits what the rebuild consumes.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import GeniusSonority
import Nintendo

final class FSTPipelineArchiveTests: XCTestCase {

    private let discRoot = Folder("/disc")

    private func engine() -> GeniusSonorityEngine {
        .defaultEngine(for: .battleRevolution)
    }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func u8Bytes(_ marker: String) throws -> GoDData {
        try U8Archive(
            byteOrder: .big,
            nodes: [
                .init(path: "arc", kind: .directory),
                .init(path: "arc/one.brlan", kind: .file(payload("animation \(marker)"))),
                .init(path: "arc/two.tpl", kind: .file(payload("texture \(marker)"))),
            ]
        ).data(engine: try NintendoEngine.defaults())
    }

    private func narcBytes() throws -> GoDData {
        try NARCArchive(
            byteOrder: .big,
            entries: (0 ..< 4).map { .init(name: nil, data: payload("entry \($0)")) }
        ).data(engine: try NintendoEngine.defaults())
    }

    /// A disc tree holding just a table of contents and whatever files the
    /// test supplies. No FSYS archives — the TOC can be empty, and these
    /// tests are about the other file kinds.
    private func makeDisc(files: [(path: String, data: GoDData)]) throws -> InMemoryFST {
        let fst = InMemoryFST()
        let engine = engine()
        let toc = FsysTOC(unknown: engine.data.toc.unknown)
        try fst.writeFile(
            try toc.tocData(with: engine),
            at: discRoot.folder("files").file(engine.data.fsys.GSfsysFile.fileName),
            overwrite: true
        )
        for file in files {
            try fst.writeFile(file.data, at: discRoot.folder("files").file(file.path), overwrite: true)
        }
        return fst
    }

    private func registry(from tree: FileSystemTree) throws -> FSTRegistry {
        try tree.decodeJSON(from: Folder("/").file("FST.json"))
    }

    private func entry(_ registry: FSTRegistry, discPath: String) -> FSTRegistry.Entry? {
        registry.entries.first { $0.discPath == discPath }
    }

    // MARK: - Unpacking

    func testArchivesAreUnpackedAndMarkedInTheFST() throws {
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/homeBtn.arc", try u8Bytes("two")),
            ("arcDat/seq.narc", try narcBytes()),
        ])
        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        XCTAssertEqual(entry(fst, discPath: "hb/HomeButton2/homeBtn.arc")?.type, .nintendoArchive)
        XCTAssertEqual(entry(fst, discPath: "arcDat/seq.narc")?.type, .nintendoArchive)

        // The manifest and the extracted contents both landed.
        let manifest = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton2/homeBtn.arc")?.file)
        XCTAssertNotNil(output.readFile(at: manifest))
        let contents: NintendoArchiveRegistry = try output.decodeJSON(from: manifest)
        XCTAssertEqual(contents.format, .u8)
        XCTAssertEqual(contents.archiveName, "homeBtn.arc")
    }

    /// Selection is by extension, so a container that isn't named like one
    /// stays an ordinary binary rather than being sniffed out.
    func testAnArchiveWithAnUnrelatedExtensionStaysBinary() throws {
        let disc = try makeDisc(files: [("misc/homeBtn.dat", try u8Bytes("hidden"))])
        let fst = try registry(from: try engine().unpackProject(from: discRoot, fileSystem: disc))
        XCTAssertEqual(entry(fst, discPath: "misc/homeBtn.dat")?.type, .binary)
    }

    /// PBR ships the same `homeBtn.arc` under two folders, so the unpacked
    /// artifacts have to be namespaced by the archive's own disc directory.
    func testArchivesSharingAFilenameDoNotCollide() throws {
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/homeBtn.arc", try u8Bytes("two")),
            ("hb/HomeButton3/homeBtn.arc", try u8Bytes("three")),
        ])
        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        let second = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton2/homeBtn.arc")?.file)
        let third = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton3/homeBtn.arc")?.file)
        XCTAssertNotEqual(second.path, third.path, "both archives wrote to the same manifest")

        // And their contents are the two different sets of bytes, not one
        // set written twice.
        let engine = engine()
        let packedSecond = try NintendoEngine.defaults().packArchive(manifestFile: second, fileSystem: output)
        let packedThird = try NintendoEngine.defaults().packArchive(manifestFile: third, fileSystem: output)
        XCTAssertEqual(packedSecond.rawBytes, try u8Bytes("two").rawBytes)
        XCTAssertEqual(packedThird.rawBytes, try u8Bytes("three").rawBytes)
        _ = engine
    }

    // MARK: - Round trip

    func testUnpackThenPackReproducesTheArchivesByteIdentically() throws {
        let u8 = try u8Bytes("two")
        let narc = try narcBytes()
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/homeBtn.arc", u8),
            ("arcDat/seq.narc", narc),
        ])
        let engine = engine()
        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)

        let built = InMemoryFST()
        // Everything the pack reads lives beside FST.json, so the project
        // tree is both the source folder and where the manifest resolves.
        try copyTree(output, into: built, at: Folder("/project"))
        try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )

        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/HomeButton2/homeBtn.arc"))?.allData?.rawBytes,
            u8.rawBytes
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("arcDat/seq.narc"))?.allData?.rawBytes,
            narc.rawBytes
        )
    }

    // MARK: - Fallback

    /// An unreadable archive is still a file the disc needs. It falls back
    /// to raw bytes with a `.binary` entry rather than failing the dump.
    func testAnUnreadableArchiveFallsBackToRawBytes() throws {
        let corrupt = payload("this is not a U8 archive at all")
        let disc = try makeDisc(files: [
            ("hb/broken.arc", corrupt),
            ("arcDat/seq.narc", try narcBytes()),
        ])
        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        let broken = try XCTUnwrap(entry(fst, discPath: "hb/broken.arc"))
        XCTAssertEqual(broken.type, .binary, "an unreadable archive should degrade to binary")
        XCTAssertEqual(output.readFile(at: broken.file)?.allData?.rawBytes, corrupt.rawBytes,
                       "the original bytes must survive verbatim")

        // The good archive alongside it still unpacked.
        XCTAssertEqual(entry(fst, discPath: "arcDat/seq.narc")?.type, .nintendoArchive)
    }

    func testAnUnreadableArchiveStillRebuildsVerbatim() throws {
        let corrupt = payload("not an archive")
        let disc = try makeDisc(files: [("hb/broken.arc", corrupt)])
        let engine = engine()
        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)

        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))
        try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/broken.arc"))?.allData?.rawBytes,
            corrupt.rawBytes
        )
    }

    /// Same policy for FSYS: one archive that won't parse shouldn't take the
    /// whole disc down with it.
    func testAnUnreadableFSYSFallsBackToRawBytes() throws {
        let corrupt = payload("definitely not an FSYS archive")
        let disc = try makeDisc(files: [("broken.fsys", corrupt)])

        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        let broken = try XCTUnwrap(entry(fst, discPath: "broken.fsys"))
        XCTAssertEqual(broken.type, FSTRegistry.EntryType.binary)
        XCTAssertEqual(output.readFile(at: broken.file)?.allData?.rawBytes, corrupt.rawBytes)
    }

    // MARK: - Helpers

    /// Copies every file of `source` under `root` of `destination`, so a
    /// project tree produced in memory can be packed from a folder.
    private func copyTree(_ source: FileSystemTree, into destination: FileSystemTree, at root: Folder) throws {
        func walk(_ folder: Folder) throws {
            guard let meta = source.inspectFolder(at: folder) else { return }
            for file in meta.files {
                guard let data = source.readFile(at: file)?.allData else { continue }
                var relative = file.path
                if relative.hasPrefix("/") { relative.removeFirst() }
                try destination.writeFile(data, at: root.file(relative), overwrite: true)
            }
            for sub in meta.subFolders { try walk(sub) }
        }
        try walk(Folder("/"))
    }
}
