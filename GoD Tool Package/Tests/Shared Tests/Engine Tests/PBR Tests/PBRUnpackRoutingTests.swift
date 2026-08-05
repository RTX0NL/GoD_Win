//
//  PBRUnpackRoutingTests.swift
//  PBRTests
//
//  Checks the PBR-specific FSYS routing/naming the `.battleRevolution` engine
//  configures: per-archive subfolders (pkx/wzx/bf), textures kept raw in model
//  archives but decoded to PNG in image archives, decks split by type under
//  Data, common bin routed to Data/Common, and "(null)" entries named by
//  archive + index. Runs `processFsys` on individual real archives so it's
//  fast. Skips without the unpacked disc.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
@testable import GeniusSonority

final class PBRUnpackRoutingTests: XCTestCase {

    private var filesFolder: String? {
        let path = ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func setUpFixtures() throws -> (engine: GeniusSonorityEngine, toc: FsysTOC, folder: String) {
        guard let folder = filesFolder else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let engine = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let tocPath = folder + "/GSfsys.toc"
        let toc = try FsysTOC(
            tocData: GoDData(data: try XCTUnwrap(FileManager.default.contents(atPath: tocPath)), byteOrder: .big),
            engine: engine
        )
        return (engine, toc, folder)
    }

    private func process(_ name: String, _ ctx: (engine: GeniusSonorityEngine, toc: FsysTOC, folder: String)) throws -> GeniusSonorityEngine.FsysResult? {
        guard let bytes = FileManager.default.contents(atPath: ctx.folder + "/" + name) else { return nil }
        return try ctx.engine.processFsys(
            data: GoDData(data: bytes, byteOrder: .big),
            fileName: name, discPath: name, toc: ctx.toc
        )
    }

    private func paths(_ r: GeniusSonorityEngine.FsysResult) -> [String] {
        r.extractedFiles.map(\.file.path)
    }

    /// A Pokémon model archive groups into `/Assets/Models/Pokemon/<num>` with
    /// the `pkx_` prefix stripped, keeps its textures raw, and names its
    /// "(null)" entries by archive + index.
    func testPkxGroupsPerArchiveAndKeepsTexturesRaw() throws {
        let ctx = try setUpFixtures()
        let r = try XCTUnwrap(try process("pkx_025.fsys", ctx), "pkx_025.fsys missing")
        let files = paths(r)
        XCTAssertFalse(files.isEmpty)
        for path in files {
            XCTAssertTrue(path.hasPrefix("/Assets/Models/Pokemon/025/"), "unexpected \(path)")
        }
        XCTAssertFalse(files.contains { $0.hasSuffix(".png") }, "model textures must stay raw")
        XCTAssertTrue(files.contains { $0.contains("/pkx_025_0000.") }, "index-based naming")
    }

    /// A move-effect archive groups into `/Assets/Effects/Moves/<idx>`.
    func testWzxWazaGroupsPerArchive() throws {
        let ctx = try setUpFixtures()
        let r = try XCTUnwrap(try process("wzx_waza_059.fsys", ctx))
        for path in paths(r) {
            XCTAssertTrue(path.hasPrefix("/Assets/Effects/Moves/059/"), "unexpected \(path)")
        }
    }

    /// Pokémon face icons decode to PNG under the images tree.
    func testMenuFaceImagesConvertToPng() throws {
        let ctx = try setUpFixtures()
        let r = try XCTUnwrap(try process("menu_face.fsys", ctx))
        let files = paths(r)
        XCTAssertFalse(files.isEmpty)
        for path in files {
            XCTAssertTrue(path.hasPrefix("/Assets/Images/Pokemon/Faces/"), "unexpected \(path)")
            XCTAssertTrue(path.hasSuffix(".png"), "image archive must convert to png: \(path)")
        }
    }

    /// Decks split by type into separate Data subfolders.
    func testDecksSplitByTypeUnderData() throws {
        let ctx = try setUpFixtures()
        let r = try XCTUnwrap(try process("deck.fsys", ctx))
        let files = paths(r)
        XCTAssertTrue(files.contains { $0.hasPrefix("/Data/Decks/Pokemon/") }, "dckp → Data/Decks/Pokemon")
        XCTAssertTrue(files.contains { $0.hasPrefix("/Data/Decks/Trainer/") }, "dckt → Data/Decks/Trainer")
        XCTAssertTrue(files.contains { $0.hasPrefix("/Data/Decks/AI/") }, "dcka → Data/Decks/AI")
    }

    /// Messages sort into per-language folders read from the MESG binary,
    /// directly under Messages (no Misc subfolder).
    func testMessagesSortByLanguage() throws {
        let ctx = try setUpFixtures()
        let en = try XCTUnwrap(try process("menu_btutorial.fsys", ctx))
        XCTAssertTrue(paths(en).contains { $0.hasPrefix("/Data/Text/Messages/English/") && $0.hasSuffix(".msg") },
                      "English MESG → Messages/English")
        XCTAssertFalse(paths(en).contains { $0.contains("/Messages/Misc/") }, "no Misc subfolder")

        let fr = try XCTUnwrap(try process("menu_btutorial_f.fsys", ctx))
        XCTAssertTrue(paths(fr).contains { $0.hasPrefix("/Data/Text/Messages/French/") },
                      "French MESG → Messages/French")
    }

    /// common.fsys: bin data tables route to Data/Common; its textures still
    /// decode to PNG (it's not a model archive).
    func testCommonBinRoutesToDataCommon() throws {
        let ctx = try setUpFixtures()
        let r = try XCTUnwrap(try process("common.fsys", ctx))
        let files = paths(r)
        let binFiles = files.filter { $0.hasPrefix("/Data/Common/") }
        XCTAssertEqual(binFiles.count, 33, "33 bin data tables → Data/Common")
        XCTAssertTrue(files.contains { $0.hasSuffix(".png") }, "common textures decode to png")
    }
}
