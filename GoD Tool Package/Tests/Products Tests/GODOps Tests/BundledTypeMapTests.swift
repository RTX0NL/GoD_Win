//
//  BundledTypeMapTests.swift
//
//  Guards the type-map resources shipped with the XD and Colosseum engines:
//  each must decode as a `TypeMap` and (for tables whose struct type exists in
//  the engine) name a struct the engine actually defines. Tables whose struct
//  is not yet ported are allowed — they disassemble to raw chunks and upgrade
//  automatically once the struct lands — but are reported so coverage is
//  visible. The engine folders whose structs resolve these types are supplied
//  by the disassembly op config (`engines`), not by the map.
//

import XCTest
import Foundation
import GoDFoundation
import Disassembler
import Dolphin
import Structs
import XD
import Colosseum
import Pokemon
@testable import GODOps

final class BundledTypeMapTests: XCTestCase {

    private func decode(_ data: GoDData?, _ name: String) throws -> TypeMap {
        let bytes = try XCTUnwrap(data, "missing bundled resource \(name)")
        return try JSONDecoder().decode(TypeMap.self, from: Data(bytes.rawBytes))
    }

    private func tableEntryTypes(_ map: TypeMap) -> [(name: String, type: String)] {
        map.chunks.compactMap {
            if case .table(let t) = $0 { return (t.name, t.entryType) }
            return nil
        }
    }

    /// Every table entry type either resolves against `definedTypes` or is
    /// reported as pending (not an error — degrades to a raw chunk).
    private func assertResolvable(_ map: TypeMap, definedTypes: Set<String>, label: String) {
        var pending = [String]()
        for table in tableEntryTypes(map) where !definedTypes.contains(table.type) {
            pending.append("\(table.name)→\(table.type)")
        }
        if !pending.isEmpty {
            print("[\(label)] \(map.chunks.count) chunks; \(pending.count) pending struct types: \(pending.joined(separator: ", "))")
        }
    }

    func testXDDolTypeMap() throws {
        let map = try decode(PokemonXD.bundledResource(named: "dol_typemap.json"), "XD dol_typemap.json")
        let defined = Set(XDEngine.Structs.allItems.map(\.name))
        // The XD DOL map's tables all have ported structs — full coverage.
        for table in tableEntryTypes(map) {
            XCTAssertTrue(defined.contains(table.type), "XD DOL: unresolved struct \(table.type) for \(table.name)")
        }
        // And it carries the embedded MSG file chunks.
        let files = map.chunks.filter { if case .file = $0 { return true }; return false }
        XCTAssertGreaterThanOrEqual(files.count, 3, "XD DOL map should include embedded MSG files")
        assertResolvable(map, definedTypes: defined, label: "XD DOL")
    }

    func testXDCommonRelTypeMap() throws {
        let map = try decode(PokemonXD.bundledResource(named: "common_rel_typemap.json"), "XD common_rel_typemap.json")
        assertResolvable(map, definedTypes: Set(XDEngine.Structs.allItems.map(\.name)), label: "XD common.rel")
    }

    func testColosseumCommonRelTypeMap() throws {
        let map = try decode(PokemonColosseum.bundledResource(named: "common_rel_typemap.json"), "Colo common_rel_typemap.json")
        let defined = Set(ColosseumEngine.Structs.allItems.map(\.name))
        assertResolvable(map, definedTypes: defined, label: "Colo common.rel")
        // The one ported Colo struct must resolve so at least one table is typed.
        XCTAssertTrue(tableEntryTypes(map).contains { $0.type == "CharacterModel" && defined.contains("CharacterModel") })
    }

    /// The engine folders that resolve a map's struct types come from the
    /// operation (via `resolveStructTypes(engineFolders:)`), not the map.
    func testResolveStructTypesUsesConfigEngineFolders() throws {
        let fst = InMemoryFST()
        let engineFolder = installEngine(try XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let map = TypeMap(chunks: [
            .table(.init(name: "CharacterModels", start: "x", entryType: "CharacterModel"))
        ])

        // Resolves from the config-supplied engine folder.
        let resolved = resolveStructTypes(from: map, engineFolders: [engineFolder], fileSystem: fst, logger: nil)
        XCTAssertNotNil(resolved["CharacterModel"], "should resolve from the supplied engine folder")

        // An unresolvable type stays unresolved (chunk would degrade to raw).
        let unknown = TypeMap(chunks: [.table(.init(name: "Nope", start: "x", entryType: "NoSuchStruct"))])
        XCTAssertNil(resolveStructTypes(from: unknown, engineFolders: [engineFolder], fileSystem: fst, logger: nil)["NoSuchStruct"])
    }

    /// There is deliberately no fallback to a built-in engine. Resolving one
    /// game's type map against another game's structs is worse than not
    /// resolving it: Colosseum and XD both declare `CharacterModel`, at 0xDC
    /// and 0x34 bytes, so the fallback would silently read a Colosseum table
    /// at a quarter of its stride and report it as typed.
    func testResolveStructTypesDoesNotFallBackToABuiltInEngine() throws {
        let fst = InMemoryFST()
        let map = TypeMap(chunks: [
            .table(.init(name: "CharacterModels", start: "x", entryType: "CharacterModel"))
        ])
        XCTAssertTrue(resolveStructTypes(from: map, engineFolders: [], fileSystem: fst, logger: nil).isEmpty)
        // A folder that isn't an engine is the same story.
        XCTAssertTrue(
            resolveStructTypes(from: map, engineFolders: [Folder("/nope")], fileSystem: fst, logger: nil).isEmpty
        )
    }

    /// Enum fields have to survive resolution. The local resolver this
    /// replaced mapped every `.enumeration` to `uint8` and never read the
    /// `Enumerations/` folder, so no typed chunk ever had one.
    ///
    /// (Every enum the XD structs reference is declared by the XD engine
    /// itself, so this doesn't exercise cross-engine lookup — that's
    /// `GenericEngineCombiningTests`. The Pokemon folder is here because it
    /// is what ProjectSetup now seeds, and it must not disturb resolution.)
    func testResolveStructTypesKeepsEnumFields() throws {
        let fst = InMemoryFST()
        let engines = Folder("/project/Engines")
        let gameFolder = installEngine(try XDEngine.defaults(), under: engines, in: fst)
        let pokemonFolder = installEngine(try PokemonEngine.defaults(), under: engines, in: fst)

        // A struct the XD engine declares with an enum-typed field.
        let withEnum = XDEngine.Structs.allItems.first { map in
            map.properties.contains { if case .enumeration = $0.type { return true }; return false }
        }
        let structName: String = try XCTUnwrap(withEnum?.name, "expected an XD struct with an enum field")
        let map = TypeMap(chunks: [.table(.init(name: "T", start: "x", entryType: structName))])

        let resolved = resolveStructTypes(
            from: map, engineFolders: [gameFolder, pokemonFolder], fileSystem: fst, logger: nil
        )
        let definition = try XCTUnwrap(resolved[structName])
        let enumFields = definition.properties.filter {
            if case .enumeration = $0.type { return true }
            return false
        }
        XCTAssertFalse(
            enumFields.isEmpty,
            "enum fields must survive resolution — the previous local resolver mapped them all to uint8"
        )
        // And they must carry their real cases, not just be enum-shaped.
        for field in enumFields {
            guard case .enumeration(let resolvedEnum) = field.type else { continue }
            XCTAssertFalse(
                resolvedEnum.values.isEmpty,
                "enum '\(resolvedEnum.name)' resolved with no cases — the Enumerations folder wasn't read"
            )
        }
    }
}
