//
//  DolTableCSVCorpusTests.swift
//  GODOpsTests
//
//  The data tables both games keep in `main.dol` — abilities, TMs, status
//  effects, menu sprites, the PKX/WZX model references, and for Colosseum
//  also items, types and the script builtin dispatch table — dump as CSV
//  only when their struct tiles the real table and the type map names the
//  address a label actually lands on. A type-map chunk whose address has no
//  label is skipped in silence, so "this region has no tables" and "this
//  region's addresses are four bytes out" look identical from the outside;
//  that is exactly what this test is here to tell apart.
//
//  The dump verifies each CSV byte-for-byte against the table before writing
//  it, so a table that appears as CSV has already round-tripped. What is
//  asserted on top is that it came out at the row count the map declares —
//  a wrong start address can still round-trip while describing the wrong
//  bytes — plus a couple of known values per game, which is what catches a
//  table that is structurally fine and positionally wrong.
//
//  Skips cleanly without a project. GODDESS_DOL_TABLE_CORPUS (XD) and
//  GODDESS_COLO_DOL_TABLE_CORPUS (Colosseum) each point at a project folder
//  holding Build/Contents/sys/main.dol and Build/Contents/sys/boot.bin, which
//  names the region and so the maps to use.
//
//  Slow in a debug build. Run it with
//  `swift test -c release --filter DolTableCSVCorpus`.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Dolphin
import Disassembler
import XD
import Colosseum
import GeniusSonority
import Pokemon
@testable import GODOps

final class DolTableCSVCorpusTests: XCTestCase {

    /// One game's corpus: where the project is, which engines resolve its
    /// tables, and how its region-keyed DOL resources are found.
    private struct Corpus {
        let label: String
        let projectRoot: String
        let gameEngine: any Engine
        let gsGame: GSGame
        let gameIDs: [String]
        let fallbackGameID: String
        let typeMap: (String) -> GoDData?
        let symbolMap: (String) -> GoDData?
        /// `(table, column, row, value)` — a cell whose value is known from
        /// the game itself, checked after the structural assertions.
        let spotChecks: [(table: String, column: String, row: Int, value: String)]
    }

    private var scratch: Folder {
        Folder(nativePath: NSTemporaryDirectory()).folder("goddess-dol-table-csv-corpus")
    }

    private func env(_ key: String, default value: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? value
    }

    private func xdCorpus() throws -> Corpus {
        Corpus(
            label: "XD",
            projectRoot: env("GODDESS_DOL_TABLE_CORPUS", default: "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project"),
            gameEngine: try XDEngine.defaults(),
            gsGame: .galeOfDarkness,
            gameIDs: PokemonXD.gameIDs,
            fallbackGameID: PokemonXD.gameIDUS,
            typeMap: { PokemonXD.dolTypeMapData(for: $0) },
            symbolMap: { PokemonXD.symbolMapData(for: $0) },
            spotChecks: [
                // Ability 1 is Stench, whose name is message 3101 in both
                // games — the join that generated the shared ability enum.
                (table: "Abilities", column: "name_id", row: 1, value: "3101"),
                (table: "TMs", column: "move_id", row: 0, value: "FOCUSPUNCH"),
            ]
        )
    }

    private func colosseumCorpus() throws -> Corpus {
        Corpus(
            label: "Colosseum",
            projectRoot: env("GODDESS_COLO_DOL_TABLE_CORPUS", default: "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project"),
            gameEngine: try ColosseumEngine.defaults(),
            gsGame: .colosseum,
            gameIDs: PokemonColosseum.gameIDs,
            fallbackGameID: PokemonColosseum.gameIDUS,
            typeMap: { PokemonColosseum.dolTypeMapData(for: $0) },
            symbolMap: { PokemonColosseum.symbolMapData(for: $0) },
            spotChecks: [
                (table: "Abilities", column: "name_id", row: 1, value: "3101"),
                (table: "TMs", column: "move_id", row: 0, value: "FOCUSPUNCH"),
                (table: "Items", column: "bag_slot", row: 1, value: "PokeBalls"),
                (table: "ValidItems", column: "item_id", row: 1, value: "MASTERBALL"),
            ]
        )
    }

