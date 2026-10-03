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

    /// A loose file keeps the directory it sat in on the disc. PBR ships five
    /// files under both `hb/HomeButton2` and `hb/HomeButton3`; routing by type
    /// alone named them by basename, so the second of each pair overwrote the
    /// first and the rebuild wrote one copy's bytes into both.
    func testLooseFilesSharingAFilenameDoNotCollide() throws {
        let second = payload("HomeButton2's copy")
        let third = payload("HomeButton3's copy")
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/config.txt", second),
            ("hb/HomeButton3/config.txt", third),
            ("loose.bin", payload("at the root")),
        ])
        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        let a = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton2/config.txt")?.file)
        let b = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton3/config.txt")?.file)
        XCTAssertNotEqual(a.path, b.path, "both copies claimed one project path")
        XCTAssertEqual(output.readFile(at: a)?.allData?.rawBytes, second.rawBytes)
        XCTAssertEqual(output.readFile(at: b)?.allData?.rawBytes, third.rawBytes)

        // A file at the root of `files/` keeps its plain, un-nested path.
        let root = try XCTUnwrap(entry(fst, discPath: "loose.bin")?.file)
        XCTAssertEqual(File(root.path).fileName, "loose.bin")
        XCTAssertFalse(root.path.contains("/hb/"), "a root file shouldn't gain a directory")

        // And both come back where they belong.
        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))
        try engine().packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/HomeButton2/config.txt"))?.allData?.rawBytes,
            second.rawBytes
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/HomeButton3/config.txt"))?.allData?.rawBytes,
            third.rawBytes
        )
    }

    // MARK: - Platform directories

    /// `hb/HomeButton2` and `hb/HomeButton3` are the console's Home Menu
    /// library, not the game's assets, so they mirror their disc path under
    /// `/Platform` rather than sorting into the asset folders by file type.
    func testPlatformDirectoriesMirrorTheirDiscPathUnderPlatform() throws {
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/homeBtn.arc", try u8Bytes("two")),
            ("hb/HomeButton2/config.txt", payload("HomeButton2's copy")),
            ("hb/HomeButton3/config.txt", payload("HomeButton3's copy")),
        ])
        let output = try engine().unpackProject(from: discRoot, fileSystem: disc)
        let fst = try registry(from: output)

        let arc = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton2/homeBtn.arc")?.file)
        XCTAssertEqual(arc.path, "/Platform/hb/HomeButton2/homeBtn.arc.json")

        let second = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton2/config.txt")?.file)
        let third = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton3/config.txt")?.file)
        XCTAssertEqual(second.path, "/Platform/hb/HomeButton2/config.txt")
        XCTAssertEqual(third.path, "/Platform/hb/HomeButton3/config.txt")

        // Nothing platform-owned leaked into the game's asset folders.
        for entry in fst.entries {
            guard let discPath = entry.discPath, discPath.hasPrefix("hb/") else { continue }
            XCTAssertFalse(entry.file.path.hasPrefix("/Assets/"), "\(discPath) sorted as a game asset")
            XCTAssertFalse(entry.file.path.hasPrefix("/Archives/"), "\(discPath) sorted as a game archive")
        }
    }

    /// A game-content directory is unaffected: it still routes by file type
    /// and nests the disc directory under the folder its type chose.
    func testANonPlatformDirectoryStillRoutesByFileType() throws {
        let disc = try makeDisc(files: [("hb/HomeButton9/config.txt", payload("an unlisted version"))])
        let fst = try registry(from: try engine().unpackProject(from: discRoot, fileSystem: disc))
        let file = try XCTUnwrap(entry(fst, discPath: "hb/HomeButton9/config.txt")?.file)
        XCTAssertFalse(file.path.hasPrefix("/Platform/"), "an unlisted directory isn't platform data")
        XCTAssertTrue(file.path.hasSuffix("hb/HomeButton9/config.txt"), "it still keeps its disc directory")
    }

    /// The whole point of the folder is that the rebuild finds it again.
    func testPlatformFilesRebuildToTheirOriginalDiscPaths() throws {
        let u8 = try u8Bytes("two")
        let second = payload("HomeButton2's copy")
        let third = payload("HomeButton3's copy")
        let disc = try makeDisc(files: [
            ("hb/HomeButton2/homeBtn.arc", u8),
            ("hb/HomeButton2/config.txt", second),
            ("hb/HomeButton3/config.txt", third),
        ])
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
            built.readFile(at: Folder("/built/files").file("hb/HomeButton2/homeBtn.arc"))?.allData?.rawBytes,
            u8.rawBytes
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/HomeButton2/config.txt"))?.allData?.rawBytes,
            second.rawBytes
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("hb/HomeButton3/config.txt"))?.allData?.rawBytes,
            third.rawBytes
        )
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
