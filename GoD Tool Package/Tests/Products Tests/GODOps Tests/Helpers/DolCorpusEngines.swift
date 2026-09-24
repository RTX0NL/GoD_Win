//
//  DolCorpusEngines.swift
//  GODOpsTests
//
//  The engine folders a DOL corpus test disassembles with.
//
//  They are written from code rather than read out of the project's own
//  folder on purpose: a project dumped before an engine gained a definition
//  has a stale copy on disk. But `Engine.write` emits only the region-neutral
//  defaults — the DOL symbol map is not bundled at all (`ProjectSetup`
//  installs the ROM's own once it knows the game ID) and the bundled type map
//  is the US one. A test that took the written folder as it came therefore
//  disassembled with **no symbol map**, and with a US type map whatever disc
//  the corpus held, which is a weaker configuration than any real project and
//  left the symbol-map assertions unreachable. This finishes the job
//  `ProjectSetup` does.
//

import Foundation
import GoDFoundation
import GoDEngine
import Dolphin
import XD
import GeniusSonority
import Pokemon

/// Where the engines landed, plus the two region-keyed DOL resources an
/// operation config needs to point at.
struct DolCorpusEngines {
    /// The `dolphinEngine` config field.
    let dolphin: Folder
    /// Engine folders whose structs resolve the type map's chunk types,
    /// game engine first — the order `ProjectSetup` writes.
    let typedData: [Folder]
    /// The DOL symbol map for the corpus's region.
    let symbolMap: File?
    /// The DOL type map for the corpus's region.
    let typeMap: File?
    /// The game ID those two were chosen for.
    let gameID: String
}

/// Write the XD engine set into `scratch/Engines`, then overwrite the two
/// region-keyed DOL resources with the corpus disc's own.
func installDolCorpusEngines(
    forProjectAt projectRoot: Folder,
    under scratch: Folder,
    in fileSystem: FileSystemTree
) throws -> DolCorpusEngines {
    let folder = scratch.folder("Engines")
    let dolphin = try DolphinEngine.defaults()
    let xd = try XDEngine.defaults()
    let gs = GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness)
    let pokemon = try PokemonEngine.defaults()
    for engine in [dolphin as any Engine, xd as any Engine, gs as any Engine, pokemon as any Engine] {
        try engine.write(to: fileSystem, in: folder, overwrite: true)
    }

    let xdFolder = folder.folder(xd.name)
    let resources = XDEngine.Data().resources
    let gameID = dolCorpusGameID(forProjectAt: projectRoot, in: fileSystem)

    let symbolMapFile = xdFolder.file(resources.dolSymbolMap.path)
    if let data = PokemonXD.symbolMapData(for: gameID) {
        try fileSystem.writeFile(data, at: symbolMapFile, overwrite: true)
    }
    let typeMapFile = xdFolder.file(resources.dolTypeMap.path)
    if let data = PokemonXD.dolTypeMapData(for: gameID) {
        try fileSystem.writeFile(data, at: typeMapFile, overwrite: true)
    }

    return DolCorpusEngines(
        dolphin: folder.folder(dolphin.name),
        typedData: [xdFolder, folder.folder(gs.name), folder.folder(pokemon.name)],
        symbolMap: fileSystem.inspectFile(at: symbolMapFile) != nil ? symbolMapFile : nil,
        typeMap: fileSystem.inspectFile(at: typeMapFile) != nil ? typeMapFile : nil,
        gameID: gameID
    )
}

/// The corpus disc's game ID, read from the project's own `boot.bin`.
///
/// A corpus that is only a `main.dol` has no `boot.bin` to read, and the
/// default corpus path is a US project, so US is the fallback. Callers print
/// the resolved id, because picking the wrong region's maps mis-types a disc
/// rather than failing outright.
func dolCorpusGameID(forProjectAt projectRoot: Folder, in fileSystem: FileSystemTree) -> String {
    let bootBin = projectRoot.folder("Build").folder("Contents").folder("sys").file("boot.bin")
    if let data = fileSystem.readFile(at: bootBin)?.allData,
       let id = data.readString(atAddress: 0, format: .utf8, maxCharacters: 4),
       PokemonXD.gameIDs.contains(id) {
        return id
    }
    return PokemonXD.gameIDUS
}