    /// Engines from code, not the project's folder — a project dumped before
    /// a definition landed carries a stale copy on disk — plus the region's
    /// own DOL maps, which is the job `ProjectSetup` does once it knows the
    /// game ID.
    private func install(
        _ corpus: Corpus,
        gameID: String,
        in fileSystem: FileSystemTree
    ) throws -> (dolphin: Folder, typedData: [Folder], typeMap: File?, symbolMap: File?) {
        let folder = scratch.folder("Engines")
        let dolphin = try DolphinEngine.defaults()
        let gs = GeniusSonorityEngine.defaultEngine(for: corpus.gsGame)
        let pokemon = try PokemonEngine.defaults()
        for engine in [dolphin as any Engine, corpus.gameEngine, gs as any Engine, pokemon as any Engine] {
            try engine.write(to: fileSystem, in: folder, overwrite: true)
        }
        var typeMapFile: File? = nil
        if let data = corpus.typeMap(gameID) {
            typeMapFile = scratch.file("dol_typemap.json")
            try fileSystem.writeFile(data, at: typeMapFile!, overwrite: true)
        }
        var symbolMapFile: File? = nil
        if let data = corpus.symbolMap(gameID) {
            symbolMapFile = scratch.file("dol.map")
            try fileSystem.writeFile(data, at: symbolMapFile!, overwrite: true)
        }
        return (
            dolphin: folder.folder(dolphin.name),
            typedData: [folder.folder(corpus.gameEngine.name), folder.folder(gs.name), folder.folder(pokemon.name)],
            typeMap: typeMapFile,
            symbolMap: symbolMapFile
        )
    }

    private func declaredTables(in typeMap: GoDData) throws -> [(name: String, count: Int)] {
        let map = try JSONDecoder().decode(TypeMap.self, from: typeMap)
        return map.chunks.compactMap {
            guard case .table(let table) = $0, let count = table.count else { return nil }
            return (name: table.name, count: count)
        }
    }

