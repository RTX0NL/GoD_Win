//
//  GenericEngineCombiningTests.swift
//  GoDEngineTests
//
//  Combining engines is how an operation gets "the right definitions in
//  scope": the config names engine folders, they merge in order, and a
//  lookup takes the first hit. Order is load-bearing — Colosseum and XD
//  both declare `CharacterModel` at different sizes.
//

import XCTest
import GoDFoundation
import Structs
@testable import GoDEngine

final class GenericEngineCombiningTests: XCTestCase {

    private let root = Folder("/engines")

    private func engine(
        structs: [StructMap] = [],
        enums: [Enum] = []
    ) throws -> GenericEngine {
        try GenericEngine(
            data: .init(),
            enums: .init(unchecked: enums),
            structs: .init(unchecked: structs)
        )
    }

    private func map(_ name: String, _ properties: [StructMap.Property]) -> StructMap {
        StructMap(name: name, wordSize: 4, alignmentStyle: .none, properties: properties)
    }

    // MARK: - Ordering

    func testFirstEngineWinsForADuplicatedStructName() throws {
        // The real case: Colosseum's CharacterModel is 0xDC, XD's is 0x34.
        let game = try engine(structs: [map("CharacterModel", [.padding(length: 0xDC)])])
        let other = try engine(structs: [map("CharacterModel", [.padding(length: 0x34)])])

        XCTAssertEqual(try GenericEngine(combining: [game, other]).getStruct("CharacterModel").length, 0xDC)
        XCTAssertEqual(try GenericEngine(combining: [other, game]).getStruct("CharacterModel").length, 0x34)
    }

    func testFirstEngineWinsForADuplicatedEnumName() throws {
        let first = try engine(enums: [Enum(name: "Kind", allowUnknownCases: false,
                                            values: [.init(name: "A", rawValue: 1)], propertyType: .uint8)])
        let second = try engine(enums: [Enum(name: "Kind", allowUnknownCases: false,
                                             values: [.init(name: "B", rawValue: 2)], propertyType: .uint8)])
        let combined = try GenericEngine(combining: [first, second])
        XCTAssertEqual(combined.getEnum("Kind")?.values.map(\.name), ["A"])
    }

    func testShadowedNamesReportWhatIsUnreachable() throws {
        let first = try engine(
            structs: [map("Shared", []), map("OnlyFirst", [])],
            enums: [Enum(name: "Dup", allowUnknownCases: false, values: [], propertyType: .uint8)]
        )
        let second = try engine(
            structs: [map("Shared", [])],
            enums: [Enum(name: "Dup", allowUnknownCases: false, values: [], propertyType: .uint8)]
        )
        let shadowed = try GenericEngine(combining: [first, second]).shadowedNames
        XCTAssertEqual(shadowed.structs, ["Shared"])
        XCTAssertEqual(shadowed.enums, ["Dup"])
    }

    // MARK: - Cross-engine references

    func testAStructResolvesAnEnumDeclaredByAnotherEngine() throws {
        // Why the game engine alone isn't enough: its structs name enums
        // that ship in the Pokemon and Genius Sonority engines.
        let gameEngine = try engine(structs: [
            map("Gift", [.abstraction(name: "species", typeName: "Species")]),
        ])
        let pokemonEngine = try engine(enums: [
            Enum(name: "Species", allowUnknownCases: false,
                 values: [.init(name: "Bulbasaur", rawValue: 1)], propertyType: .uint16),
        ])

        // Alone, the reference can't resolve at all.
        XCTAssertThrowsError(try gameEngine.getStruct("Gift") as StructDefinition)

        let combined = try GenericEngine(combining: [gameEngine, pokemonEngine])
        let definition = try combined.getStruct("Gift") as StructDefinition
        guard case .enumeration(let resolved) = definition.properties[0].type else {
            return XCTFail("species did not resolve to an enum")
        }
        XCTAssertEqual(resolved.name, "Species")
        XCTAssertEqual(try resolved.get(1).name, "Bulbasaur")
    }

    func testAStructResolvesASubStructDeclaredByAnotherEngine() throws {
        let first = try engine(structs: [map("Outer", [.subStruct(name: "inner", typeName: "Inner")])])
        let second = try engine(structs: [map("Inner", [.uint8(name: "a"), .uint8(name: "b")])])
        let combined = try GenericEngine(combining: [first, second])
        XCTAssertEqual(try combined.getStruct("Outer").length, 2)
    }

    // MARK: - Loading from folders

    func testCombinesEnginesLoadedFromFolders() throws {
        let fst = InMemoryFST()
        let gameFolder = root.folder("Game")
        let sharedFolder = root.folder("Shared")

        try engine(structs: [map("Gift", [.abstraction(name: "species", typeName: "Species")])])
            .write(to: fst, in: root, overwrite: true)
        // `write` names the folder after the engine, and every GenericEngine
        // is called the same thing, so write them one at a time and move.
        try fst.createFolder(at: gameFolder, overwrite: true)
        try moveEngine(from: root.folder("Generic Engine"), to: gameFolder, in: fst)

        try engine(enums: [Enum(name: "Species", allowUnknownCases: false,
                                values: [.init(name: "Bulbasaur", rawValue: 1)], propertyType: .uint16)])
            .write(to: fst, in: root, overwrite: true)
        try fst.createFolder(at: sharedFolder, overwrite: true)
        try moveEngine(from: root.folder("Generic Engine"), to: sharedFolder, in: fst)

        let combined = try GenericEngine(combining: [gameFolder, sharedFolder], in: fst)
        let definition = try combined.getStruct("Gift") as StructDefinition
        guard case .enumeration(let resolved) = definition.properties[0].type else {
            return XCTFail("species did not resolve to an enum")
        }
        XCTAssertEqual(resolved.name, "Species")
    }

    func testCombiningNoEnginesYieldsAnEmptyEngine() throws {
        let combined = try GenericEngine(combining: [])
        XCTAssertTrue(combined.structs.entries.isEmpty)
        XCTAssertTrue(combined.enums.entries.isEmpty)
        XCTAssertThrowsError(try combined.getStruct("Anything") as StructDefinition)
    }

    func testAMissingFolderFailsRatherThanResolvingSilently() {
        XCTAssertThrowsError(try GenericEngine(combining: [root.folder("Nope")], in: InMemoryFST()))
    }

    // MARK: - Helpers

    private func moveEngine(from source: Folder, to destination: Folder, in fst: FileSystemTree) throws {
        guard let contents = fst.inspectFolder(at: source) else {
            return XCTFail("no engine written at \(source.path)")
        }
        for file in contents.files {
            if let data = fst.readFile(at: file)?.allData {
                try fst.writeFile(data, at: destination.file(file.fileName), overwrite: true)
            }
        }
        for subFolder in contents.subFolders {
            try moveEngine(
                from: subFolder,
                to: destination.folder(subFolder.path.split(separator: "/").last.map(String.init) ?? ""),
                in: fst
            )
        }
    }
}
