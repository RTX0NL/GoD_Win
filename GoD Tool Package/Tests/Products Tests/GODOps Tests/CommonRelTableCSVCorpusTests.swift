//
//  CommonRelTableCSVCorpusTests.swift
//  GODOpsTests
//
//  The common.rel tables users actually edit — species, moves, trainers,
//  battles, rooms — dump as CSV only when their struct definition tiles the
//  real table and every declared padding run really is zero (see CLAUDE.md,
//  "Struct tables as CSV"). The synthetic tests pin the layouts to the
//  accessors; these run the real dump over a real `common.rel` for each game
//  and check that the tables came out typed rather than demoted to raw bytes.
//
//  The dump verifies each CSV byte-for-byte against the table before writing
//  it, so a table that is present as CSV has already round-tripped. What is
//  asserted on top is the one thing that verification cannot see: that the
//  row count equals the REL's own count word for the table — a wrong stride
//  would still round-trip, but it would not divide the chunk into the number
//  of rows the game says are there.
//
//  Both tests skip cleanly when their unpacked project isn't present. Point
//  them elsewhere with GODDESS_COMMON_REL_CORPUS (XD) and
//  GODDESS_COLO_COMMON_REL_CORPUS (Colosseum): a project folder holding
//  Build/Unpacked/Assets/Data/Common/common.rel and Build/Contents/sys/boot.bin,
//  which names the region and so the type map to use.
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

final class CommonRelTableCSVCorpusTests: XCTestCase {

    /// One game's corpus: where the project is, which engines resolve its
    /// tables, and how its region-keyed resources are found.
    private struct Corpus {
        let label: String
        let projectRoot: String
        let gameEngine: any Engine
        let gsGame: GSGame
        let typeMap: (String) -> GoDData?
        let symbolIndex: (String) -> GoDData?
        /// Tables that must dump as CSV, each with the REL symbol that
        /// holds its entry count.
        let requiredTables: [(table: String, countSymbol: String)]
    }

    private var scratch: Folder {
        Folder(NSTemporaryDirectory()).folder("goddess-common-rel-csv-corpus")
    }

    private func env(_ key: String, default value: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? value
    }

    private func xdCorpus() throws -> Corpus {
        Corpus(
            label: "XD",
            projectRoot: env("GODDESS_COMMON_REL_CORPUS", default: "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project"),
            gameEngine: try XDEngine.defaults(),
            gsGame: .galeOfDarkness,
            typeMap: { PokemonXD.commonRelTypeMapData(for: $0) },
            // XD's pointer indices are the same on every build, so the
            // engine ships one symbol index.
            symbolIndex: { _ in PokemonXD.bundledResource(named: "common_rel_symbols.json") },
            requiredTables: [
                ("PokemonStats", "NumberOfPokemon"),
                ("Battles", "NumberOfBattles"),
                ("Rooms", "NumberOfRooms"),
                ("Pokespots", "NumberOfPokespots"),
                ("PokespotRock", "PokespotRockEntries"),
                ("PokespotOasis", "PokespotOasisEntries"),
                ("PokespotCave", "PokespotCaveEntries"),
                ("PokespotAll", "PokespotAllEntries"),
                ("Items", "NumberOfItems"),
                ("Moves", "NumberOfMoves"),
                ("Natures", "NumberOfNatures"),
                ("TreasureBoxData", "NumberOfTreasureBoxes"),
                ("Types", "NumberOfTypes"),
            ]
        )
    }

