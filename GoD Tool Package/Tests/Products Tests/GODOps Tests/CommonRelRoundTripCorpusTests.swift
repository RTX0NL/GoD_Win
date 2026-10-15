//
//  CommonRelRoundTripCorpusTests.swift
//  GODOpsTests
//
//  A typed `common.rel` dumped and reassembled must come back byte-for-byte.
//  This is the whole typed-edit pipeline end to end — the disassembler, the
//  type map, every format the map names (MSG, GTX, FNT, SCD), the CSV table
//  codec, and the assembler re-deriving relocations — so a regression in any
//  of them shows up here as a byte count.
//
//  It is the check that catches a chunk changing *size*, which is worse than
//  a chunk changing content: everything after it in the section moves, and
//  the address-keyed symbol and type maps no longer describe the module, so
//  the next dump reads the wrong things at the wrong places. The 2026-09
//  audit measured exactly that — XD PAL 8 bytes short, Colosseum US 65 —
//  and the cause was the MSG writer dropping the 1-3 bytes of 4-byte
//  alignment padding its container puts after each embedded string table.
//
//  Skips without a module. `GODDESS_COMMON_REL_ROUNDTRIP` overrides the
//  samples, as `<engine>=<game id>=<path>` entries separated by `;`, e.g.
//  "xd=GXXP=/dumps/xd-pal/common.rel;colo=GC6E=/dumps/colo-us/common.rel".
//  The game id picks the region's type map and symbol index and cannot be
//  read off the module, so it is named rather than guessed.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Dolphin
import Disassembler
import XD
import Colosseum
import GeniusSonority
import Pokemon
@testable import GODOps

final class CommonRelRoundTripCorpusTests: XCTestCase {

    private struct Sample {
        let label: String
        let path: String
        let gameID: String
        let gsGame: GSGame
        let gameEngine: any Engine
        let typeMap: GoDData?
        let symbolIndex: GoDData?
    }

    private func sample(engine: String, gameID: String, path: String) throws -> Sample? {
        switch engine {
        case "xd":
            return Sample(
                label: "XD \(gameID)", path: path, gameID: gameID, gsGame: .galeOfDarkness,
                gameEngine: try XDEngine.defaults(),
                typeMap: PokemonXD.commonRelTypeMapData(for: gameID),
                // XD's pointer indices are the same on every build, so one
                // symbol index serves every region.
                symbolIndex: PokemonXD.bundledResource(named: "common_rel_symbols.json")
            )
        case "colo":
            let suffix: String
            switch gameID {
            case PokemonColosseum.gameIDUS: suffix = "us"
            case PokemonColosseum.gameIDEU: suffix = "eu"
            case PokemonColosseum.gameIDJP: suffix = "jp"
            default: return nil
            }
            return Sample(
                label: "Colosseum \(gameID)", path: path, gameID: gameID, gsGame: .colosseum,
                gameEngine: try ColosseumEngine.defaults(),
                typeMap: PokemonColosseum.commonRelTypeMapData(for: gameID),
                symbolIndex: PokemonColosseum.bundledResource(named: "common_rel_symbols_\(suffix).json")
            )
        default:
            return nil
        }
    }

