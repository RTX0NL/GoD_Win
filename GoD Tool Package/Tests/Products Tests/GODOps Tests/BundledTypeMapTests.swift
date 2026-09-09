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

    private func fileChunks(_ map: TypeMap) -> [TypeMap.Chunk.EmbeddedFile] {
        map.chunks.compactMap {
            if case .file(let f) = $0 { return f }
            return nil
        }
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

    /// Every bundled map, for every region, must decode and name structs the
    /// engine defines. The maps are region-keyed because each chunk is
    /// identified by position — the DOL map by address, the REL maps by
    /// pointer-index symbol — and both move between builds.
    private static let regions = ["us", "eu", "jp"]

    func testXDDolTypeMapsDecodeForEveryRegion() throws {
        let defined = Set(XDEngine.Structs.allItems.map(\.name))
        for region in Self.regions {
            let name = "dol_typemap_\(region).json"
            let map = try decode(PokemonXD.bundledResource(named: name), "XD \(name)")
            for table in tableEntryTypes(map) {
                XCTAssertTrue(defined.contains(table.type),
                              "XD DOL \(region): unresolved struct \(table.type) for \(table.name)")
            }
            // Every region embeds at least a font and a message table in the DOL.
            let files = fileChunks(map)
            XCTAssertFalse(files.isEmpty, "XD DOL \(region) should carry embedded file chunks")
            XCTAssertTrue(files.contains { $0.extension == "fnt" },
                          "XD DOL \(region) should carry the embedded font")
            assertResolvable(map, definedTypes: defined, label: "XD DOL \(region)")
        }
    }

    /// Every XD common.rel table is typed now — the last four (PokemonStats,
    /// Battles, Pokespots, Rooms) landed together with the region-specific
    /// `BattleEU` and `RoomJP` layouts — so an unresolved type here is a
    /// regression, not a pending port.
    func testXDCommonRelTypeMapsDecodeForEveryRegion() throws {
        let defined = Set(XDEngine.Structs.allItems.map(\.name))
        for region in Self.regions {
            let name = "common_rel_typemap_\(region).json"
            let map = try decode(PokemonXD.bundledResource(named: name), "XD \(name)")
            for table in tableEntryTypes(map) {
                XCTAssertTrue(defined.contains(table.type),
                              "XD common.rel \(region): unresolved struct \(table.type) for \(table.name)")
            }
            assertResolvable(map, definedTypes: defined, label: "XD common.rel \(region)")
        }
    }

    /// The battle and room tables change stride between builds (PAL adds
    /// four per-language intro ids to a battle, JP drops four of a room's
    /// five fsys ids), so each region's map must name the layout that fits
    /// its disc.
    func testXDCommonRelTypeMapsNameTheRegionalLayouts() throws {
        func entryType(_ region: String, table: String) throws -> String? {
            let map = try decode(
                PokemonXD.bundledResource(named: "common_rel_typemap_\(region).json"),
                "XD common_rel_typemap_\(region).json"
            )
            return tableEntryTypes(map).first { $0.name == table }?.type
        }
        XCTAssertEqual(try entryType("us", table: "Battles"), "Battle")
        XCTAssertEqual(try entryType("jp", table: "Battles"), "Battle")
        XCTAssertEqual(try entryType("eu", table: "Battles"), "BattleEU")
        XCTAssertEqual(try entryType("us", table: "Rooms"), "Room")
        XCTAssertEqual(try entryType("eu", table: "Rooms"), "Room")
        XCTAssertEqual(try entryType("jp", table: "Rooms"), "RoomJP")
        for region in Self.regions {
            for spot in ["PokespotRock", "PokespotOasis", "PokespotCave", "PokespotAll"] {
                XCTAssertEqual(try entryType(region, table: spot), "PokespotEncounter", "\(region) \(spot)")
            }
        }
    }

    /// The US and PAL discs carry the six-language species/move tables in
    /// common.rel; the JP disc carries one. Losing those entries would mean
    /// the biggest string tables in the game dump as anonymous bytes.
    func testXDCommonRelTypeMapsCarryTheEmbeddedMessageTables() throws {
        for (region, expected) in [("us", 6), ("eu", 6), ("jp", 0)] {
            let map = try decode(
                PokemonXD.bundledResource(named: "common_rel_typemap_\(region).json"),
                "XD common_rel_typemap_\(region).json"
            )
            let msgs = fileChunks(map).filter { $0.extension == "msg" }
            XCTAssertEqual(msgs.count, expected, "XD common.rel \(region): embedded MSG count")
        }
    }

    func testColosseumTypeMapsDecodeForEveryRegion() throws {
        let defined = Set(ColosseumEngine.Structs.allItems.map(\.name))
        for region in Self.regions {
            let dol = try decode(
                PokemonColosseum.bundledResource(named: "dol_typemap_\(region).json"),
                "Colo dol_typemap_\(region).json"
            )
            XCTAssertTrue(fileChunks(dol).contains { $0.extension == "fnt" },
                          "Colo DOL \(region) should carry the embedded font")

            let rel = try decode(
                PokemonColosseum.bundledResource(named: "common_rel_typemap_\(region).json"),
                "Colo common_rel_typemap_\(region).json"
            )
            // Every Colosseum common.rel table is typed now, so an unresolved
            // type is a regression, not a pending port.
            for table in tableEntryTypes(rel) {
                XCTAssertTrue(defined.contains(table.type),
                              "Colo common.rel \(region): unresolved struct \(table.type) for \(table.name)")
            }
            assertResolvable(rel, definedTypes: defined, label: "Colo common.rel \(region)")
        }
    }

    /// Colosseum's PAL disc carries per-language copies of one field in three
    /// tables, so its map must name the wider layouts and the others the
    /// shared ones.
    func testColosseumCommonRelTypeMapsNameTheRegionalLayouts() throws {
        func entryType(_ region: String, table: String) throws -> String? {
            let map = try decode(
                PokemonColosseum.bundledResource(named: "common_rel_typemap_\(region).json"),
                "Colo common_rel_typemap_\(region).json"
            )
            return tableEntryTypes(map).first { $0.name == table }?.type
        }
        for (table, shared, pal) in [("Rooms", "Room", "RoomEU"), ("Battles", "Battle", "BattleEU"), ("BattleFields", "BattleField", "BattleFieldEU")] {
            XCTAssertEqual(try entryType("us", table: table), shared)
            XCTAssertEqual(try entryType("jp", table: table), shared)
            XCTAssertEqual(try entryType("eu", table: table), pal)
        }
    }

    /// `tableres2.rel` lives inside `common_dvdeth.fsys` on the US and PAL
    /// discs (JP has no such archive) and is byte-identical between them, so
    /// it gets one map rather than a region-keyed set.
    func testTableres2TypeMap() throws {
        let map = try decode(
            PokemonXD.bundledResource(named: "tableres2_typemap.json"),
            "XD tableres2_typemap.json"
        )
        let files = fileChunks(map)
        XCTAssertEqual(files.filter { $0.extension == "fnt" }.count, 1,
                       "tableres2 carries exactly one font")
        XCTAssertEqual(files.filter { $0.extension == "msg" }.count, 7,
                       "tableres2 carries seven language message tables")
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
