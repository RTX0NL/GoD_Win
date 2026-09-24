//
//  FSYSFontNamingTests.swift
//  ColosseumTests
//
//  What an extracted font is called, and which archives end up sharing one.
//
//  Fonts used to be pooled: one copy of each distinct font under a serial
//  `Font_Data_<n>`, shared by every archive carrying those bytes. The number
//  moved whenever the set of fonts changed, and it could only ever name one of
//  the archives a font came from. They are now written like any other entry —
//  `<stored name>_<index in the archive>.fnt` — so a font is named for where
//  it came from, and archives that agree on a name *and* on their bytes still
//  share one file through the unpack's ordinary collision pass.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import GeniusSonority

final class FSYSFontNamingTests: XCTestCase {

    private let discRoot = Folder("/disc")

    private func engine(_ game: GSGame = .galeOfDarkness) -> GeniusSonorityEngine {
        .defaultEngine(for: game)
    }

    /// Nothing here parses a font: the unpack routes and names by metadata
    /// and compares payloads. Distinct `seed`s are distinct fonts.
    private func font(_ seed: String) -> GoDData {
        GoDData(byteStream: Array("font:\(seed)".utf8), byteOrder: .big)
    }

    private func fontEntry(named name: String, identifier: Int, data: GoDData) -> FSYSArchive.Entry {
        FSYSArchive.Entry(
            metadata: .init(name: name, fileType: "fnt", identifier: identifier,
                            compress: false, includesFullFilename: nil),
            filename: "\(name).fnt",
            data: data
        )
    }

    private func makeDisc(
        _ archives: [(path: String, entries: [FSYSArchive.Entry])],
        engine: GeniusSonorityEngine
    ) throws -> InMemoryFST {
        let fst = InMemoryFST()
        let toc = FsysTOC(unknown: engine.data.toc.unknown)
        try fst.writeFile(
            try toc.tocData(with: engine),
            at: discRoot.folder("files").file(engine.data.fsys.GSfsysFile.fileName),
            overwrite: true
        )
        for archive in archives {
            let data = try FSYSArchive(
                groupID: 0,
                metadata: .init(unknownFlag1: false, unknownFlag2: false, debugFlag: false,
                                unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0),
                entries: archive.entries
            ).data(groupID: 0, engine: engine)
            try fst.writeFile(data, at: discRoot.folder("files").file(archive.path), overwrite: true)
        }
        return fst
    }

    /// Every font path the archive's registry points at.
    private func fontPaths(_ tree: FileSystemTree, forArchive discPath: String) throws -> [String] {
        let fst: FSTRegistry = try tree.decodeJSON(from: Folder("/").file("FST.json"))
        let entry = try XCTUnwrap(fst.entries.first { $0.discPath == discPath },
                                  "no FST entry for \(discPath)")
        let registry: FSYSRegistry = try tree.decodeJSON(from: entry.file)
        return registry.entries.filter { $0.metadata.fileType == "fnt" }.map(\.file.path)
    }

    // MARK: - Naming

    /// A named font entry takes its index too, because a stored name is only
    /// unique inside its own archive. An unnamed one is unchanged — its name
    /// already carries the index.
    func testAFontTakesTheEntryIndexAsWellAsItsName() {
        let engine = engine()
        XCTAssertEqual(
            engine.projectFilename(forEntryNamed: "fight", filename: "fight.fnt",
                                   index: 1, archiveName: "fight_common", indexed: true),
            "fight_001.fnt"
        )
        XCTAssertEqual(
            engine.projectFilename(forEntryNamed: "fight", filename: "fight.fnt",
                                   index: 2, archiveName: "waza_viewer", indexed: true),
            "fight_002.fnt"
        )
        // Without the flag — every other file type — the name is untouched.
        XCTAssertEqual(
            engine.projectFilename(forEntryNamed: "fight", filename: "fight.fnt",
                                   index: 1, archiveName: "fight_common"),
            "fight.fnt"
        )
        // A `(null)` entry is already `<archive>_<index>`; it doesn't get a
        // second index bolted on.
        XCTAssertEqual(
            engine.projectFilename(forEntryNamed: "(null)", filename: "(null).fnt",
                                   index: 34, archiveName: "common", indexed: true),
            "common_034.fnt"
        )
    }