    private func colosseumCorpus() throws -> Corpus {
        Corpus(
            label: "Colosseum",
            projectRoot: env("GODDESS_COLO_COMMON_REL_CORPUS", default: "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project"),
            gameEngine: try ColosseumEngine.defaults(),
            gsGame: .colosseum,
            typeMap: { PokemonColosseum.commonRelTypeMapData(for: $0) },
            // Colosseum's pointer indices differ per build, so the symbol
            // index is region-keyed like the type map.
            symbolIndex: { gameID in
                let suffix: String
                switch gameID {
                case PokemonColosseum.gameIDUS: suffix = "us"
                case PokemonColosseum.gameIDEU: suffix = "eu"
                case PokemonColosseum.gameIDJP: suffix = "jp"
                default: return nil
                }
                return PokemonColosseum.bundledResource(named: "common_rel_symbols_\(suffix).json")
            },
            requiredTables: [
                ("LegendaryPokemon", "NumberOfLegendaryPokemon"),
                ("PokefaceTextures", "NumberOfPokefaceTextures"),
                ("PeopleIDs", "NumberOfPeopleIDs"),
                ("Rooms", "NumberOfRooms"),
                ("TrainerClasses", "NumberOfTrainerClasses"),
                ("BattleFields", "NumberOfBattleFields"),
                ("Doors", "NumberOfDoors"),
                ("BattleTypes", "NumberOfBattleTypes"),
                ("KeyboardCharacters", "NumberOfKeyboardCharacters"),
                ("Keyboard2Characters", "NumberOfKeyboard2Characters"),
                ("Keyboard3Characters", "NumberOfKeyboard3Characters"),
                ("BattleStyles", "NumberOfBattleStyles"),
                ("Trainers", "NumberOfTrainers"),
                ("TrainerAIData", "NumberOfTrainerAIData"),
                ("TrainerPokemonData", "NumberOfTrainerPokemonData"),
                ("Battles", "NumberOfBattles"),
                ("SoundFiles", "NumberOfSoundFiles"),
                ("AIWeightEffects", "NumberOfAIWeightEffects"),
                ("AIPokemonRoles", "NumberOfAIPokemonRoles"),
                ("TreasureBoxData", "NumberOfTreasureBoxes"),
                ("Moves", "NumberOfMoves"),
                ("Natures", "NumberOfNatures"),
                ("PokemonStats", "NumberOfPokemon"),
                ("NatureMultipliers", "NumberOfNatureMultipliers"),
                ("CharacterModels", "NumberOfCharacterModels"),
                ("ShadowData", "NumberOfShadowPokemon"),
                ("PokemonMetLocations", "NumberOfMetLocations"),
                ("InteractionPoints", "NumberOfInteractionPoints"),
            ]
        )
    }

    /// Engines from code, not the project's folder — a project dumped
    /// before a definition landed carries a stale copy on disk.
    private func installEngines(
        for corpus: Corpus,
        in fileSystem: FileSystemTree
    ) throws -> (dolphin: Folder, typedData: [Folder]) {
        let folder = scratch.folder("Engines")
        let dolphin = try DolphinEngine.defaults()
        let gs = GeniusSonorityEngine.defaultEngine(for: corpus.gsGame)
        let pokemon = try PokemonEngine.defaults()
        for engine in [dolphin as any Engine, corpus.gameEngine, gs as any Engine, pokemon as any Engine] {
            try engine.write(to: fileSystem, in: folder, overwrite: true)
        }
        return (
            dolphin: folder.folder(dolphin.name),
            typedData: [folder.folder(corpus.gameEngine.name), folder.folder(gs.name), folder.folder(pokemon.name)]
        )
    }

    private func tableNames(in typeMap: GoDData) throws -> [String] {
        let map = try JSONDecoder().decode(TypeMap.self, from: typeMap)
        return map.chunks.compactMap {
            if case .table(let table) = $0 { return table.name }
            return nil
        }
    }

