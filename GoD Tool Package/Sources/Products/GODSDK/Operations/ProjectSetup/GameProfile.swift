//
//  GameProfile.swift
//  GODOps
//
//  Everything project setup needs to know that varies from game to game.
//
//  Setup used to branch on `isXD` / `isColosseum` / `isPBR` at a dozen
//  scattered sites and carried two ~95-line, near-identical blocks — one per
//  Genius Sonority GameCube game — that differed only in an engine name, an
//  operation case, a message variant and which map-rel folders to use. Adding
//  a game meant editing all of it. It also hardcoded values the engines
//  already declare (`"XD Engine"` as a string literal, the unused-Colo map
//  prefixes, the Wii disc capacity), so the two could drift apart silently.
//
//  A profile is the data behind those differences. `Project.setup` reads one
//  and generates the same op chain for any game that has one, so supporting
//  another Genius Sonority title is a new `GameProfile` rather than another
//  `if` branch.
//

import Foundation
import GoDFoundation
import GoDEngine
import GeniusSonority
import Colosseum
import XD

struct GameProfile {

    /// Which `coloXDDump` / `coloXDBuild` case drives the FSYS pipeline.
    /// The two currently run the same code, but the config surface keeps
    /// them apart, so the profile records which one to emit.
    enum FSYSFamily {
        case colosseum
        case galeOfDarkness
    }

    /// One map-rel disassembly target: where its source lands under
    /// `/Source/Code`, which typemap types it, and which `.rel`s it claims.
    struct MapPlan {
        let sourceFolderName: String
        /// Path of the typemap within the game's engine folder. Every plan
        /// has one — XD points both of its plans at the same map, Colosseum
        /// has one per layout.
        let typeMapResource: File
        let filter: MapRelDump.Filter
    }

    let gameIDs: [String]
    let gsGame: GSGame
    /// Folder name the game engine serializes to — read from the engine
    /// itself rather than repeated as a literal.
    let engineName: String
    /// `variant` string for the message dump/build ops.
    let msgVariant: String
    let family: FSYSFamily
    let mapPlans: [MapPlan]
    /// Path of the DOL typemap within the engine folder, if the game ships
    /// one. Games without a typemap disassemble their DOL as raw hex.
    let dolTypeMapResource: File?
    /// Path of the DOL symbol map within the engine folder.
    let dolSymbolMapResource: File
    /// Region-matched files to install into the engine folder once the disc's
    /// game ID is known. The engine carries region-neutral paths; which bytes
    /// land there depends on the region.
    let regionalResources: (String) -> [(path: File, data: GoDData)]
    /// Builds the game engine for serialization into the project.
    let makeEngine: () throws -> any Engine

    // MARK: - Lookup

    static func profile(forGameID gameID: String) -> GameProfile? {
        all.first { $0.gameIDs.contains(gameID) }
    }

    static let all: [GameProfile] = [.galeOfDarkness, .colosseum]

    // MARK: - Genius Sonority GameCube games

    static let galeOfDarkness: GameProfile = {
        let data = XDEngine.Data()
        let resources = data.resources
        return GameProfile(
            gameIDs: PokemonXD.gameIDs,
            gsGame: .galeOfDarkness,
            engineName: XDEngine.defaultName,
            msgVariant: "xd",
            family: .galeOfDarkness,
            mapPlans: [
                // The regular maps, minus the leftover Colosseum-format ones.
                .init(
                    sourceFolderName: "maps",
                    typeMapResource: resources.mapRelTypeMap,
                    filter: .excludePrefixes(data.unusedColosseumMapPrefixes)
                ),
                // …which go to their own folder, since they don't follow the
                // XD layout the typemap describes.
                .init(
                    sourceFolderName: "maps_unused",
                    typeMapResource: resources.mapRelTypeMap,
                    filter: .onlyPrefixes(data.unusedColosseumMapPrefixes)
                ),
            ],
            dolTypeMapResource: resources.dolTypeMap,
            dolSymbolMapResource: resources.dolSymbolMap,
            regionalResources: { gameID in
                // XD's common.rel layout is region-stable, so only the DOL
                // symbol map varies.
                guard let map = PokemonXD.symbolMapData(for: gameID) else { return [] }
                return [(resources.dolSymbolMap, map)]
            },
            makeEngine: { try XDEngine.defaults() }
        )
    }()

    static let colosseum: GameProfile = {
        let data = ColosseumEngine.Data()
        let resources = data.resources
        return GameProfile(
            gameIDs: PokemonColosseum.gameIDs,
            gsGame: .colosseum,
            engineName: ColosseumEngine.defaultName,
            msgVariant: "colo",
            family: .colosseum,
            mapPlans: [
                // Colosseum maps come in two layouts. The runtime classifier
                // that tells them apart isn't ported yet, so both plans ship
                // disabled and the user opts in once the prefixes are known.
                .init(
                    sourceFolderName: "maps_type1",
                    typeMapResource: resources.mapRelTypeMapType1,
                    filter: .coloType1
                ),
                .init(
                    sourceFolderName: "maps_type2",
                    typeMapResource: resources.mapRelTypeMapType2,
                    filter: .coloType2
                ),
            ],
            dolTypeMapResource: nil,
            dolSymbolMapResource: resources.dolSymbolMap,
            regionalResources: { gameID in
                var result = [(path: File, data: GoDData)]()
                if let map = PokemonColosseum.symbolMapData(for: gameID) {
                    result.append((resources.dolSymbolMap, map))
                }
                // common.rel pointer indices move between Colosseum builds
                // (StringTable*/Script sit at different indices per region),
                // so the matching map is chosen here.
                if let symbols = PokemonColosseum.commonRelSymbolMapData(for: gameID) {
                    result.append((resources.commonRelSymbolMap, symbols))
                }
                return result
            },
            makeEngine: { try ColosseumEngine.defaults() }
        )
    }()
}
