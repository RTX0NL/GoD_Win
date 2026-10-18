//
//  NintendoArchiveOperationTests.swift
//  GODOpsTests
//
//  Runs the four archive operations against an InMemoryFST with synthetic
//  archives. The engine-level tests already prove the formats; what these
//  cover is the operation layer's own decisions — where output lands, how
//  bulk runs are filtered, and that a dump feeds its own build.
//

import XCTest
import GoDFoundation
import Nintendo
@testable import GODOps

final class NintendoArchiveOperationTests: XCTestCase {

    private func engine() throws -> NintendoEngine { try .defaults() }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func u8Bytes(byteOrder: ByteOrder = .big) throws -> GoDData {
        try U8Archive(
            byteOrder: byteOrder,
            nodes: [
                .init(path: "arc", kind: .directory),
                .init(path: "arc/one.brlan", kind: .file(payload("first"))),
                .init(path: "arc/two.tpl", kind: .file(payload("second"))),
            ]
        ).data(engine: try engine())
    }

    private func narcBytes(byteOrder: ByteOrder = .big) throws -> GoDData {
        try NARCArchive(
            byteOrder: byteOrder,
            entries: (0 ..< 4).map { .init(name: nil, data: payload("entry \($0)")) }
        ).data(engine: try engine())
    }

    // MARK: - Single dump / build

    func testSingleDumpWritesManifestAndContents() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/homeBtn.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(
                archivePath: File("/files/homeBtn.arc"),
                outputFolder: Folder("/out")
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/homeBtn.arc.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/homeBtn/arc/one.brlan")))
        XCTAssertNotNil(fst.readFile(at: File("/out/homeBtn/arc/two.tpl")))
    }

