//
//  PBRCommonTableStructTests.swift
//  PBRTests
//
//  Pins the PBR engine's `common.fsys` struct definitions against the real
//  disc. Every table's entry struct has to be exactly as long as the stride
//  the disc declares in the table header's +0x04 word, or the struct can't
//  tile the entry array and the table falls back to raw bytes. The expected
//  strides here are measured from the PAL disc (RPBP01) and mirrored into
//  `PBREngine.Data.defaultCommonTables`, so these tests catch either side
//  drifting.
//

import XCTest
import Structs
import GoDEngine
@testable import PBR

final class PBRCommonTableStructTests: XCTestCase {

    private func engine() throws -> PBREngine {
        try PBREngine.defaults()
    }

    private func length(_ name: String) throws -> Int {
        try engine().getStruct(name).length
    }

    // MARK: - Engine integrity

    /// `defaults()` resolves every registered struct, so this fails if a
    /// struct references a missing sub-struct or enum, names a property
    /// invalidly, or duplicates one.
    func testEngineDefaultsResolveEveryStruct() throws {
        XCTAssertNoThrow(try PBREngine.defaults())
    }

    // MARK: - Container format

    func testCommonTableHeaderIsThirtyBytesOfWordsPlusReserved() throws {
        XCTAssertEqual(try length("PBRCommonTableHeader"), 0x30)
        XCTAssertEqual(try length("PBRCommonTableNameRecord"), 0x08)
        XCTAssertEqual(try length("PBRCommonTableStringHeader"), 0x02)
        XCTAssertEqual(try length("PBRCommonTableRelocation"), 0x04)
    }

    /// The format constants the ops layer reads must name structs that
    /// actually exist.
    func testCommonTableFormatNamesRegisteredStructs() throws {
        let format = try engine().data.commonTableFormat
        for name in [
            format.headerStructName,
            format.nameRecordStructName,
            format.stringRecordStructName,
            format.relocationStructName
        ] {
            XCTAssertNoThrow(try length(name), "format references unregistered struct \(name)")
        }
        XCTAssertEqual(format.headerSize, 0x30)
    }

    // MARK: - Pokémon model body map

    /// The body map is the whole point of the model table: 25 bone slots at
    /// +0x19 and 22 animation slots at +0x32 have to land exactly, or every
    /// slot after the first misread one is off by the drift.
    func testPokemonModelBodyMapLengths() throws {
        XCTAssertEqual(try length("PBRModelBoneMap"), 0x19, "25 bone slots")
        XCTAssertEqual(try length("PBRModelAnimationMap"), 0x16, "22 animation slots")
        XCTAssertEqual(try length("PBRPokemonModel"), 0x48, "model table stride")
    }

    /// Each slot enum must name exactly as many roles as the corresponding
    /// map struct has fields, and the raw values must be the slot indexes
    /// 0..<count with no gaps — the enum is how callers address a slot
    /// numerically, so a gap would silently point at the wrong byte.
    func testSlotEnumsMatchTheBodyMapStructs() throws {
        let engine = try engine()

        let boneMap = try engine.getStruct("PBRModelBoneMap")
        let boneSlots = try XCTUnwrap(engine.getEnum("PBRModelBoneSlot"))
        XCTAssertEqual(boneSlots.values.count, boneMap.properties.count)
        XCTAssertEqual(boneSlots.values.map(\.rawValue), Array(0..<boneMap.properties.count))

        let animMap = try engine.getStruct("PBRModelAnimationMap")
        let animSlots = try XCTUnwrap(engine.getEnum("PBRModelAnimationSlot"))
        XCTAssertEqual(animSlots.values.count, animMap.properties.count)
        XCTAssertEqual(animSlots.values.map(\.rawValue), Array(0..<animMap.properties.count))
    }

    // MARK: - Table registry

    /// Every table descriptor must bind to a registered struct whose length
    /// equals the entry stride measured from the disc.
    func testEveryTableStructTilesItsEntryStride() throws {
        let engine = try engine()
        for table in engine.data.commonTables {
            guard let structName = table.structName else { continue }
            let resolved = try length(structName)
            XCTAssertEqual(
                resolved, table.entrySize,
                "\(table.name) (common_\(table.index)): \(structName) is \(resolved) bytes, disc stride is \(table.entrySize)"
            )
        }
    }