    private func bigEndianWord(_ data: GoDData) -> Int? {
        let bytes = data.rawBytes
        guard bytes.count >= 4 else { return nil }
        return (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    }

    private func verify(_ corpus: Corpus) throws {
        let fileSystem = FileSystem.shared
        let root = Folder(corpus.projectRoot)
        let relPath = root.folder("Build").folder("Unpacked").folder("Assets").folder("Data").folder("Common").file("common.rel")
        guard fileSystem.inspectFile(at: relPath) != nil else {
            throw XCTSkip("No common.rel at \(relPath.path) — point the corpus variable at a project folder.")
        }

        // The region decides the type map (and, for Colosseum, the symbol
        // index): chunks are keyed by pointer-index symbol and several
        // tables change stride between builds. The engine keys its resources
        // by the four-character game code, without the maker code that
        // follows it on disc.
        let bootPath = root.folder("Build").folder("Contents").folder("sys").file("boot.bin")
        guard let boot = fileSystem.readFile(at: bootPath)?.read(atAddress: 0, length: 4) else {
            throw XCTSkip("No boot.bin at \(bootPath.path) to read the game id from.")
        }
        let gameID = String(decoding: boot.rawBytes, as: UTF8.self)
        guard let typeMapData = corpus.typeMap(gameID) else {
            throw XCTSkip("No bundled common.rel type map for game id \(gameID).")
        }

        try? fileSystem.deleteFolder(at: scratch)
        let engines = try installEngines(for: corpus, in: fileSystem)
        let typeMapPath = scratch.file("common_rel_typemap.json")
        try fileSystem.writeFile(typeMapData, at: typeMapPath, overwrite: true)
        var symbolIndexPath: File? = nil
        if let symbols = corpus.symbolIndex(gameID) {
            symbolIndexPath = scratch.file("common_rel_symbols.json")
            try fileSystem.writeFile(symbols, at: symbolIndexPath!, overwrite: true)
        }
        let declaredTables = try tableNames(in: typeMapData)

        let outputFolder = scratch.folder("common_rel")
        let logger = RecordingLogger()
        try RelDisassembly.disassemble(
            config: .init(
                relPath: relPath,
                outputFolder: outputFolder,
                dolphinEngine: engines.dolphin,
                symbolIndexPath: symbolIndexPath,
                typeMapPath: typeMapPath,
                engines: engines.typedData
            ),
            settings: .default,
            fileSystem: fileSystem,
            logger: logger
        )

        // Every chunk of every data section, keyed by label. The REL manifest
        // carries one chunk list per section, with file paths relative to the
        // module folder.
        let manifest = try RelManifest(json: try XCTUnwrap(
            fileSystem.readFile(at: outputFolder.file(RelManifest.fileName(for: "common")))?.allData,
            "the dump must write common.rel.json"
        ))
        var chunks = [String: (chunk: DataSectionManifest.Chunk, folder: Folder)]()
        for section in manifest.sections {
            for chunk in section.chunks ?? [] { chunks[chunk.label] = (chunk, outputFolder) }
        }

        // Which declared tables made it, so the log shows coverage as well
        // as the pass/fail on the required ones.
        let typed = declaredTables.filter { chunks[$0]?.chunk.type == .table }
        let demoted = declaredTables.filter { chunks[$0]?.chunk.type != .table }
        print("""
        [\(corpus.label) common.rel CSV corpus] \(gameID): \(typed.count)/\(declaredTables.count) declared tables dumped as CSV.
          typed:   \(typed.sorted().joined(separator: ", "))
          demoted: \(demoted.sorted().joined(separator: ", "))
        """)
        // The dump says why a table fell back to raw bytes; surface that
        // beside the failure instead of making the reader re-run it.
        for table in demoted {
            for warning in logger.warnings where warning.contains("'\(table)'") {
                print("  [\(corpus.label) \(table)] \(warning)")
            }
        }

        let engine = try GenericEngine(combining: engines.typedData, in: fileSystem)
        for (table, countSymbol) in corpus.requiredTables {
            guard let entry = chunks[table] else {
                XCTFail("\(corpus.label) \(table) is missing from the dump")
                continue
            }
            XCTAssertEqual(entry.chunk.type, .table, "\(corpus.label) \(table) did not dump as CSV")
            guard entry.chunk.type == .table,
                  let structType = entry.chunk.structType,
                  let count = entry.chunk.count
            else { continue }

            guard let countEntry = chunks[countSymbol],
                  let countData = fileSystem.readFile(at: countEntry.folder.file(countEntry.chunk.file))?.allData,
                  let declared = bigEndianWord(countData)
            else {
                XCTFail("\(corpus.label) \(table): no readable count chunk \(countSymbol)")
                continue
            }
            XCTAssertEqual(
                count, declared,
                "\(corpus.label) \(table): \(count) rows of \(structType) but \(countSymbol) says \(declared) — wrong stride"
            )

            // The CSV re-decodes through the engine to the same row count.
            let definition: StructDefinition = try engine.getStruct(structType)
            let csv = try XCTUnwrap(
                fileSystem.readFile(at: entry.folder.file(entry.chunk.file))?.allData,
                "\(corpus.label) \(table): no CSV on disk"
            ).string(format: .utf8)
            let decoded = try StructTableCSV.decode(csv, definition: definition, byteOrder: .big)
            XCTAssertEqual(decoded.entries.count, count, "\(corpus.label) \(table): CSV lost rows")
        }
    }

    func testXDCommonRelTablesDumpAsCSVWithTheDeclaredCounts() throws {
        try verify(try xdCorpus())
    }

    func testColosseumCommonRelTablesDumpAsCSVWithTheDeclaredCounts() throws {
        try verify(try colosseumCorpus())
    }
}