    func testSingleDumpThenBuildReproducesTheArchive() throws {
        let fst = InMemoryFST()
        let original = try u8Bytes()
        try fst.writeFile(original, at: File("/files/homeBtn.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivePath: File("/files/homeBtn.arc"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try NintendoArchiveBuild.build(
            config: .init(
                manifestPath: File("/out/homeBtn.arc.json"),
                outputPath: File("/built/homeBtn.arc")
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertEqual(fst.readFile(at: File("/built/homeBtn.arc"))?.allData?.rawBytes, original.rawBytes)
    }

    /// With no output path the rebuilt archive lands beside its manifest,
    /// under the name the manifest recorded.
    func testSingleBuildDefaultsToTheManifestsFolder() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try narcBytes(), at: File("/files/seq.narc"), overwrite: true)
        try NintendoArchiveDump.dump(
            config: .init(archivePath: File("/files/seq.narc"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try NintendoArchiveBuild.build(
            config: .init(manifestPath: File("/out/seq.narc.json")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertNotNil(fst.readFile(at: File("/out/seq.narc")))
    }

    func testSingleDumpThrowsWhenTheArchiveIsMissing() {
        XCTAssertThrowsError(
            try NintendoArchiveDump.dump(
                config: .init(archivePath: File("/files/nope.arc"), outputFolder: Folder("/out")),
                settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger()
            )
        )
    }

    // MARK: - Bulk dump

    func testBulkDumpGivesEachArchiveItsOwnSubfolder() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/a.arc"), overwrite: true)
        try fst.writeFile(try u8Bytes(), at: File("/files/b.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        // Both archives hold `arc/one.brlan`; separate subfolders are what
        // stops the second from overwriting the first.
        XCTAssertNotNil(fst.readFile(at: File("/out/a.arc/a/arc/one.brlan")))
        XCTAssertNotNil(fst.readFile(at: File("/out/b.arc/b/arc/one.brlan")))
        XCTAssertNotNil(fst.readFile(at: File("/out/a.arc/a.arc.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/b.arc/b.arc.json")))
    }

    /// Files that aren't archives share the folder with ones that are, so a
    /// bulk run has to skip them rather than fail.
    func testBulkDumpSkipsNonArchives() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/real.arc"), overwrite: true)
        try fst.writeFile(payload("just some bytes"), at: File("/files/notes.txt"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/real.arc/real.arc.json")))
        XCTAssertNil(fst.readFile(at: File("/out/notes.txt/notes.txt.json")))
    }

    /// Identification is by magic, not extension — a NARC named `.arc`
    /// still unpacks as a NARC.
    func testBulkDumpIdentifiesByMagicNotExtension() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try narcBytes(), at: File("/files/mislabelled.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let registry: NintendoArchiveRegistry = try fst.decodeJSON(
            from: File("/out/mislabelled.arc/mislabelled.arc.json")
        )
        XCTAssertEqual(registry.format, .narc)
    }

    func testBulkDumpFormatFilter() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/a.arc"), overwrite: true)
        try fst.writeFile(try narcBytes(), at: File("/files/b.narc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(
                archivesFolder: Folder("/files"),
                outputFolder: Folder("/out"),
                filter: .onlyFormats(["narc"])
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/b.narc/b.narc.json")))
        XCTAssertNil(fst.readFile(at: File("/out/a.arc/a.arc.json")))
    }

    func testBulkDumpExtensionFilter() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/a.arc"), overwrite: true)
        try fst.writeFile(try narcBytes(), at: File("/files/b.narc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(
                archivesFolder: Folder("/files"),
                outputFolder: Folder("/out"),
                filter: .onlyExtensions(["arc"])
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/a.arc/a.arc.json")))
        XCTAssertNil(fst.readFile(at: File("/out/b.narc/b.narc.json")))
    }

    /// Off by default, so pointing a bulk dump at one folder can't quietly
    /// walk a whole disc.
    func testBulkDumpDoesNotRecurseByDefault() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/top.arc"), overwrite: true)
        try fst.writeFile(try u8Bytes(), at: File("/files/nested/deep.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/top.arc/top.arc.json")))
        XCTAssertNil(fst.readFile(at: File("/out/deep.arc/deep.arc.json")))
    }

    func testBulkDumpRecursesWhenAsked() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/nested/deep.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(
                archivesFolder: Folder("/files"),
                outputFolder: Folder("/out"),
                recursive: true
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertNotNil(fst.readFile(at: File("/out/nested/deep.arc/deep.arc.json")))
    }

    /// Battle Revolution keeps eight same-named archives in both
    /// `hb/HomeButton2/` and `hb/HomeButton3/`. A recursive dump that dropped
    /// the folder wrote both to one place, so the second overwrote the first.
    func testRecursiveDumpAndBuildKeepSameNamedArchivesApart() throws {
        let fst = InMemoryFST()
        let first = try u8Bytes()
        let second = try u8Bytes(byteOrder: .little)
        XCTAssertNotEqual(first.rawBytes, second.rawBytes)
        try fst.writeFile(first, at: File("/files/hb/HomeButton2/homeBtn.arc"), overwrite: true)
        try fst.writeFile(second, at: File("/files/hb/HomeButton3/homeBtn.arc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out"), recursive: true),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertNotNil(fst.readFile(at: File("/out/hb/HomeButton2/homeBtn.arc/homeBtn.arc.json")))
        XCTAssertNotNil(fst.readFile(at: File("/out/hb/HomeButton3/homeBtn.arc/homeBtn.arc.json")))

        try NintendoArchiveBuild.build(
            config: .init(inputFolder: Folder("/out"), outputFolder: Folder("/built")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertEqual(fst.readFile(at: File("/built/hb/HomeButton2/homeBtn.arc"))?.allData?.rawBytes, first.rawBytes)
        XCTAssertEqual(fst.readFile(at: File("/built/hb/HomeButton3/homeBtn.arc"))?.allData?.rawBytes, second.rawBytes)
    }

    // MARK: - Bulk build

    func testBulkDumpThenBulkBuildReproducesEveryArchive() throws {
        let fst = InMemoryFST()
        let u8 = try u8Bytes()
        let narc = try narcBytes()
        try fst.writeFile(u8, at: File("/files/a.arc"), overwrite: true)
        try fst.writeFile(narc, at: File("/files/b.narc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try NintendoArchiveBuild.build(
            config: .init(inputFolder: Folder("/out"), outputFolder: Folder("/built")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        XCTAssertEqual(fst.readFile(at: File("/built/a.arc"))?.allData?.rawBytes, u8.rawBytes)
        XCTAssertEqual(fst.readFile(at: File("/built/b.narc"))?.allData?.rawBytes, narc.rawBytes)
    }

    /// A project folder holds JSON that belongs to other operations, so a
    /// bulk build has to ignore anything that isn't one of our manifests.
    func testBulkBuildIgnoresForeignJSON() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/a.arc"), overwrite: true)
        try NintendoArchiveDump.dump(
            config: .init(archivesFolder: Folder("/files"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try fst.writeFile(
            GoDData(byteStream: Array(#"{"unrelated": true}"#.utf8), byteOrder: .big),
            at: File("/out/other.json"), overwrite: true
        )

        try NintendoArchiveBuild.build(
            config: .init(inputFolder: Folder("/out"), outputFolder: Folder("/built")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        XCTAssertNotNil(fst.readFile(at: File("/built/a.arc")))
    }

    /// Two manifests that name the same archive in one folder can't both be
    /// built; the run stops rather than letting the second overwrite the
    /// first.
    func testBulkBuildRefusesTwoManifestsForOneArchive() throws {
        let fst = InMemoryFST()
        try fst.writeFile(try u8Bytes(), at: File("/files/a.arc"), overwrite: true)
        try NintendoArchiveDump.dump(
            config: .init(archivePath: File("/files/a.arc"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        let manifest = try XCTUnwrap(fst.readFile(at: File("/out/a.arc.json"))?.allData)
        try fst.writeFile(manifest, at: File("/out/copy.json"), overwrite: true)

        XCTAssertThrowsError(
            try NintendoArchiveBuild.build(
                config: .init(inputFolder: Folder("/out"), outputFolder: Folder("/built")),
                settings: .default, fileSystem: fst, logger: SilentLogger()
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("/built/a.arc"), "\(error)")
        }
    }

    // MARK: - Byte order

    /// A little-endian archive has to come back little-endian, which is the
    /// whole reason the manifest records the byte order rather than letting
    /// the writer re-detect it.
    func testLittleEndianArchiveSurvivesDumpAndBuild() throws {
        let fst = InMemoryFST()
        let original = try narcBytes(byteOrder: .little)
        try fst.writeFile(original, at: File("/files/le.narc"), overwrite: true)

        try NintendoArchiveDump.dump(
            config: .init(archivePath: File("/files/le.narc"), outputFolder: Folder("/out")),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
        try NintendoArchiveBuild.build(
            config: .init(
                manifestPath: File("/out/le.narc.json"),
                outputPath: File("/built/le.narc")
            ),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )

        let rebuilt = fst.readFile(at: File("/built/le.narc"))?.allData
        XCTAssertEqual(rebuilt?.rawBytes, original.rawBytes)
        XCTAssertEqual(Array(rebuilt?.rawBytes.prefix(4) ?? []), Array("NARC".utf8))
    }
}
