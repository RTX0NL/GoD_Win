//
//  PokemonGameEnumTests.swift
//  PokemonTests
//
//  The species / move / item enums are generated from the games' own data
//  tables, so the risk isn't a typo in one case — it's a systematic fault in
//  the generation: a duplicate name silently shadowing another entry, a raw
//  value appearing twice, or a name that can't survive serialization.
//  These check the properties that must hold for all ~3,500 cases.
//

import XCTest
import Foundation
import GoDEngine
import Structs
@testable import Pokemon

final class PokemonGameEnumTests: XCTestCase {

    private let numberedEnums = ["PokemonSpecies", "Moves", "Items", "Abilities"]

    private func engine(_ game: PokemonEngine.Game) throws -> PokemonEngine {
        try PokemonEngine.defaultEngine(for: game)
    }

    // MARK: - Every game has its own three lists

    func testEachGameShipsItsOwnNumberedEnums() throws {
        for game in PokemonEngine.Game.allCases {
            let enums = try engine(game).enums.entries
            for name in numberedEnums {
                let match = enums.filter { $0.name == name }
                XCTAssertEqual(match.count, 1, "\(game) should declare exactly one '\(name)'")
                XCTAssertFalse(match.first?.values.isEmpty ?? true, "\(game).\(name) is empty")
            }
        }
    }

    func testSharedCrossGameEnumsAreStillPresent() throws {
        // The fixed-cardinality enums are game-independent and must not have
        // been displaced by the per-game ones.
        for game in PokemonEngine.Game.allCases {
            let names = Set(try engine(game).enums.entries.map(\.name))
            for shared in ["Type", "Nature", "Gender", "EggGroup", "ExpRate"] {
                XCTAssertTrue(names.contains(shared), "\(game) lost the shared '\(shared)' enum")
            }
        }
    }

    // MARK: - Properties that must hold for every case

    func testEveryCaseNameIsValid() throws {
        for game in PokemonEngine.Game.allCases {
            for definition in try engine(game).enums.entries {
                XCTAssertEqual(
                    definition.invalidCaseNames, [],
                    "\(game).\(definition.name) has unusable case names"
                )
            }
        }
    }

    func testCaseNamesAreUniqueWithinEachEnum() throws {
        // A duplicate name is worse than a missing one: `get(_ name:)` takes
        // the first match, so the later entry becomes unreachable and any
        // edit naming it would silently write the wrong id.
        for game in PokemonEngine.Game.allCases {
            for definition in try engine(game).enums.entries {
                let names = definition.values.map { $0.name.lowercased() }
                let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }
                XCTAssertTrue(
                    duplicates.isEmpty,
                    "\(game).\(definition.name) repeats: \(duplicates.keys.sorted().prefix(5))"
                )
            }
        }
    }

    func testRawValuesAreUniqueWithinEachEnum() throws {
        for game in PokemonEngine.Game.allCases {
            for definition in try engine(game).enums.entries where numberedEnums.contains(definition.name) {
                let raws = definition.values.map(\.rawValue)
                XCTAssertEqual(Set(raws).count, raws.count, "\(game).\(definition.name) repeats a raw value")
            }
        }
    }

    func testRawValuesFitTheDeclaredWidth() throws {
        for game in PokemonEngine.Game.allCases {
            for definition in try engine(game).enums.entries where numberedEnums.contains(definition.name) {
                // Abilities are uint8 because that is the width of the
                // fields holding them; the rest are uint16.
                let expected: IntegerProperties = definition.name == "Abilities" ? .uint8 : .uint16
                let limit = definition.name == "Abilities" ? 0xFF : 0xFFFF
                XCTAssertEqual(definition.propertyType, expected, "\(game).\(definition.name)")
                for value in definition.values {
                    XCTAssertTrue(
                        (0...limit).contains(value.rawValue),
                        "\(game).\(definition.name).\(value.name) = \(value.rawValue) exceeds its width"
                    )
                }
            }
        }
    }

    // MARK: - The numbering really is per-game

    func testGamesNumberTheSameSpeciesDifferently() throws {
        // The reason these can't be shared. Deoxys sits at 410 in the two
        // GameCube games and at its national-dex 386 in Battle Revolution;
        // installing the wrong list would put confident, wrong names in
        // every abstracted column.
        func speciesEnum(_ game: PokemonEngine.Game) throws -> Enum {
            try XCTUnwrap(try engine(game).getEnum("PokemonSpecies"))
        }
        XCTAssertEqual(try speciesEnum(.galeOfDarkness).get("DEOXYS").rawValue, 410)
        XCTAssertEqual(try speciesEnum(.colosseum).get("DEOXYS").rawValue, 410)
        XCTAssertEqual(try speciesEnum(.battleRevolution).get("DEOXYS").rawValue, 386)

        // And anchors that should agree everywhere.
        for game in PokemonEngine.Game.allCases {
            XCTAssertEqual(try speciesEnum(game).get("BULBASAUR").rawValue, 1, "\(game)")
        }
    }

    func testColosseumAndXDShareTheAbilityNumbering() throws {
        // Their ability names occupy the same message ids in the same order,
        // which is what makes one shared list correct. PBR's is its own.
        let colo = try XCTUnwrap(try engine(.colosseum).getEnum("Abilities"))
        let xd = try XCTUnwrap(try engine(.galeOfDarkness).getEnum("Abilities"))
        let pbr = try XCTUnwrap(try engine(.battleRevolution).getEnum("Abilities"))
        XCTAssertEqual(colo.values, xd.values)
        XCTAssertEqual(colo.values.count, 77)
        XCTAssertEqual(pbr.values.count, 124)
        XCTAssertEqual(try colo.get("STENCH").rawValue, 1)
        XCTAssertEqual(try pbr.get("Stench").rawValue, 1)
    }

    func testItemAndMoveListsDifferPerGame() throws {
        let colo = try engine(.colosseum)
        let xd = try engine(.galeOfDarkness)
        // XD added moves and items over Colosseum; the lists must not be the
        // same object smuggled into both.
        let coloMoves = try XCTUnwrap(colo.getEnum("Moves")).values.count
        let xdMoves = try XCTUnwrap(xd.getEnum("Moves")).values.count
        XCTAssertGreaterThan(xdMoves, coloMoves)
        let coloItems = try XCTUnwrap(colo.getEnum("Items")).values.count
        let xdItems = try XCTUnwrap(xd.getEnum("Items")).values.count
        XCTAssertGreaterThan(xdItems, coloItems)
    }

    // MARK: - Round trip

    func testEveryCaseRoundTripsNameToRawToName() throws {
        for game in PokemonEngine.Game.allCases {
            for definition in try engine(game).enums.entries where numberedEnums.contains(definition.name) {
                for value in definition.values {
                    let byName = try definition.get(value.name)
                    XCTAssertEqual(byName.rawValue, value.rawValue)
                    XCTAssertEqual(try definition.get(value.rawValue).name, value.name)
                }
            }
        }
    }

    func testUnknownRawValuesAreTolerated() throws {
        // allowUnknownCases is on so a romhack's extra ids don't fail a dump;
        // the CSV codec writes those back as plain integers.
        let moves = try XCTUnwrap(try engine(.colosseum).getEnum("Moves"))
        XCTAssertTrue(moves.allowUnknownCases)
        XCTAssertNoThrow(try moves.get(9999))
    }
}