    /// End to end: the font is named for its own entry, not for a serial.
    func testAFontIsNamedAfterTheEntryItCameFrom() throws {
        let engine = engine()
        let disc = try makeDisc([
            ("mailopen_menu.fsys", [
                fontEntry(named: "other", identifier: 1, data: font("other")),
                fontEntry(named: "pda_menu", identifier: 2, data: font("pda")),
            ]),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        XCTAssertEqual(try fontPaths(output, forArchive: "mailopen_menu.fsys").map { File($0).fileName },
                       ["other_000.fnt", "pda_menu_001.fnt"])
    }

    // MARK: - Sharing

    /// Archives that carry the same font under their own names each keep a
    /// copy — the font is no longer pooled onto one archive's name.
    func testArchivesCarryingOneFontUnderDifferentNamesEachKeepACopy() throws {
        let engine = engine()
        let shared = font("space")
        let archives = ["D1_labo_1F", "D1_out", "M2_enter_1F"]
        let disc = try makeDisc(archives.enumerated().map { index, name in
            ("\(name).fsys", [fontEntry(named: name, identifier: index + 1, data: shared)])
        }, engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let paths = try archives.flatMap { try fontPaths(output, forArchive: "\($0).fsys") }
        XCTAssertEqual(paths.map { File($0).fileName },
                       ["D1_labo_1F_000.fnt", "D1_out_000.fnt", "M2_enter_1F_000.fnt"])
        for path in paths {
            XCTAssertEqual(output.readFile(at: File(path))?.allData?.rawBytes, shared.rawBytes,
                           "\(path) doesn't hold the font its archive carried")
        }
    }

    /// The sharing that remains: same name, same bytes, same folder, one
    /// file — which is the ordinary collision pass, not a font rule.
    func testArchivesAgreeingOnNameAndBytesShareOneFile() throws {
        let engine = engine()
        let shared = font("system_tool")
        let disc = try makeDisc([
            ("carde_menu.fsys", [fontEntry(named: "system_tool", identifier: 1, data: shared)]),
            ("hologram_menu.fsys", [fontEntry(named: "system_tool", identifier: 2, data: shared)]),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let paths = try ["carde_menu.fsys", "hologram_menu.fsys"]
            .flatMap { try fontPaths(output, forArchive: $0) }
        XCTAssertEqual(Set(paths).count, 1, "identical fonts of one name became \(Set(paths).count) files")
        XCTAssertEqual(File(paths[0]).fileName, "system_tool_000.fnt")
    }

    /// A language variant of an archive routes into its own language folder,
    /// so its font is a separate file from the base archive's even when the
    /// bytes match. The pool used to merge those; on the XD US disc that is
    /// the five `fight_common*` archives. Nothing is lost — each archive now
    /// holds the font it shipped, under the language it belongs to.
    func testLanguageVariantsKeepTheirFontUnderTheirOwnLanguageFolder() throws {
        let engine = engine()
        let shared = font("fight")
        let disc = try makeDisc([
            ("fight_common.fsys", [fontEntry(named: "fight", identifier: 1, data: shared)]),
            ("fight_common_fr.fsys", [fontEntry(named: "fight", identifier: 2, data: shared)]),
            ("fight_common_ge.fsys", [fontEntry(named: "fight", identifier: 3, data: shared)]),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let paths = try ["fight_common.fsys", "fight_common_fr.fsys", "fight_common_ge.fsys"]
            .flatMap { try fontPaths(output, forArchive: $0) }
        XCTAssertEqual(paths, [
            "/Data/Text/Fonts/fight_000.fnt",
            "/Data/Text/Fonts/French/fight_000.fnt",
            "/Data/Text/Fonts/German/fight_000.fnt",
        ])
        for path in paths {
            XCTAssertEqual(output.readFile(at: File(path))?.allData?.rawBytes, shared.rawBytes)
        }
    }

    /// Two different fonts stored under one name at one index are two files.
    /// `M2_enter_1F` and `M2_enter_1F_2` do this on the XD US disc.
    func testTwoDifferentFontsUnderOneNameStayTwoFiles() throws {
        let engine = engine()
        let disc = try makeDisc([
            ("M2_enter_1F.fsys", [fontEntry(named: "M2_enter_1F", identifier: 1, data: font("space"))]),
            ("M2_enter_1F_2.fsys", [fontEntry(named: "M2_enter_1F", identifier: 2, data: font("full"))]),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let first = try fontPaths(output, forArchive: "M2_enter_1F.fsys")
        let second = try fontPaths(output, forArchive: "M2_enter_1F_2.fsys")
        XCTAssertEqual(first.map { File($0).fileName }, ["M2_enter_1F_000.fnt"])
        XCTAssertEqual(second.map { File($0).fileName }, ["M2_enter_1F_000 (2).fnt"])
        XCTAssertEqual(output.readFile(at: File(first[0]))?.allData?.rawBytes, font("space").rawBytes)
        XCTAssertEqual(output.readFile(at: File(second[0]))?.allData?.rawBytes, font("full").rawBytes)
    }

    /// A misc archive keeps the rest of its contents in a folder of its own,
    /// but its font still files under the fonts folder — the font ops work
    /// over that one folder, and a font routed elsewhere would drop out of
    /// them. `waza_viewer` is the XD case (its `fight` font is a 524-glyph
    /// sheet, nothing like `fight_common`'s four glyphs).
    func testAFontInAMiscArchiveStillFilesUnderTheFontsFolder() throws {
        let engine = engine()
        let fontsFolder = try XCTUnwrap(engine.data.fsys.fileTypeFolders["fnt"])
        let disc = try makeDisc([
            ("waza_viewer.fsys", [
                fontEntry(named: "other", identifier: 1, data: font("other")),
                fontEntry(named: "fight", identifier: 2, data: font("viewer")),
            ]),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        XCTAssertEqual(try fontPaths(output, forArchive: "waza_viewer.fsys"),
                       [fontsFolder.file("other_000.fnt").path,
                        fontsFolder.file("fight_001.fnt").path])
    }

    /// A font's name must not depend on what else is on the disc: the serial
    /// numbering used to renumber every font after one that changed.
    func testAFontKeepsItsNameWhenOtherFontsChange() throws {
        let engine = engine()
        let keeper = font("keeper")
        let full = try makeDisc([
            ("a_first.fsys", [fontEntry(named: "a_first", identifier: 1, data: font("first"))]),
            ("b_middle.fsys", [fontEntry(named: "b_middle", identifier: 2, data: font("middle"))]),
            ("c_keeper.fsys", [fontEntry(named: "c_keeper", identifier: 3, data: keeper)]),
        ], engine: engine)
        let trimmed = try makeDisc([
            ("c_keeper.fsys", [fontEntry(named: "c_keeper", identifier: 3, data: keeper)]),
        ], engine: engine)

        let before = try fontPaths(try engine.unpackProject(from: discRoot, fileSystem: full),
                                   forArchive: "c_keeper.fsys")
        let after = try fontPaths(try engine.unpackProject(from: discRoot, fileSystem: trimmed),
                                  forArchive: "c_keeper.fsys")
        XCTAssertEqual(before, after, "the font was renamed by a change to an unrelated archive")
        XCTAssertEqual(before.map { File($0).fileName }, ["c_keeper_000.fnt"])
    }
}