    private func verify(_ corpus: Corpus) throws {
        let fileSystem = FileSystem.shared
        let root = Folder(corpus.projectRoot)
        let sys = root.folder("Build").folder("Contents").folder("sys")
        let dolPath = sys.file("main.dol")
        guard fileSystem.inspectFile(at: dolPath) != nil else {
            throw XCTSkip("No main.dol at \(dolPath.path) — point the corpus variable at a project folder.")
        }

        var gameID = corpus.fallbackGameID
        if let boot = fileSystem.readFile(at: sys.file("boot.bin"))?.allData,
           let id = boot.readString(atAddress: 0, format: .utf8, maxCharacters: 4),
           corpus.gameIDs.contains(id) {
            gameID = id
        }
        guard let typeMapData = corpus.typeMap(gameID) else {
            throw XCTSkip("No bundled DOL type map for game id \(gameID).")
        }

        try? fileSystem.deleteFolder(at: scratch)
        let engines = try install(corpus, gameID: gameID, in: fileSystem)
        let outputFolder = scratch.folder("Disassembly")
        let logger = RecordingLogger()
        try DolDisassembly.disassemble(
            config: .init(
                dolPath: dolPath,
                outputFolder: outputFolder,
                symbolMapPath: engines.symbolMap,
                dolphinEngine: engines.dolphin,
                typeMapPath: engines.typeMap,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: logger
        )

        // A DOL keeps one manifest per data section, so the chunks have to be
        // gathered across all of them; the folder each came from is what the
        // chunk's `file` is relative to.
        let moduleFolder = outputFolder.folder(DolDisassembler.outputFolderName(for: dolPath))
        var chunks = [String: (chunk: DataSectionManifest.Chunk, folder: Folder)]()
        for section in fileSystem.inspectFolder(at: moduleFolder)?.subFolders ?? [] {
            guard let json = fileSystem.readFile(at: section.file("manifest.json"))?.allData,
                  let manifest = try? JSONDecoder().decode(DataSectionManifest.self, from: json)
            else { continue }
            for chunk in manifest.chunks { chunks[chunk.label] = (chunk, section) }
        }

        let declared = try declaredTables(in: typeMapData)
        // A table is named in the type map by its start label but recorded in
        // the manifest under that same label, so the lookup is by label.
        let map = try JSONDecoder().decode(TypeMap.self, from: typeMapData)
        var startLabel = [String: String]()
        for case .table(let table) in map.chunks { startLabel[table.name] = table.start }

        let typed = declared.filter { chunks[startLabel[$0.name] ?? ""]?.chunk.type == .table }
        print("""
        [\(corpus.label) DOL table corpus] \(gameID): \(typed.count)/\(declared.count) declared tables dumped as CSV.
        """)
        for (name, _) in declared where chunks[startLabel[name] ?? ""]?.chunk.type != .table {
            print("  [\(corpus.label) \(name)] not typed")
            for warning in logger.warnings where warning.contains("'\(name)'") {
                print("    \(warning)")
            }
        }

        // Where the map names the table's start, its declared size is an
        // independent statement of how long the table is — and the one check
        // that catches a count which is simply too big, since such a table
        // still dumps, still round-trips and still reads correctly for every
        // row that is really there. XD's `Abilities` shipped at 123 rows
        // against `pokemon_tokusei_data`'s 0x3A8 bytes, which is 78.
        var symbolSizes = [UInt32: UInt32]()
        if let path = engines.symbolMap,
           let data = fileSystem.readFile(at: path)?.allData {
            for symbol in SymbolMapParser().parse(data.string(format: .utf8)) where symbol.size > 0 {
                symbolSizes[symbol.address] = symbol.size
            }
        }

        let engine = try GenericEngine(combining: engines.typedData, in: fileSystem)
        var rows = [String: [[String: String]]]()
        for (name, count) in declared {
            guard let label = startLabel[name], let entry = chunks[label] else {
                XCTFail("\(corpus.label) \(name): the type map's \(startLabel[name] ?? "?") matched no label, so the table was skipped")
                continue
            }
            XCTAssertEqual(entry.chunk.type, .table, "\(corpus.label) \(name) did not dump as CSV")
            guard entry.chunk.type == .table, let structType = entry.chunk.structType else { continue }
            XCTAssertEqual(entry.chunk.count, count, "\(corpus.label) \(name): row count")

            let csv = try XCTUnwrap(
                fileSystem.readFile(at: entry.folder.file(entry.chunk.file))?.allData,
                "\(corpus.label) \(name): no CSV on disk"
            ).string(format: .utf8)
            let definition: StructDefinition = try engine.getStruct(structType)
            let decoded = try StructTableCSV.decode(csv, definition: definition, byteOrder: .big)
            XCTAssertEqual(decoded.entries.count, count, "\(corpus.label) \(name): CSV lost rows")
            rows[name] = parse(csv)

            if let address = UInt32(label.dropFirst(4), radix: 16),
               let declaredSize = symbolSizes[address] {
                XCTAssertEqual(
                    count * definition.length, Int(declaredSize),
                    "\(corpus.label) \(name): \(count) rows of \(definition.length) bytes is "
                    + "\(count * definition.length) bytes, but the symbol at \(label) is \(declaredSize)"
                )
            }
        }

        for check in corpus.spotChecks {
            guard let table = rows[check.table], check.row < table.count else {
                XCTFail("\(corpus.label) \(check.table): no row \(check.row) to spot-check")
                continue
            }
            XCTAssertEqual(
                table[check.row][check.column], check.value,
                "\(corpus.label) \(check.table) row \(check.row) \(check.column)"
            )
        }

        try? fileSystem.deleteFolder(at: scratch)
    }

    /// The CSV as `[row: [column: value]]`. Deliberately naive — every cell
    /// these tests check is a bare number or enum case name, and the codec
    /// itself is covered by `StructTableCSV`'s own tests.
    private func parse(_ csv: String) -> [[String: String]] {
        var lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            var row = [String: String]()
            for (index, name) in header.enumerated() where index < cells.count {
                row[name] = cells[index]
            }
            return row
        }
    }

    func testXDDolTablesDumpAsCSVWithTheDeclaredCounts() throws {
        try verify(try xdCorpus())
    }

    func testColosseumDolTablesDumpAsCSVWithTheDeclaredCounts() throws {
        try verify(try colosseumCorpus())
    }
}
