//
//  DolLayoutCorpusTests.swift
//  GODOpsTests
//
//  A DOL rebuilt from an unedited disassembly must keep its layout: the same
//  total length and the same section table, so every symbol stays where the
//  symbol map says it is. That is the guarantee the second dump of a project
//  depends on — see CLAUDE.md, "A rebuilt DOL keeps its layout" — and it
//  cannot be proved on a synthetic DOL, because what broke it on real discs
//  was the writers: an embedded texture cut short of its palette, a message
//  table cut short of its strings.
//
//  Skips cleanly without a project, so it's safe on a machine with no ROMs.
//  GODDESS_DOL_CORPUS points at a project folder holding
//  Build/Contents/sys/main.dol.
//
//  Slow in a debug build — 4.3 MB is roughly a million instructions to
//  decode. Run it with `swift test -c release --filter DolLayoutCorpus`.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Dolphin
import Disassembler
import XD
import GeniusSonority
import Pokemon
@testable import GODOps

final class DolLayoutCorpusTests: XCTestCase {

    private var projectRoot: String {
        ProcessInfo.processInfo.environment["GODDESS_DOL_CORPUS"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project"
    }

    private var scratch: Folder {
        Folder(NSTemporaryDirectory()).folder("goddess-dol-layout-corpus")
    }

    func testARebuiltDolKeepsItsSizeAndSectionTable() throws {
        let fileSystem = FileSystem.shared
        let dolPath = Folder(projectRoot).folder("Build").folder("Contents").folder("sys").file("main.dol")
        guard let originalData = fileSystem.readFile(at: dolPath)?.allData else {
            throw XCTSkip("No DOL at \(dolPath.path) — set GODDESS_DOL_CORPUS to a project folder.")
        }

        try? fileSystem.deleteFolder(at: scratch)
        let engines = try installDolCorpusEngines(
            forProjectAt: Folder(projectRoot), under: scratch, in: fileSystem
        )
        // Unwrapped rather than tolerated: disassembling without them is a
        // weaker run that still passes, which is how the symbol-map
        // assertions below went unreached.
        let typeMapPath = try XCTUnwrap(engines.typeMap, "XD engine ships no DOL type map")
        let symbolMapPath = try XCTUnwrap(engines.symbolMap, "XD engine ships no DOL symbol map for \(engines.gameID)")
        print("[DOL layout corpus] \(engines.gameID) maps installed")

        let outputFolder = scratch.folder("Disassembly")
        try DolDisassembly.disassemble(
            config: .init(
                dolPath: dolPath,
                outputFolder: outputFolder,
                symbolMapPath: symbolMapPath,
                dolphinEngine: engines.dolphin,
                typeMapPath: typeMapPath,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: SilentLogger()
        )

        // No `allowResizedChunks`: a chunk that rebuilds longer than it was
        // dumped at should stop the assembly and name itself, which is a
        // more useful failure than a size assertion further down.
        let rebuiltPath = scratch.file("rebuilt.dol")
        let rebuiltMapPath = scratch.file("rebuilt.map")
        try DolAssembly.assemble(
            config: .init(
                codeFolder: outputFolder.folder(DolDisassembler.outputFolderName(for: dolPath)),
                outputDolPath: rebuiltPath,
                symbolMapPath: symbolMapPath,
                outputSymbolMapPath: rebuiltMapPath,
                dolphinEngine: engines.dolphin,
                typeMapPath: typeMapPath,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: SilentLogger()
        )

        let rebuiltData = try XCTUnwrap(fileSystem.readFile(at: rebuiltPath)?.allData)
        XCTAssertEqual(
            rebuiltData.length, originalData.length,
            "a rebuilt DOL that changes size has moved symbols the maps still address by their old values"
        )

        let dolphinEngine = try DolphinEngine(from: engines.dolphin, in: fileSystem)
        let original = try Dol(data: originalData, dolphinEngine: dolphinEngine)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: dolphinEngine)

        XCTAssertEqual(rebuilt.textSections.count, original.textSections.count)
        XCTAssertEqual(rebuilt.dataSections.count, original.dataSections.count)
        for (index, section) in original.textSections.enumerated() where index < rebuilt.textSections.count {
            XCTAssertEqual(rebuilt.textSections[index].RAMAddress, section.RAMAddress, "text\(index) address")
            XCTAssertEqual(rebuilt.textSections[index].assembly.length, section.assembly.length, "text\(index) size")
        }
        for (index, section) in original.dataSections.enumerated() where index < rebuilt.dataSections.count {
            XCTAssertEqual(rebuilt.dataSections[index].RAMAddress, section.RAMAddress, "data\(index) address")
            XCTAssertEqual(rebuilt.dataSections[index].data.length, section.data.length, "data\(index) size")
        }

        // The rewritten map is what the next dump reads; every name in the
        // input has to survive it, or a type-map chunk stops resolving.
        //
        // Both sides are compared as `SymbolMapParser` sees them, which is
        // the only comparison that means anything: the parser sanitizes each
        // name (`@`, `<`, `>` become `_`) and suffixes a repeated name with
        // its address, so the file on disk and the names the tool works with
        // are deliberately not the same strings.
        let inputMap = try XCTUnwrap(fileSystem.readFile(at: symbolMapPath)?.allData)
        let outputMap = try XCTUnwrap(
            fileSystem.readFile(at: rebuiltMapPath)?.allData,
            "the assembly wrote no symbol map"
        )
        let parser = SymbolMapParser()
        let before = parser.parse(inputMap.string(format: .utf8))
        let after = parser.parse(outputMap.string(format: .utf8))
        let afterByName = Dictionary(after.map { ($0.name, $0.address) }, uniquingKeysWith: { a, _ in a })
        let lost = before.filter { afterByName[$0.name] == nil }
        let moved = before.filter { symbol in
            guard let address = afterByName[symbol.name] else { return false }
            return address != symbol.address
        }
        XCTAssertTrue(lost.isEmpty, "\(lost.count) symbols dropped, e.g. \(lost.prefix(3).map(\.name))")
        XCTAssertTrue(
            moved.isEmpty,
            "nothing shifted, so nothing should have moved: \(moved.prefix(3).map(\.name))"
        )
        XCTAssertGreaterThan(
            after.count, before.count,
            "the data-section chunk labels a type map names should be added to the map"
        )
        print("""
        [DOL layout corpus] symbol map: \(before.count) in, \(after.count) out, \
        \(moved.count) moved, \(lost.count) lost, \(after.count - before.count + lost.count) added
        """)

        try? fileSystem.deleteFolder(at: scratch)
    }
}
