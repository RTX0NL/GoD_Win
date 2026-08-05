//
//  DolTableCSVCorpusTests.swift
//  GODOpsTests
//
//  Struct tables dump as CSV and must rebuild from it byte-exactly (see
//  CLAUDE.md, "Struct tables as CSV"). The synthetic tests prove the codec;
//  this proves it against a real executable — XD's 4.3 MB `main.dol` and the
//  13 tables its bundled type map declares, ranging from 58 to 1019 entries
//  over structs with enum, string and pointer fields.
//
//  Skips cleanly when the unpacked project isn't present, so it's safe to
//  keep in the suite on a machine without ROMs. Point it elsewhere with
//  GODDESS_DOL_CORPUS (a project folder holding Build/Contents/sys/main.dol).
//
//  Slow in a debug build — 4.3 MB is roughly a million instructions to
//  decode. Run it with `swift test -c release --filter DolTableCSVCorpus`.
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

final class DolTableCSVCorpusTests: XCTestCase {

    private var projectRoot: String {
        ProcessInfo.processInfo.environment["GODDESS_DOL_CORPUS"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project"
    }

    private var scratch: Folder {
        Folder(NSTemporaryDirectory()).folder("goddess-dol-csv-corpus")
    }

    /// Installs engines from code rather than reading the project's own
    /// folder: a project dumped before an engine gained a definition has a
    /// stale copy on disk (the XD project's `Enumerations/` is empty), and
    /// this is meant to exercise the current definitions.
    ///
    /// Returns the type-map resolution list — game engine first, then the
    /// shared sets it references — plus the Dolphin folder separately.
    private func installEngines(
        in fileSystem: FileSystemTree
    ) throws -> (dolphin: Folder, typedData: [Folder]) {
        let folder = scratch.folder("Engines")
        let dolphin = try DolphinEngine.defaults()
        let xd = try XDEngine.defaults()
        let gs = GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness)
        let pokemon = try PokemonEngine.defaults()
        for engine in [dolphin as any Engine, xd as any Engine, gs as any Engine, pokemon as any Engine] {
            try engine.write(to: fileSystem, in: folder, overwrite: true)
        }
        return (
            dolphin: folder.folder(dolphin.name),
            typedData: [folder.folder(xd.name), folder.folder(gs.name), folder.folder(pokemon.name)]
        )
    }

    private func tableNames(inTypeMapAt path: File, in fileSystem: FileSystemTree) throws -> [String] {
        guard let data = fileSystem.readFile(at: path)?.allData else { return [] }
        let typeMap = try JSONDecoder().decode(TypeMap.self, from: data)
        return typeMap.chunks.compactMap {
            if case .table(let table) = $0 { return table.name }
            return nil
        }
    }

    /// Every chunk of every data-section manifest under `codeFolder`.
    private func chunks(
        under codeFolder: Folder,
        in fileSystem: FileSystemTree
    ) -> [DataSectionManifest.Chunk] {
        guard let contents = fileSystem.inspectFolder(at: codeFolder) else { return [] }
        return contents.subFolders.flatMap { section -> [DataSectionManifest.Chunk] in
            guard let data = fileSystem.readFile(at: section.file("manifest.json"))?.allData,
                  let manifest = try? JSONDecoder().decode(DataSectionManifest.self, from: data)
            else { return [] }
            return manifest.chunks
        }
    }