    /// Strides measured directly from the PAL disc's table headers, kept
    /// here as an independent copy of the registry so a typo in one is
    /// caught by the other.
    func testRegistryStridesMatchTheDisc() throws {
        let discStrides: [Int: Int] = [
            0: 0x10, 1: 0x76, 2: 0x0C, 3: 0xBA, 4: 0x12, 5: 0x194, 6: 0x48,
            7: 0x14, 8: 0x34, 9: 0x2A, 10: 0x20, 11: 0x5C, 12: 0x0C, 13: 0x2C,
            14: 0x0E, 15: 0x04, 16: 0x06, 17: 0x0C, 18: 0x20, 19: 0x28,
            20: 0x0E, 21: 0x0C, 22: 0x08, 23: 0x04, 24: 0x3C, 25: 0x06,
            26: 0x2C, 27: 0x54, 28: 0x0E, 29: 0x04, 30: 0x18, 31: 0x1C, 32: 0x50,
        ]
        let tables = try engine().data.commonTables
        XCTAssertEqual(tables.count, discStrides.count, "one descriptor per common.fsys table")
        for table in tables {
            XCTAssertEqual(table.entrySize, discStrides[table.index],
                           "\(table.name) stride")
        }
    }

    /// The two index enums are the addressable form of the registry, so
    /// they have to agree with it — including that the JP disc is missing
    /// `ColosseumsUnknown` and renumbers everything else.
    func testTableIndexEnumsAgreeWithTheRegistry() throws {
        let engine = try engine()
        let tables = engine.data.commonTables

        let us = try XCTUnwrap(engine.getEnum("PBRCommonTableIndex"))
        XCTAssertEqual(
            us.values.map { ($0.rawValue, $0.name) }.sorted { $0.0 < $1.0 }.map(\.1),
            tables.sorted { $0.index < $1.index }.map(\.name)
        )

        let jp = try XCTUnwrap(engine.getEnum("PBRCommonTableIndexJP"))
        let jpTables = tables.compactMap { table in
            table.japaneseIndex.map { (index: $0, name: table.name) }
        }
        XCTAssertEqual(jpTables.count, tables.count - 1, "TutorialData is US/PAL only")
        XCTAssertEqual(
            jp.values.map { ($0.rawValue, $0.name) }.sorted { $0.0 < $1.0 }.map(\.1),
            jpTables.sorted { $0.index < $1.index }.map(\.name)
        )
        XCTAssertEqual(Set(jpTables.map(\.index)).count, jpTables.count, "JP indexes are unique")
        XCTAssertEqual(jpTables.map(\.index).sorted(), Array(0..<jpTables.count), "JP indexes are contiguous")
    }

    /// Lookup helpers resolve a table both by name and by file index, and
    /// the index lookup must respect the disc's ordering.
    func testTableLookupsRespectDiscOrdering() throws {
        let engine = try engine()

        XCTAssertEqual(engine.commonTable(named: "PokemonModels")?.index, 6)
        XCTAssertEqual(engine.commonTable(fileIndex: 6, japanese: false)?.name, "PokemonModels")
        XCTAssertEqual(engine.commonTable(fileIndex: 12, japanese: true)?.name, "PokemonModels")
        // Index 6 means a different table on a JP disc.
        XCTAssertEqual(engine.commonTable(fileIndex: 6, japanese: true)?.name, "PokemonIcons")
        // TutorialData was added for the international release, so it has no
        // JP counterpart; JP index 9 is ColosseumsUnknown instead.
        XCTAssertNil(engine.commonTable(named: "TutorialData")?.japaneseIndex)
        XCTAssertEqual(engine.commonTable(fileIndex: 9, japanese: true)?.name, "ColosseumsUnknown")
        // …and on a JP disc it binds the JP record.
        XCTAssertEqual(engine.commonTable(fileIndex: 9, japanese: true)?.structName,
                       "PBRColosseumsUnknownJP")
        XCTAssertEqual(engine.commonTable(fileIndex: 3, japanese: false)?.structName,
                       "PBRColosseumsUnknown")
    }

    func testGameIDsSelectTheRightTableOrdering() {
        XCTAssertFalse(PokemonBattleRevolution.usesJapaneseTableOrder(gameID: PokemonBattleRevolution.gameIDUS))
        XCTAssertFalse(PokemonBattleRevolution.usesJapaneseTableOrder(gameID: PokemonBattleRevolution.gameIDEU))
        XCTAssertTrue(PokemonBattleRevolution.usesJapaneseTableOrder(gameID: PokemonBattleRevolution.gameIDJP))
    }

    // MARK: - Sub-struct lengths

    func testSubStructLengths() throws {
        XCTAssertEqual(try length("PBREvolution"), 0x06)
        XCTAssertEqual(try length("PBRLevelUpMove"), 0x04)
        XCTAssertEqual(try length("PBRColosseumTrainerDeck"), 0x10)
        XCTAssertEqual(try length("PBRColosseumPokemonDecks"), 0x08)
    }
}
