//
//  FSYSUnnamedEntryTests.swift
//  ColosseumTests
//
//  Entries whose name the games' packer never filled in.
//
//  Genius Sonority's packer printed an absent filename through `%s` with a
//  null pointer, so the archive stores the literal `(null)`. PBR does it for
//  every entry; XD does it for every streamed sound, every movie, the flash
//  menus and some textures — 1105 to 2104 entries per disc, which all used to
//  land on the same handful of project paths and overwrite each other.
//
//  Two things have to hold for those to survive a round trip: the unpack has
//  to give each one its own file, and the writer has to tolerate several
//  entries sharing a stored name, which is ordinary in these archives
//  (`D2_valley_1.fsys` holds six entries called `D2_valley_1`).
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import GeniusSonority

final class FSYSUnnamedEntryTests: XCTestCase {

    private let discRoot = Folder("/disc")
    private let placeholder = "(null)"

    private func engine(_ game: GSGame = .galeOfDarkness) -> GeniusSonorityEngine {
        .defaultEngine(for: game)
    }

    private func payload(_ text: String) -> GoDData {
        GoDData(byteStream: Array(text.utf8), byteOrder: .big)
    }

    private func entry(
        name: String,
        type: String,
        identifier: Int,
        payload text: String
    ) -> FSYSArchive.Entry {
        FSYSArchive.Entry(
            metadata: .init(name: name, fileType: type, identifier: identifier,
                            compress: false, includesFullFilename: nil),
            filename: "\(name).\(type)",
            data: payload(text)
        )
    }

    private func archiveBytes(
        _ entries: [FSYSArchive.Entry],
        groupID: Int = 0,
        engine: GeniusSonorityEngine
    ) throws -> GoDData {
        try FSYSArchive(
            groupID: groupID,
            metadata: .init(unknownFlag1: false, unknownFlag2: false, debugFlag: false,
                            unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0),
            entries: entries
        ).data(groupID: groupID, engine: engine)
    }