    private func samples() throws -> [Sample] {
        let specs = ProcessInfo.processInfo.environment["GODDESS_COMMON_REL_ROUNDTRIP"]
            ?? [
                "xd=\(PokemonXD.gameIDEU)=\(NSHomeDirectory())/Documents/GoD Tool/XD GoD Tool dumped/Game Files/common/common.rel",
                "colo=\(PokemonColosseum.gameIDUS)=\(NSHomeDirectory())/Documents/GoD Tool/Colo CM Tool/Game Files/common/common.rel",
            ].joined(separator: ";")

        var found: [Sample] = []
        for spec in specs.split(separator: ";") {
            let parts = spec.split(separator: "=", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            guard FileManager.default.fileExists(atPath: parts[2]) else { continue }
            if let sample = try sample(engine: parts[0], gameID: parts[1], path: parts[2]) {
                found.append(sample)
            }
        }
        return found
    }

    /// Engines from code, not from a project folder — a project dumped
    /// before a definition landed carries a stale copy on disk.
    private func installEngines(
        for sample: Sample,
        under folder: Folder,
        in fileSystem: FileSystemTree
    ) throws -> (dolphin: Folder, typedData: [Folder]) {
        let dolphin = try DolphinEngine.defaults()
        let gs = GeniusSonorityEngine.defaultEngine(for: sample.gsGame)
        let pokemon = try PokemonEngine.defaults()
        for engine in [dolphin as any Engine, sample.gameEngine, gs as any Engine, pokemon as any Engine] {
            try engine.write(to: fileSystem, in: folder, overwrite: true)
        }
        return (
            dolphin: folder.folder(dolphin.name),
            typedData: [folder.folder(sample.gameEngine.name), folder.folder(gs.name), folder.folder(pokemon.name)]
        )
    }

    func testTypedCommonRelDumpsAndReassemblesByteIdentically() throws {
        let samples = try samples()
        if samples.isEmpty {
            throw XCTSkip("No common.rel to check — set GODDESS_COMMON_REL_ROUNDTRIP to <engine>=<game id>=<path> entries.")
        }

        let fileSystem = FileSystem.shared
        for sample in samples {
            guard let typeMapData = sample.typeMap else {
                XCTFail("\(sample.label): no bundled common.rel type map for \(sample.gameID)")
                continue
            }
            let scratch = Folder(nativePath: NSTemporaryDirectory()).folder("goddess-common-rel-round-trip")
            try? fileSystem.deleteFolder(at: scratch)
            defer { try? fileSystem.deleteFolder(at: scratch) }

            let engines = try installEngines(for: sample, under: scratch.folder("Engines"), in: fileSystem)
            let original = GoDData(
                byteStream: [UInt8](try Data(contentsOf: URL(fileURLWithPath: sample.path))),
                byteOrder: .big
            )
            let relPath = scratch.file("common.rel")
            try fileSystem.writeFile(original, at: relPath, overwrite: true)

            let typeMapPath = scratch.file("common_rel_typemap.json")
            try fileSystem.writeFile(typeMapData, at: typeMapPath, overwrite: true)
            var symbolIndexPath: File? = nil
            if let symbols = sample.symbolIndex {
                symbolIndexPath = scratch.file("common_rel_symbols.json")
                try fileSystem.writeFile(symbols, at: symbolIndexPath!, overwrite: true)
            }

            let dumpFolder = scratch.folder("dump")
            try RelDisassembly.disassemble(
                config: .init(
                    relPath: relPath,
                    outputFolder: dumpFolder,
                    dolphinEngine: engines.dolphin,
                    symbolIndexPath: symbolIndexPath,
                    typeMapPath: typeMapPath,
                    engines: engines.typedData
                ),
                settings: .default, fileSystem: fileSystem, logger: SilentLogger()
            )

            let rebuiltPath = scratch.file("rebuilt.rel")
            try RelAssembly.assemble(
                config: .init(
                    inputFolder: dumpFolder,
                    relName: "common",
                    outputPath: rebuiltPath,
                    overwrite: true,
                    engines: engines.typedData
                ),
                settings: .default, fileSystem: fileSystem, logger: SilentLogger()
            )

            let rebuilt = try XCTUnwrap(
                fileSystem.readFile(at: rebuiltPath)?.allData,
                "\(sample.label): the assembly wrote nothing"
            )
            let before = original.rawBytes, after = rebuilt.rawBytes
            XCTAssertEqual(
                after.count, before.count,
                "\(sample.label): rebuilt module changed size — every symbol after the resized chunk moves"
            )
            let firstDifference = zip(before, after).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            XCTAssertNil(
                firstDifference.map { String(format: "0x%X", $0) },
                "\(sample.label): rebuilt module differs from the original"
            )
            print("[common.rel round trip] \(sample.label): \(before.count) bytes, byte-identical")
        }
    }
}
