//
//  AssetBatchLayoutTests.swift
//  GODOpsTests
//
//  The batch asset operations, exercised as a pair.
//
//  Each direction was already covered on its own, which is exactly why the
//  two could disagree about where a rebuilt file goes and nothing noticed:
//  `dumpFlashMenus` nests a folder per menu, and `buildFlashMenus` mirrored
//  that folder into the output too, so the rebuilt `.gsw` landed one level
//  below the game-side file it was meant to replace. On XD PAL that put 167
//  of 168 menus somewhere the packer never looks, with the run reporting
//  success. These tests assert the round trip lands on the input's own path.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import FixtureCatalog
import TestSupport
@testable import GODOps

final class AssetBatchLayoutTests: XCTestCase {

    /// Where the FSYS unpack leaves `.gsw` files, language subfolders and all.
    private let menusFolder = Folder("/project/Unpacked/Flash Menus")
    private let menusSource = Folder("/project/Source/Menus")

    private let atxFolder = Folder("/project/Unpacked/Images/Misc")
    private let atxSource = Folder("/project/Source/ATX")

    // MARK: - Flash menus

    func testFlashMenuBatchRebuildsOverTheFileItWasDumpedFrom() throws {
        let fst = InMemoryFST()
        let gsw = try readerCanonicalized(GSWFixtures.model())
        let bytes = try XCTUnwrap(gsw.binaries.first).data

        // One at the root and one in a language subfolder, because the layout
        // has to survive the mirrored folder as well as the per-menu one.
        let root = menusFolder.file("\(GSWFixtures.name).gsw")
        let nested = menusFolder.folder("French").file("\(GSWFixtures.name).gsw")
        try fst.writeFile(bytes, at: root, overwrite: true)
        try fst.writeFile(bytes, at: nested, overwrite: true)

        try runDump(.dumpFlashMenus(
            flashMenusFolder: menusFolder, outputFolder: menusSource, overwrite: true
        ), on: fst)

        // The dump nests: <source>/[<language>/]<menu>/<menu>.gsw.json
        XCTAssertNotNil(
            fst.readFile(at: menusSource.folder(GSWFixtures.name).file("\(GSWFixtures.name).gsw.json")),
            "expected a per-menu project folder at the source root"
        )
        XCTAssertNotNil(
            fst.readFile(at: menusSource.folder("French").folder(GSWFixtures.name)
                .file("\(GSWFixtures.name).gsw.json")),
            "expected a per-menu project folder under the language folder"
        )

        // Blank both game-side files so "did the build reach them" is unambiguous.
        try fst.writeFile(GoDData(byteStream: [0], byteOrder: .big), at: root, overwrite: true)
        try fst.writeFile(GoDData(byteStream: [0], byteOrder: .big), at: nested, overwrite: true)

        try runBuild(.buildFlashMenus(
            projectsFolder: menusSource, outputFolder: menusFolder, overwrite: true
        ), on: fst)

        for target in [root, nested] {
            let rebuilt = try XCTUnwrap(
                fst.readFile(at: target)?.allData,
                "nothing rebuilt at \(target.path)"
            )
            XCTAssertEqual(rebuilt.rawBytes, bytes.rawBytes, "rebuilt \(target.path) differs")
        }

        // And nothing was left in a folder the packer never reads.
        XCTAssertNil(
            fst.readFile(at: menusFolder.folder(GSWFixtures.name).file("\(GSWFixtures.name).gsw")),
            "the build wrote into a per-menu subfolder instead of over the game-side file"
        )
        XCTAssertNil(
            fst.readFile(at: menusFolder.folder("French").folder(GSWFixtures.name)
                .file("\(GSWFixtures.name).gsw")),
            "the build wrote into a per-menu subfolder instead of over the game-side file"
        )
    }

    // MARK: - ATX

    func testATXBatchRebuildsOverTheFileItWasDumpedFrom() throws {
        let fst = InMemoryFST()
        let atx = try readerCanonicalized(ATXFixtures.model())
        let bytes = try XCTUnwrap(atx.binaries.first).data
        let target = atxFolder.file("\(ATXFixtures.name).atx")
        try fst.writeFile(bytes, at: target, overwrite: true)

        try runDump(.dumpATXs(atxFolder: atxFolder, outputFolder: atxSource, overwrite: true), on: fst)
        XCTAssertNotNil(
            fst.readFile(at: atxSource.folder(ATXFixtures.name).file("\(ATXFixtures.name).atx.json")),
            "expected a per-texture project folder"
        )

        try fst.writeFile(GoDData(byteStream: [0], byteOrder: .big), at: target, overwrite: true)
        try runBuild(.buildATXs(jsonFolder: atxSource, outputFolder: atxFolder, overwrite: true), on: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: target)?.allData, "nothing rebuilt at \(target.path)")
        XCTAssertEqual(rebuilt.rawBytes, bytes.rawBytes)
        XCTAssertNil(
            fst.readFile(at: atxFolder.folder(ATXFixtures.name).file("\(ATXFixtures.name).atx")),
            "the build wrote into a per-texture subfolder instead of over the game-side file"
        )
    }

    // MARK: - Helpers

    private func runDump(_ op: ColoXD.DumpConfig.Operations, on fst: InMemoryFST) throws {
        try ColoXD.dump(
            config: ColoXD.DumpConfig(operations: [OperationConfig(operation: op, enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
    }

    private func runBuild(_ op: ColoXD.BuildConfig.Operations, on fst: InMemoryFST) throws {
        try ColoXD.build(
            config: ColoXD.BuildConfig(operations: [OperationConfig(operation: op, enabled: .yes)]),
            settings: .default, fileSystem: fst, logger: SilentLogger()
        )
    }
}