    /// A disc tree holding a table of contents and the given archives.
    private func makeDisc(
        _ archives: [(path: String, data: GoDData)],
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
            try fst.writeFile(archive.data, at: discRoot.folder("files").file(archive.path), overwrite: true)
        }
        return fst
    }

    private func registry(_ tree: FileSystemTree, forArchive discPath: String) throws -> FSYSRegistry {
        let fst: FSTRegistry = try tree.decodeJSON(from: Folder("/").file("FST.json"))
        let entry = try XCTUnwrap(fst.entries.first { $0.discPath == discPath },
                                 "no FST entry for \(discPath)")
        return try tree.decodeJSON(from: entry.file)
    }

    // MARK: - Naming

    /// The rule: an unnamed entry is named after the archive it came from
    /// plus its index, three digits; anything else keeps its own name.
    func testUnnamedEntriesAreNamedByArchiveAndIndex() {
        for game in [GSGame.colosseum, .galeOfDarkness, .battleRevolution] {
            let engine = engine(game)
            XCTAssertEqual(
                engine.projectFilename(forEntryNamed: placeholder, filename: "(null).isd",
                                       index: 0, archiveName: "stm_bgm_ev_6brothers"),
                "stm_bgm_ev_6brothers_000.isd",
                "\(game)"
            )
            XCTAssertEqual(
                engine.projectFilename(forEntryNamed: placeholder, filename: "(null).ish",
                                       index: 775, archiveName: "stm_se_nakigoe_archive"),
                "stm_se_nakigoe_archive_775.ish",
                "\(game)"
            )
            // Past three digits the index simply gets longer.
            XCTAssertEqual(
                engine.projectFilename(forEntryNamed: placeholder, filename: "(null).ish",
                                       index: 1234, archiveName: "big"),
                "big_1234.ish",
                "\(game)"
            )
            // A named entry is untouched.
            XCTAssertEqual(
                engine.projectFilename(forEntryNamed: "agent_m_a2", filename: "agent_m_a2.dat",
                                       index: 3, archiveName: "people_archive"),
                "agent_m_a2.dat",
                "\(game)"
            )
        }
    }

    /// The archive's own stem is used, not the language-stripped base the
    /// folder routing works from: stripping made the four language variants
    /// of `battle_disk` produce one set of names.
    func testLanguageVariantsOfAnArchiveProduceDistinctNames() {
        let engine = engine()
        let names = ["battle_disk", "battle_disk_fr", "battle_disk_ge", "battle_disk_it", "battle_disk_sp"]
            .map { engine.projectFilename(forEntryNamed: placeholder, filename: "(null).gtx",
                                          index: 8, archiveName: $0) }
        XCTAssertEqual(Set(names).count, names.count, "language variants collapsed onto one name: \(names)")
    }

    /// A nameless entry can still carry a full filename the packer filled in
    /// — 154 of XD US's do, which is where `00seaside32.ish` comes from — and
    /// that real name has to win over a synthesized one.
    func testAnUnnamedEntryWithAStoredFilenameKeepsIt() throws {
        let engine = engine()
        XCTAssertEqual(
            engine.projectFilename(forEntryNamed: placeholder, filename: "00seaside32.ish",
                                   index: 0, archiveName: "stm_bgm_00seaside32"),
            "00seaside32.ish"
        )

        // End to end: the archive stores the name, the project uses it.
        let entries = [
            FSYSArchive.Entry(
                metadata: .init(name: placeholder, fileType: "ish", identifier: 1, compress: false,
                                includesFullFilename: true, fullFilename: "00seaside32.ish"),
                filename: "00seaside32.ish",
                data: payload("header")
            ),
            FSYSArchive.Entry(
                metadata: .init(name: placeholder, fileType: "isd", identifier: 2, compress: false,
                                includesFullFilename: true, fullFilename: "00seaside32.isd"),
                filename: "00seaside32.isd",
                data: payload("stream")
            ),
        ]
        let archive = FSYSArchive(
            groupID: 0,
            metadata: .init(unknownFlag1: false, unknownFlag2: false, debugFlag: true,
                            unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0),
            entries: entries
        )
        let disc = try makeDisc([("stm_bgm_00seaside32.fsys", try archive.data(groupID: 0, engine: engine))],
                                engine: engine)
        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "stm_bgm_00seaside32.fsys")
        XCTAssertEqual(
            registry.entries.map { File($0.file.path).fileName },
            ["00seaside32.ish", "00seaside32.isd"]
        )
    }

    // MARK: - Unpacking

    /// Two unnamed entries of the same type in one archive are two files, not
    /// one written twice.
    func testUnnamedEntriesInOneArchiveGetTheirOwnFiles() throws {
        let engine = engine()
        let disc = try makeDisc([(
            "stm_se_nakigoe_archive.fsys",
            try archiveBytes([
                entry(name: placeholder, type: "isd", identifier: 1, payload: "first cry"),
                entry(name: placeholder, type: "isd", identifier: 2, payload: "second cry"),
            ], engine: engine)
        )], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "stm_se_nakigoe_archive.fsys")

        XCTAssertEqual(registry.entries.count, 2)
        let paths = registry.entries.map(\.file.path)
        XCTAssertEqual(Set(paths).count, 2, "both entries claimed the same file: \(paths)")
        XCTAssertEqual(
            paths.map { File($0).fileName },
            ["stm_se_nakigoe_archive_000.isd", "stm_se_nakigoe_archive_001.isd"]
        )
        XCTAssertEqual(output.readFile(at: File(paths[0]))?.allData?.rawBytes, payload("first cry").rawBytes)
        XCTAssertEqual(output.readFile(at: File(paths[1]))?.allData?.rawBytes, payload("second cry").rawBytes)
    }

    /// The wider half of the same bug: every archive's unnamed entries used
    /// to share one path across the whole disc, so the last archive unpacked
    /// decided what all of them contained.
    func testUnnamedEntriesInDifferentArchivesDoNotOverwriteEachOther() throws {
        let engine = engine()
        let disc = try makeDisc([
            ("stm_bgm_title.fsys",
             try archiveBytes([entry(name: placeholder, type: "isd", identifier: 1, payload: "title theme")],
                              engine: engine)),
            ("stm_bgm_battle.fsys",
             try archiveBytes([entry(name: placeholder, type: "isd", identifier: 2, payload: "battle theme")],
                              engine: engine)),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let title = try registry(output, forArchive: "stm_bgm_title.fsys")
        let battle = try registry(output, forArchive: "stm_bgm_battle.fsys")

        let titleFile = try XCTUnwrap(title.entries.first?.file)
        let battleFile = try XCTUnwrap(battle.entries.first?.file)
        XCTAssertNotEqual(titleFile.path, battleFile.path)
        XCTAssertEqual(output.readFile(at: titleFile)?.allData?.rawBytes, payload("title theme").rawBytes)
        XCTAssertEqual(output.readFile(at: battleFile)?.allData?.rawBytes, payload("battle theme").rawBytes)
    }

    /// The two halves of a sound are paired by filename stem later on, so an
    /// archive holding exactly one of each has to name them as a pair.
    func testTheTwoHalvesOfALoneSoundShareAStem() throws {
        let engine = engine()
        let disc = try makeDisc([(
            "stm_bgm_ev_6brothers.fsys",
            try archiveBytes([
                entry(name: placeholder, type: "ish", identifier: 8283, payload: "I_SF header"),
                entry(name: placeholder, type: "isd", identifier: 8284, payload: "adpcm stream"),
            ], engine: engine)
        )], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "stm_bgm_ev_6brothers.fsys")
        XCTAssertEqual(
            registry.entries.map { File($0.file.path).fileName },
            ["stm_bgm_ev_6brothers_000.ish", "stm_bgm_ev_6brothers_000.isd"]
        )
    }

    /// An archive holding many sounds pairs each header with the stream its
    /// content confirms (XD's `stm_se_nakigoe_archive`, whose halves don't
    /// run in step), so every pair shares a stem and converts to WAV.
    func testManySoundsInOneArchiveArePairedByContent() throws {
        let engine = engine()
        func isf(_ type: String, _ id: Int, _ data: GoDData) -> FSYSArchive.Entry {
            FSYSArchive.Entry(
                metadata: .init(name: placeholder, fileType: type, identifier: id,
                                compress: false, includesFullFilename: nil),
                filename: "\(placeholder).\(type)", data: data
            )
        }
        let disc = try makeDisc([(
            "stm_se_nakigoe_archive.fsys",
            try archiveBytes([
                isf("ish", 10, ISFPairingTests.header(scales: [0x21, 0x31])),
                isf("ish", 20, ISFPairingTests.header(scales: [0x22, 0x32])),
                isf("ish", 30, ISFPairingTests.header(scales: [0x23, 0x33])),
                isf("isd", 21, ISFPairingTests.stream(scales: [0x22, 0x32])),
                isf("isd", 11, ISFPairingTests.stream(scales: [0x21, 0x31])),
                isf("isd", 31, ISFPairingTests.stream(scales: [0x23, 0x33])),
            ], engine: engine)
        )], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "stm_se_nakigoe_archive.fsys")
        XCTAssertEqual(registry.entries.map { File($0.file.path).fileName }, [
            "stm_se_nakigoe_archive_000.ish",
            "stm_se_nakigoe_archive_001.ish",
            "stm_se_nakigoe_archive_002.ish",
            "stm_se_nakigoe_archive_001.isd",
            "stm_se_nakigoe_archive_000.isd",
            "stm_se_nakigoe_archive_002.isd",
        ])
    }

    /// PBR US stores string table 1 (`mes_common.fsys`) with no file type and
    /// a 3D font typed `fnt`. Both used to be invisible to the operations that
    /// find their files by extension. The project files now take the type
    /// their bytes have, and the archive still rebuilds byte for byte because
    /// the registry keeps the stored type.
    func testFilesWhoseBytesContradictTheirTypeAreNamedByContentAndStillRoundTrip() throws {
        let engine = engine(.battleRevolution)
        var mesg = Array("MESG".utf8) + [0, 0, 0, 1, 0, 0, 0, 1] + Array("USUK".utf8)
        mesg += [UInt8](repeating: 0, count: 16)
        let font3D = Array("F3".utf8) + [0x01, 0xE6] + [UInt8](repeating: 0x11, count: 28)
        func raw(_ type: String?, _ id: Int, _ bytes: [UInt8]) -> FSYSArchive.Entry {
            FSYSArchive.Entry(
                metadata: .init(name: placeholder, fileType: type, identifier: id,
                                compress: false, includesFullFilename: nil),
                filename: "\(placeholder).\(type ?? "bin")",
                data: GoDData(byteStream: bytes, byteOrder: .big)
            )
        }
        let original = try archiveBytes([
            raw(nil, 1, mesg),
            raw("fnt", 2, font3D),
            raw(nil, 3, [1, 2, 3, 4, 5, 6, 7, 8]),
        ], engine: engine)
        let disc = try makeDisc([("mes_common.fsys", original)], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "mes_common.fsys")
        let files = registry.entries.map(\.file)
        XCTAssertEqual(files.map(\.fileType), ["msg", "f3d", "bin"], files.map(\.path).description)
        XCTAssertEqual(registry.entries.map(\.metadata.fileType), [nil, "fnt", nil], "the registry keeps the archive's types")
        XCTAssertEqual(output.readFile(at: files[0])?.allData?.rawBytes, mesg)
        XCTAssertEqual(output.readFile(at: files[1])?.allData?.rawBytes, font3D)

        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))
        try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("mes_common.fsys"))?.allData?.rawBytes,
            original.rawBytes
        )
    }

    /// …but halves whose content can't confirm a pair are left alone:
    /// numbering them in parallel would pair them wrongly. Separate names
    /// keep them unpaired, which is the honest outcome.
    func testManySoundsInOneArchiveAreNotPairedByPosition() throws {
        let engine = engine()
        let disc = try makeDisc([(
            "stm_se_nakigoe_archive.fsys",
            try archiveBytes([
                entry(name: placeholder, type: "ish", identifier: 1, payload: "header one"),
                entry(name: placeholder, type: "ish", identifier: 2, payload: "header two"),
                entry(name: placeholder, type: "isd", identifier: 3, payload: "stream one"),
                entry(name: placeholder, type: "isd", identifier: 4, payload: "stream two"),
            ], engine: engine)
        )], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let registry = try registry(output, forArchive: "stm_se_nakigoe_archive.fsys")
        let names = registry.entries.map { File($0.file.path).fileName }
        XCTAssertEqual(names, [
            "stm_se_nakigoe_archive_000.ish",
            "stm_se_nakigoe_archive_001.ish",
            "stm_se_nakigoe_archive_002.isd",
            "stm_se_nakigoe_archive_003.isd",
        ])
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - Colliding project paths

    /// Two archives whose same-named entries hold the same bytes keep sharing
    /// one file. That is what lets a shared asset be edited in one place, and
    /// it covers the large majority of repeated names on a real disc.
    func testEntriesWithIdenticalBytesShareOneFile() throws {
        let engine = engine()
        let shared = payload("one model, many maps")
        let disc = try makeDisc([
            ("M1_out.fsys", try archiveBytes([
                FSYSArchive.Entry(metadata: .init(name: "sensei_b1", fileType: "dat", identifier: 1,
                                                  compress: false, includesFullFilename: nil),
                                  filename: "sensei_b1.dat", data: shared)
            ], engine: engine)),
            ("M2_out.fsys", try archiveBytes([
                FSYSArchive.Entry(metadata: .init(name: "sensei_b1", fileType: "dat", identifier: 2,
                                                  compress: false, includesFullFilename: nil),
                                  filename: "sensei_b1.dat", data: shared)
            ], engine: engine)),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let first = try XCTUnwrap(try registry(output, forArchive: "M1_out.fsys").entries.first?.file)
        let second = try XCTUnwrap(try registry(output, forArchive: "M2_out.fsys").entries.first?.file)
        XCTAssertEqual(first.path, second.path, "identical payloads should share one file")
        XCTAssertEqual(File(first.path).fileName, "sensei_b1.dat", "and keep the plain name")
    }

    /// Different bytes under one name get a file each. The character models
    /// are the real case: `people_archive` carries its own build of a
    /// character the map archives also ship.
    func testEntriesWithDifferentBytesGetSeparateFiles() throws {
        let engine = engine()
        let disc = try makeDisc([
            ("M1_out.fsys", try archiveBytes([
                entry(name: "hizuki_a1", type: "dat", identifier: 1, payload: "the map's own build")
            ], engine: engine)),
            ("people_archive.fsys", try archiveBytes([
                entry(name: "hizuki_a1", type: "dat", identifier: 2, payload: "the shared library's build")
            ], engine: engine)),
        ], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let map = try XCTUnwrap(try registry(output, forArchive: "M1_out.fsys").entries.first?.file)
        let library = try XCTUnwrap(try registry(output, forArchive: "people_archive.fsys").entries.first?.file)
        XCTAssertNotEqual(map.path, library.path)
        XCTAssertEqual(
            [File(map.path).fileName, File(library.path).fileName].sorted(),
            ["hizuki_a1 (2).dat", "hizuki_a1.dat"]
        )
        XCTAssertEqual(output.readFile(at: map)?.allData?.rawBytes, payload("the map's own build").rawBytes)
        XCTAssertEqual(output.readFile(at: library)?.allData?.rawBytes,
                       payload("the shared library's build").rawBytes)
    }

    /// The case no folder rule can reach: both copies live in one archive, so
    /// there is no other archive to route one of them to.
    func testTwoDifferentEntriesOfOneNameInOneArchiveBothSurvive() throws {
        let engine = engine(.colosseum)
        let disc = try makeDisc([("people_archive.fsys", try archiveBytes([
            entry(name: "agent_m_a2", type: "dat", identifier: 3372, payload: "first build"),
            entry(name: "agent_m_a2", type: "dat", identifier: 3374, payload: "second build"),
        ], engine: engine))], engine: engine)

        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
        let files = try registry(output, forArchive: "people_archive.fsys").entries.map(\.file)
        XCTAssertEqual(files.map { File($0.path).fileName },
                       ["agent_m_a2.dat", "agent_m_a2 (2).dat"])
        XCTAssertEqual(output.readFile(at: files[0])?.allData?.rawBytes, payload("first build").rawBytes)
        XCTAssertEqual(output.readFile(at: files[1])?.allData?.rawBytes, payload("second build").rawBytes)
    }

    /// …and the split survives a repack, which is the point: before this, both
    /// archives were rebuilt from whichever copy happened to be written last.
    func testCollidingEntriesRepackToTheirOwnPayloads() throws {
        let engine = engine()
        let mapBytes = try archiveBytes([
            entry(name: "ball_net", type: "dat", identifier: 1, payload: "small cave build")
        ], engine: engine)
        let libraryBytes = try archiveBytes([
            entry(name: "ball_net", type: "dat", identifier: 2, payload: "the much larger shared build")
        ], engine: engine)
        let disc = try makeDisc([
            ("M2_cave_1F_1.fsys", mapBytes),
            ("people_archive.fsys", libraryBytes),
        ], engine: engine)

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
            built.readFile(at: Folder("/built/files").file("M2_cave_1F_1.fsys"))?.allData?.rawBytes,
            mapBytes.rawBytes
        )
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("people_archive.fsys"))?.allData?.rawBytes,
            libraryBytes.rawBytes
        )
    }

    /// Which copy keeps the plain name comes from the archives' disc paths,
    /// not from the order the host filesystem happened to list them in.
    func testWhichCopyKeepsThePlainNameDoesNotDependOnDiscOrder() throws {
        let engine = engine()
        func dump(_ order: [(path: String, data: GoDData)]) throws -> [String: String] {
            let disc = try makeDisc(order, engine: engine)
            let output = try engine.unpackProject(from: discRoot, fileSystem: disc)
            var result = [String: String]()
            for archive in order {
                let reg = try registry(output, forArchive: archive.path)
                result[archive.path] = File(try XCTUnwrap(reg.entries.first?.file).path).fileName
            }
            return result
        }
        let a = ("A_first.fsys", try archiveBytes([
            entry(name: "shared", type: "dat", identifier: 1, payload: "alpha")], engine: engine))
        let b = ("Z_last.fsys", try archiveBytes([
            entry(name: "shared", type: "dat", identifier: 2, payload: "omega")], engine: engine))
        XCTAssertEqual(try dump([a, b]), try dump([b, a]))
    }

    // MARK: - Group IDs

    /// An archive's group ID comes from the disc's table of contents and
    /// nowhere else. The header's own value disagrees on real discs —
    /// archives carry IDs the table never lists, one is listed despite a
    /// header of 0, one under a different value than its header claims — and
    /// a rebuild corrects the header to what the table says.
    func testGroupIDComesFromTheTableAndCorrectsTheHeader() throws {
        let engine = engine()
        let listedUnderAnother = try archiveBytes([
            entry(name: "a", type: "msg", identifier: 1, payload: "x")
        ], groupID: 0x90C, engine: engine)
        let unlisted = try archiveBytes([
            entry(name: "b", type: "msg", identifier: 2, payload: "y")
        ], groupID: 0x555, engine: engine)
        let listedWithZeroHeader = try archiveBytes([
            entry(name: "c", type: "msg", identifier: 3, payload: "z")
        ], groupID: 0, engine: engine)

        let fst = InMemoryFST()
        // The table stores archive stems, without the `.fsys` extension.
        let toc = FsysTOC(fsysIDsByFilename: [
            "stm_bgm_country": 0x924,     // listed under a value its header doesn't have
            "stm_bgm_windycity": 0x925,   // listed despite a header of 0
        ], unknown: engine.data.toc.unknown)
        try fst.writeFile(try toc.tocData(with: engine),
                          at: discRoot.folder("files").file(engine.data.fsys.GSfsysFile.fileName),
                          overwrite: true)
        for (path, data) in [("stm_bgm_country.fsys", listedUnderAnother),
                             ("DNA_key.fsys", unlisted),
                             ("stm_bgm_windycity.fsys", listedWithZeroHeader)] {
            try fst.writeFile(data, at: discRoot.folder("files").file(path), overwrite: true)
        }

        let output = try engine.unpackProject(from: discRoot, fileSystem: fst)
        func reg(_ name: String) throws -> FSYSRegistry { try registry(output, forArchive: name) }
        XCTAssertEqual(try reg("stm_bgm_country.fsys").groupID, 0x924, "the table's ID, not the header's")
        XCTAssertEqual(try reg("DNA_key.fsys").groupID, 0, "an unlisted archive has no table ID")
        XCTAssertEqual(try reg("stm_bgm_windycity.fsys").groupID, 0x925)

        // Rebuilt headers carry the table's value, correcting the disc's.
        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))
        try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )
        func headerGroupID(_ path: String) throws -> Int {
            let data = try XCTUnwrap(built.readFile(at: Folder("/built/files").file(path))?.allData)
            return try FSYSArchive(data: data, engine: engine).groupID
        }
        XCTAssertEqual(try headerGroupID("stm_bgm_country.fsys"), 0x924, "header corrected from 0x90C")
        XCTAssertEqual(try headerGroupID("stm_bgm_windycity.fsys"), 0x925, "header corrected from 0")
        XCTAssertEqual(try headerGroupID("DNA_key.fsys"), 0, "an unlisted archive's header is cleared")

        // And the rebuilt table lists exactly what the original did.
        let rebuiltTOC = try XCTUnwrap(
            built.readFile(at: Folder("/built/files").file(engine.data.fsys.GSfsysFile.fileName))?.allData
        )
        let parsed = try FsysTOC(tocData: rebuiltTOC, engine: engine)
        XCTAssertEqual(parsed.fsysID(for: "stm_bgm_country"), 0x924)
        XCTAssertEqual(parsed.fsysID(for: "stm_bgm_windycity"), 0x925)
        XCTAssertNil(parsed.fsysID(for: "DNA_key"), "an unlisted archive must not be added")
    }

    /// Whether the header repeats the ID is a per-game convention, not a rule.
    /// Battle Revolution leaves the word zero in all 1,095 archives it ships
    /// and reads the ID from the table, so a rebuild has to leave it zero too
    /// — otherwise every archive on the disc moves off the game's own layout.
    /// The registry and the rebuilt table still carry the real ID.
    func testPBRLeavesTheGroupIDOutOfTheArchiveHeader() throws {
        let engine = engine(.battleRevolution)
        XCTAssertFalse(engine.data.fsys.writesGroupIDInHeaderValue, "PBR must default to omitting it")

        let archive = try archiveBytes([
            entry(name: "a", type: "msg", identifier: 1, payload: "x")
        ], groupID: 0, engine: engine)

        let fst = InMemoryFST()
        let toc = FsysTOC(fsysIDsByFilename: ["menu_common": 0x153a], unknown: engine.data.toc.unknown)
        try fst.writeFile(try toc.tocData(with: engine),
                          at: discRoot.folder("files").file(engine.data.fsys.GSfsysFile.fileName),
                          overwrite: true)
        try fst.writeFile(archive, at: discRoot.folder("files").file("menu_common.fsys"), overwrite: true)

        let output = try engine.unpackProject(from: discRoot, fileSystem: fst)
        XCTAssertEqual(try registry(output, forArchive: "menu_common.fsys").groupID, 0x153a,
                       "the table's ID still reaches the registry")

        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))
        try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )
        let rebuilt = try XCTUnwrap(built.readFile(at: Folder("/built/files").file("menu_common.fsys"))?.allData)
        XCTAssertEqual(try FSYSArchive(data: rebuilt, engine: engine).groupID, 0,
                       "PBR's header keeps its zero")
        XCTAssertEqual(rebuilt.rawBytes, archive.rawBytes, "and the archive repacks byte-identically")

        // The table is where the ID lives, and it still says so.
        let rebuiltTOC = try XCTUnwrap(
            built.readFile(at: Folder("/built/files").file(engine.data.fsys.GSfsysFile.fileName))?.allData
        )
        XCTAssertEqual(try FsysTOC(tocData: rebuiltTOC, engine: engine).fsysID(for: "menu_common"), 0x153a)
    }

    /// The same archive built through the same engine with only the flag
    /// flipped proves the flag is what decides it, rather than something else
    /// about PBR.
    ///
    /// The engine is rebuilt through JSON so the new key's decode is exercised
    /// too, including the shape an engine folder serialized before this
    /// property existed has: no key at all. That decodes rather than failing,
    /// and falls back to the default `true` — so a PBR project dumped before
    /// today keeps writing the ID into its headers until setup is re-run, the
    /// same caveat the other FSYS fixes carry.
    func testTheHeaderGroupIDIsWrittenWhenTheEngineSaysSo() throws {
        let pbr = engine(.battleRevolution)
        let writing = try engineWithGroupIDInHeader(true, basedOn: pbr)
        let legacy = try engineWithGroupIDInHeader(nil, basedOn: pbr)
        XCTAssertTrue(writing.data.fsys.writesGroupIDInHeaderValue)
        XCTAssertNil(legacy.data.fsys.writesGroupIDInHeader, "the key should be absent, not false")
        XCTAssertTrue(legacy.data.fsys.writesGroupIDInHeaderValue,
                      "an engine folder without the key falls back to the default")

        let archive = FSYSArchive(
            groupID: 0,
            metadata: .init(unknownFlag1: false, unknownFlag2: false, debugFlag: false,
                            unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0),
            entries: [entry(name: "a", type: "msg", identifier: 1, payload: "x")]
        )
        let off = try archive.data(groupID: 0x153a, engine: pbr)
        let on = try archive.data(groupID: 0x153a, engine: writing)
        XCTAssertEqual(try FSYSArchive(data: off, engine: pbr).groupID, 0)
        XCTAssertEqual(try FSYSArchive(data: on, engine: pbr).groupID, 0x153a)
        XCTAssertNotEqual(off.rawBytes, on.rawBytes, "the flag has to change the bytes")
    }

    /// An engine whose FSYS data carries the given `writesGroupIDInHeader`,
    /// built by rewriting the serialized form — `nil` removes the key, the way
    /// an engine folder serialized before the property existed looks.
    private func engineWithGroupIDInHeader(
        _ value: Bool?, basedOn base: GeniusSonorityEngine
    ) throws -> GeniusSonorityEngine {
        let source: GeniusSonorityEngine.Data = base.data
        let encoded: Foundation.Data = try JSONEncoder().encode(source)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var fsys = try XCTUnwrap(json["fsys"] as? [String: Any])
        if let value { fsys["writesGroupIDInHeader"] = value } else { fsys["writesGroupIDInHeader"] = nil }
        json["fsys"] = fsys
        let patched: Foundation.Data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(GeniusSonorityEngine.Data.self, from: patched)
        return try GeniusSonorityEngine(data: decoded, enums: base.enums, structs: base.structs)
    }

    // MARK: - Round trip

    func testUnpackThenPackReproducesArchivesWithUnnamedEntries() throws {
        let engine = engine()
        let nakigoe = try archiveBytes([
            entry(name: placeholder, type: "isd", identifier: 1, payload: "first cry"),
            entry(name: placeholder, type: "ish", identifier: 2, payload: "first header"),
            entry(name: placeholder, type: "isd", identifier: 3, payload: "second cry"),
            entry(name: placeholder, type: "ish", identifier: 4, payload: "second header"),
        ], engine: engine)
        let disc = try makeDisc([("stm_se_nakigoe_archive.fsys", nakigoe)], engine: engine)

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
            built.readFile(at: Folder("/built/files").file("stm_se_nakigoe_archive.fsys"))?.allData?.rawBytes,
            nakigoe.rawBytes
        )
    }

    /// Pairing renames streams after their headers; pack reads the names from
    /// the registry, so the archive must still rebuild byte for byte.
    func testUnpackThenPackReproducesAnArchiveWhoseSoundsWerePaired() throws {
        let engine = engine()
        func isf(_ type: String, _ id: Int, _ data: GoDData) -> FSYSArchive.Entry {
            FSYSArchive.Entry(
                metadata: .init(name: placeholder, fileType: type, identifier: id,
                                compress: false, includesFullFilename: nil),
                filename: "\(placeholder).\(type)", data: data
            )
        }
        let nakigoe = try archiveBytes([
            isf("ish", 10, ISFPairingTests.header(scales: [0x21, 0x31])),
            isf("ish", 20, ISFPairingTests.header(scales: [0x22, 0x32])),
            isf("isd", 21, ISFPairingTests.stream(scales: [0x22, 0x32])),
            isf("isd", 11, ISFPairingTests.stream(scales: [0x21, 0x31])),
        ], engine: engine)
        let disc = try makeDisc([("stm_se_nakigoe_archive.fsys", nakigoe)], engine: engine)

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
            built.readFile(at: Folder("/built/files").file("stm_se_nakigoe_archive.fsys"))?.allData?.rawBytes,
            nakigoe.rawBytes
        )
    }

    // MARK: - Writer

    /// Several entries sharing a stored name is normal in these archives, and
    /// the games' own packer gives each one its own copy of the string. The
    /// writer used to key the name table by name, which collapsed the
    /// pointers, so it refused the archive instead of writing it.
    func testEntriesSharingANameEachGetTheirOwnNameString() throws {
        let engine = engine(.colosseum)
        let entries = [
            entry(name: "agent_m_a2", type: "dat", identifier: 3372, payload: "first model"),
            entry(name: "agent_m_a2", type: "dat", identifier: 3374, payload: "second model"),
        ]
        let bytes = try archiveBytes(entries, engine: engine)

        // Each entry points at its own copy of the name.
        let pointers = try filenamePointers(in: bytes)
        XCTAssertEqual(pointers.count, 2)
        XCTAssertNotEqual(pointers[0], pointers[1], "both entries point at one string")
        XCTAssertEqual(occurrences(of: "agent_m_a2", in: bytes), 2, "the name should be stored once per entry")

        // And the archive reads back as two entries with their own payloads.
        let parsed = try FSYSArchive(data: bytes, engine: engine)
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(parsed.entries.map(\.metadata.identifier), [3372, 3374])
        XCTAssertEqual(parsed.entries[0].data.rawBytes, payload("first model").rawBytes)
        XCTAssertEqual(parsed.entries[1].data.rawBytes, payload("second model").rawBytes)
    }

    /// The same for a whole archive of them — XD JP's cry archive stores 776
    /// entries under one name.
    func testAnArchiveOfIdenticallyNamedEntriesRoundTrips() throws {
        let engine = engine()
        let entries = (0 ..< 40).map {
            entry(name: placeholder, type: "isd", identifier: 1000 + $0, payload: "cry \($0)")
        }
        let bytes = try archiveBytes(entries, engine: engine)

        XCTAssertEqual(Set(try filenamePointers(in: bytes)).count, entries.count,
                       "every entry should have its own name pointer")
        let parsed = try FSYSArchive(data: bytes, engine: engine)
        XCTAssertEqual(parsed.entries.count, entries.count)
        for (i, parsedEntry) in parsed.entries.enumerated() {
            XCTAssertEqual(parsedEntry.data.rawBytes, payload("cry \(i)").rawBytes, "entry \(i)")
        }
    }

    // MARK: - Failure reporting

    /// A build works through the whole file system and reports what failed at
    /// the end, rather than stopping at the first bad member and leaving the
    /// rest of the disc as whatever the previous build wrote.
    func testPackWritesEverythingItCanAndReportsEveryFailure() throws {
        let engine = engine()
        let good = try archiveBytes([entry(name: "town", type: "msg", identifier: 1, payload: "hello")],
                                    engine: engine)
        let disc = try makeDisc([("good.fsys", good)], engine: engine)
        let output = try engine.unpackProject(from: discRoot, fileSystem: disc)

        let built = InMemoryFST()
        try copyTree(output, into: built, at: Folder("/project"))

        // Add two binary members whose bytes aren't in the project, so they
        // can't be packed, either side of the archive that can.
        let existing: FSTRegistry = try built.decodeJSON(from: Folder("/project").file("FST.json"))
        let missing = [
            FSTRegistry.Entry(type: .binary, file: Folder("/Assets/Misc").file("gone.bin"), discPath: "gone.bin"),
            FSTRegistry.Entry(type: .binary, file: Folder("/Assets/Misc").file("also_gone.bin"), discPath: "also_gone.bin"),
        ]
        try built.writeJSON(
            FSTRegistry(entries: [missing[0]] + existing.entries + [missing[1]]),
            at: Folder("/project").file("FST.json"),
            overwrite: true
        )

        var reported: String?
        XCTAssertThrowsError(try engine.packProject(
            fstRegistryFile: Folder("/project").file("FST.json"),
            outputFolder: Folder("/built"),
            overwrite: true,
            fileSystem: built
        )) { error in
            reported = "\(error)"
        }

        let message = try XCTUnwrap(reported)
        XCTAssertTrue(message.contains("gone.bin"), "the first failure should be named: \(message)")
        XCTAssertTrue(message.contains("also_gone.bin"), "the last failure should be named: \(message)")
        XCTAssertTrue(message.contains("2 files"), "the count should be reported: \(message)")

        // The archive between them was still written, as was the table of
        // contents that comes after both.
        XCTAssertEqual(
            built.readFile(at: Folder("/built/files").file("good.fsys"))?.allData?.rawBytes,
            good.rawBytes
        )
        XCTAssertNotNil(
            built.readFile(at: Folder("/built/files").file(engine.data.fsys.GSfsysFile.fileName)),
            "GSfsys.toc should still be rebuilt"
        )
    }

    // MARK: - Helpers

    /// Reads each entry's `filename_pointer` out of a serialized archive, via
    /// the header's offset table — independent of the writer's bookkeeping.
    private func filenamePointers(in archive: GoDData) throws -> [Int] {
        let bytes = archive.rawBytes
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        let count = u32(0x0C)
        let offsetTable = u32(0x40)
        return (0 ..< count).map { u32(u32(offsetTable + 4 * $0) + 0x24) }
    }

    private func occurrences(of needle: String, in archive: GoDData) -> Int {
        let bytes = archive.rawBytes
        let pattern = Array(needle.utf8)
        guard bytes.count >= pattern.count else { return 0 }
        var found = 0
        for start in 0 ... (bytes.count - pattern.count)
        where Array(bytes[start ..< start + pattern.count]) == pattern {
            found += 1
        }
        return found
    }

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
