//
//  StructCSVSchemaTests.swift
//
//  The flattening contract: which leaves get a column, what each column is
//  called, and where its bytes are. Both halves of the codec read offsets
//  from here, so a wrong offset here is a wrong offset everywhere.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructCSVSchemaTests: XCTestCase {

    private func headers(_ definition: StructDefinition) -> [String] {
        StructCSVSchema.columns(of: definition).map(\.header)
    }

    private func offsets(_ definition: StructDefinition) -> [String: Int] {
        Dictionary(
            StructCSVSchema.columns(of: definition).map { ($0.header, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func definition(
        _ name: String,
        _ properties: [StructDefinition.Property],
        alignment: StructAlignmentStyles = .none
    ) -> StructDefinition {
        StructDefinition(name: name, wordSize: 4, alignmentStyle: alignment, properties: properties)
    }

    // MARK: - Scalars

    func testScalarsGetOneColumnEachInDeclarationOrder() {
        let def = definition("Scalars", [
            .uint8(name: "a"),
            .int16(name: "b"),
            .float(name: "c"),
            .boolean(name: "d"),
        ])
        XCTAssertEqual(headers(def), ["a", "b", "c", "d"])
        XCTAssertEqual(offsets(def), ["a": 0, "b": 1, "c": 3, "d": 7])
    }

    func testVoidGetsNoColumn() {
        let def = definition("WithVoid", [
            .uint8(name: "a"),
            .init(name: "nothing", type: .primitive(.void)),
            .uint8(name: "b"),
        ])
        XCTAssertEqual(headers(def), ["a", "b"])
        XCTAssertEqual(offsets(def)["b"], 1)
    }

    // MARK: - Padding

    func testPaddingGetsNoColumnButStillAdvancesTheOffset() {
        let def = definition("Padded", [
            .uint8(name: "a"),
            .padding(length: 3),
            .uint32(name: "b"),
        ])
        XCTAssertEqual(headers(def), ["a", "b"])
        XCTAssertEqual(offsets(def)["b"], 4)
    }

    func testBarePaddingTypeGetsNoColumn() {
        let def = definition("BarePadding", [
            .uint8(name: "a"),
            .init(name: "gap", type: .padding(length: 2)),
            .uint8(name: "b"),
        ])
        XCTAssertEqual(headers(def), ["a", "b"])
        XCTAssertEqual(offsets(def)["b"], 3)
    }

    // MARK: - Sub-structs

    func testSubStructColumnsAreDottedPaths() {
        let stats = definition("Stats", [.uint8(name: "attack"), .uint8(name: "defense")])
        let def = definition("Mon", [
            .uint16(name: "id"),
            .subStruct(name: "base", defintion: stats),
        ])
        XCTAssertEqual(headers(def), ["id", "base.attack", "base.defense"])
        XCTAssertEqual(offsets(def), ["id": 0, "base.attack": 2, "base.defense": 3])
    }

    func testNestedSubStructsNestThePath() {
        let inner = definition("Inner", [.uint8(name: "leaf")])
        let middle = definition("Middle", [.subStruct(name: "inner", defintion: inner)])
        let def = definition("Outer", [.subStruct(name: "middle", defintion: middle)])
        XCTAssertEqual(headers(def), ["middle.inner.leaf"])
    }

    // MARK: - Arrays

    func testArrayColumnsAreOneIndexed() {
        let def = definition("Moves", [.array(name: "moves", count: 4, of: .uint16)])
        XCTAssertEqual(headers(def), ["moves[1]", "moves[2]", "moves[3]", "moves[4]"])
        XCTAssertEqual(offsets(def)["moves[1]"], 0)
        XCTAssertEqual(offsets(def)["moves[4]"], 6)
    }

    func testArrayOfSubStructsCombinesIndexAndPath() {
        let slot = definition("Slot", [.uint8(name: "id"), .uint8(name: "pp")])
        let def = definition("Deck", [
            .array(name: "slots", count: 2, of: .subStruct(slot)),
        ])
        XCTAssertEqual(headers(def), ["slots[1].id", "slots[1].pp", "slots[2].id", "slots[2].pp"])
        XCTAssertEqual(offsets(def)["slots[2].id"], 2)
    }

    func testNestedArraysNestTheIndices() {
        let def = definition("Grid", [
            .array(name: "grid", count: 2, of: .array(.uint8, count: 2)),
        ])
        XCTAssertEqual(headers(def), ["grid[1][1]", "grid[1][2]", "grid[2][1]", "grid[2][2]"])
        XCTAssertEqual(offsets(def)["grid[2][2]"], 3)
    }

    func testCharacterArrayIsASingleStringColumn() {
        let def = definition("Named", [
            .string(name: "name", format: .utf8, length: 8),
            .uint8(name: "after"),
        ])
        XCTAssertEqual(headers(def), ["name", "after"])
        XCTAssertEqual(offsets(def)["after"], 8)
    }

    // MARK: - Labels

    func testLabelKeysStayZeroIndexedForCompatibility() {
        // The header is 1-indexed for readability, but the `labelValues`
        // key is the 0-indexed form `TypedDataImporter` resolves against.
        let def = definition("Pointers", [
            .label(name: "single"),
            .array(name: "many", count: 2, of: .label),
        ])
        let columns = StructCSVSchema.columns(of: def)
        XCTAssertEqual(columns.map(\.header), ["single", "many[1]", "many[2]"])
        XCTAssertEqual(columns.map(\.labelKey), ["single", "many[0]", "many[1]"])
    }

    func testNestedLabelKeyIsAPath() {
        let inner = definition("Inner", [.label(name: "ptr")])
        let def = definition("Outer", [.subStruct(name: "sub", defintion: inner)])
        XCTAssertEqual(StructCSVSchema.columns(of: def).first?.labelKey, "sub.ptr")
    }

    // MARK: - Alignment

    func testCStyleAlignmentMatchesTheStructDataWalk() {
        let def = definition("Aligned", [
            .uint8(name: "a"),
            .uint32(name: "b"),
        ], alignment: .cStyle)
        // `b` aligns to 4, so it starts at 4 rather than 1 — the same walk
        // StructData.encode/populate perform.
        XCTAssertEqual(offsets(def), ["a": 0, "b": 4])
        XCTAssertEqual(def.offset(for: "b"), 4)
    }

    // MARK: - Empty

    func testDefinitionWithNoLeavesHasNoColumns() {
        let def = definition("Empty", [.padding(length: 4)])
        XCTAssertTrue(StructCSVSchema.columns(of: def).isEmpty)
    }

    // MARK: - Bit fields

    private var flagsByte: StructDefinition.Property {
        .bits(name: "flags", fields: [
            .number(name: "kind", bits: 0...2),
            .flag(name: "visible", bit: 3),
            .number(name: "unknown_4_7", bits: 4...7),
        ])
    }

    func testEachBitFieldGetsItsOwnDottedColumn() {
        let def = definition("Packed", [.uint8(name: "before"), flagsByte, .uint8(name: "after")])
        XCTAssertEqual(headers(def), [
            "before", "flags.kind", "flags.visible", "flags.unknown_4_7", "after",
        ])
    }

    func testBitColumnsCarryTheirContainersOffset() {
        // A bit field has no byte of its own, so every column of one
        // container shares the container's offset — and the next property
        // still starts one byte later.
        let def = definition("Packed", [.uint8(name: "before"), flagsByte, .uint8(name: "after")])
        XCTAssertEqual(offsets(def), [
            "before": 0, "flags.kind": 1, "flags.visible": 1, "flags.unknown_4_7": 1, "after": 2,
        ])
    }

    func testNoColumnIsEmittedForTheContainerItself() {
        // Two columns writing the same bytes would make the decoded row
        // depend on header order.
        let def = definition("Packed", [flagsByte])
        XCTAssertFalse(headers(def).contains("flags"))
    }

    func testBitColumnsCarryTheFieldNotTheContainer() {
        let def = definition("Packed", [flagsByte])
        let columns = StructCSVSchema.columns(of: def)
        guard case .bits(let layout, let field) = columns[1].kind else {
            return XCTFail("expected a bit column")
        }
        XCTAssertEqual(field.name, "visible")
        XCTAssertEqual(layout.storage, .uint8)
        // The column reads the whole container, not one byte of a wider one.
        XCTAssertEqual(columns[1].length, 1)
    }

    func testBitFieldsInsideASubStructAndAnArray() {
        let inner = StructDefinition(
            name: "Inner", wordSize: 4, alignmentStyle: .none, properties: [flagsByte]
        )
        let def = definition("Outer", [
            .subStruct(name: "sub", defintion: inner),
            .bitsArray(name: "pair", count: 2, fields: [
                .flag(name: "on", bit: 0),
                .number(name: "rest", bits: 1...7),
            ]),
        ])
        XCTAssertEqual(headers(def), [
            "sub.flags.kind", "sub.flags.visible", "sub.flags.unknown_4_7",
            "pair[1].on", "pair[1].rest", "pair[2].on", "pair[2].rest",
        ])
        XCTAssertEqual(offsets(def)["pair[2].on"], 2)
    }

    func testAWiderContainerKeepsOneOffsetForEveryField() {
        let def = definition("Wide", [
            .bits(name: "word", storage: .uint16, fields: [
                .number(name: "high", bits: 0...3),
                .number(name: "low", bits: 4...15),
            ]),
            .uint8(name: "after"),
        ])
        XCTAssertEqual(offsets(def), ["word.high": 0, "word.low": 0, "after": 2])
    }
}