    func testXDDolTablesDumpAsCSVAndRebuildByteExactly() throws {
        let fileSystem = FileSystem.shared
        let dolPath = Folder(projectRoot).folder("Build").folder("Contents").folder("sys").file("main.dol")
        guard let originalDol = fileSystem.readFile(at: dolPath)?.allData else {
            throw XCTSkip("No DOL at \(dolPath.path) — set GODDESS_DOL_CORPUS to a project folder.")
        }

        try? fileSystem.deleteFolder(at: scratch)
        let engines = try installEngines(in: fileSystem)

        // Type map and symbol map ship with the engine, so read them from the
        // freshly written folder rather than the project's stale copy.
        let typeMapPath = engines.typedData[0].file("Resources/dol_typemap.json")
        let symbolMapPath = engines.typedData[0].file("Resources/GXXE.map")
        guard fileSystem.inspectFile(at: typeMapPath) != nil else {
            throw XCTSkip("XD engine ships no dol_typemap.json")
        }
        let declaredTables = try tableNames(inTypeMapAt: typeMapPath, in: fileSystem)
        XCTAssertFalse(declaredTables.isEmpty, "type map declares no tables — nothing to measure")

        let outputFolder = scratch.folder("Disassembly")
        try DolDisassembly.disassemble(
            config: .init(
                dolPath: dolPath,
                outputFolder: outputFolder,
                symbolMapPath: fileSystem.inspectFile(at: symbolMapPath) != nil ? symbolMapPath : nil,
                dolphinEngine: engines.dolphin,
                typeMapPath: typeMapPath,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: SilentLogger()
        )

        let codeFolder = outputFolder.folder(DolDisassembler.outputFolderName(for: dolPath))
        let allChunks = chunks(under: codeFolder, in: fileSystem)
        let tableChunks = allChunks.filter { $0.type == .table }
        let csvNames = Set(tableChunks.map { $0.file.replacingOccurrences(of: ".csv", with: "") })

        // Which declared tables made it, and which fell back to raw bytes.
        let dumped = declaredTables.filter { csvNames.contains($0) }
        let demoted = declaredTables.filter { !csvNames.contains($0) }
        print("""
        [DOL CSV corpus] \(dumped.count)/\(declaredTables.count) declared tables dumped as CSV.
          dumped:  \(dumped.sorted().joined(separator: ", "))
          missing: \(demoted.sorted().joined(separator: ", "))
        """)

        // Every table chunk must be a CSV — nothing else writes that type.
        for chunk in tableChunks {
            XCTAssertTrue(chunk.file.hasSuffix(".csv"), "table chunk '\(chunk.label)' wrote \(chunk.file)")
        }

        // Report the shape of one real table so a regression in the format is
        // visible in the log, not just in a byte diff.
        if let sample = tableChunks.max(by: { ($0.count ?? 0) < ($1.count ?? 0) }),
           let sectionFolder = fileSystem.inspectFolder(at: codeFolder)?.subFolders.first(where: {
               fileSystem.inspectFile(at: $0.file(sample.file)) != nil
           }),
           let csv = fileSystem.readFile(at: sectionFolder.file(sample.file))?.allData {
            let lines = csv.string(format: .utf8).split(separator: "\n").prefix(3)
            print("""
            [DOL CSV corpus] largest table '\(sample.label)' (\(sample.count ?? 0) entries, \(sample.structType ?? "?")):
            \(lines.joined(separator: "\n"))
            """)
        }

        // Every table must decode back to exactly the bytes it was read from.
        //
        // Compared against the *original* DOL at each table's own address,
        // rather than against a rebuilt section, because XD's DOL does not
        // rebuild byte-identically and never has: its three embedded MSGs
        // re-encode larger (CLAUDE.md, MSG bullet) and every pointer past
        // them legitimately shifts. That divergence has nothing to do with
        // tables — it shows up in `data4` and `data6`, which contain none.
        // Asserting on whole sections would measure the MSG writer, not this.
        let dolphinEngine = try DolphinEngine.defaults()
        let original = try Dol(data: originalDol, dolphinEngine: dolphinEngine)
        let engine = try GenericEngine(combining: engines.typedData, in: fileSystem)

        let sectionFolders = fileSystem.inspectFolder(at: codeFolder)?.subFolders ?? []

        var checked = 0
        for chunk in tableChunks {
            guard let structType = chunk.structType,
                  let definition = try? engine.getStruct(structType) as StructDefinition,
                  let count = chunk.count
            else {
                XCTFail("table '\(chunk.label)' has no resolvable struct type")
                continue
            }
            // Auto labels carry their address; anything else can't be located
            // without the disassembler's own symbol table.
            guard chunk.label.hasPrefix("lbl_"),
                  let address = UInt32(chunk.label.dropFirst(4), radix: 16)
            else { continue }
            guard let section = original.dataSections.first(where: {
                address >= $0.RAMAddress && address < $0.RAMAddress + UInt32($0.data.length)
            }) else {
                XCTFail("table '\(chunk.label)' is outside every data section")
                continue
            }

            let offset = Int(address - section.RAMAddress)
            let length = definition.length * count
            guard offset + length <= section.data.length else {
                XCTFail("table '\(chunk.label)' runs past the end of its section")
                continue
            }
            var expected = section.data.rawBytes[offset ..< (offset + length)].map { $0 }

            guard let sectionFolder = sectionFolders.first(where: {
                      fileSystem.inspectFile(at: $0.file(chunk.file)) != nil
                  }),
                  let csv = fileSystem.readFile(at: sectionFolder.file(chunk.file))?.allData
            else {
                XCTFail("no CSV on disk for '\(chunk.label)'")
                continue
            }
            let decoded = try StructTableCSV.decode(
                csv.string(format: .utf8), definition: definition, byteOrder: .big
            )
            XCTAssertEqual(decoded.entries.count, count, "'\(chunk.label)' lost rows")
            var actual = decoded.entries.flatMap { $0.data.rawBytes }

            // Pointer fields are re-derived from the label table at assembly
            // time — they are zero on the way back in and are *meant* to move
            // when the layout does. The names are what has to survive, and
            // the dump's own verify step already compares those.
            let labelOffsets = StructCSVSchema.columns(of: definition)
                .filter { $0.labelKey != nil }
                .map(\.offset)
            if !labelOffsets.isEmpty {
                for entryIndex in 0 ..< min(count, decoded.entries.count) {
                    for column in labelOffsets {
                        let base = entryIndex * definition.length + column
                        for byte in base ..< min(base + 4, expected.count) {
                            expected[byte] = 0
                            actual[byte] = 0
                        }
                    }
                }
            }

            XCTAssertEqual(
                actual, expected,
                "'\(chunk.label)' (\(count)×\(structType)) did not round-trip through CSV"
            )
            checked += 1
        }
        print("[DOL CSV corpus] \(checked) tables verified byte-exact against the original DOL.")
        XCTAssertEqual(checked, declaredTables.count, "not every declared table was verified")

        // The assemble path still has to run end to end, even though its
        // output isn't byte-identical for XD.
        let rebuiltPath = scratch.file("rebuilt.dol")
        try DolAssembly.assemble(
            config: .init(
                codeFolder: codeFolder,
                outputDolPath: rebuiltPath,
                symbolMapPath: fileSystem.inspectFile(at: symbolMapPath) != nil ? symbolMapPath : nil,
                dolphinEngine: engines.dolphin,
                typeMapPath: typeMapPath,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: SilentLogger()
        )
        let rebuilt = try XCTUnwrap(fileSystem.readFile(at: rebuiltPath)?.allData)
        let after = try Dol(data: rebuilt, dolphinEngine: dolphinEngine)
        XCTAssertEqual(after.dataSections.count, original.dataSections.count, "data section count changed")
        print("[DOL CSV corpus] rebuilt DOL: \(rebuilt.length) bytes vs \(originalDol.length) original.")
    }
}
