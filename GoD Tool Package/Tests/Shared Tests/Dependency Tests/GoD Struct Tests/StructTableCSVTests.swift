//
//  StructTableCSVTests.swift
//
//  Encode and decode are tested separately rather than only as a pair, so
//  a matching bug on both sides can't hide: the encoder is checked against
//  literal expected text, the decoder against literal expected bytes. The
//  round trip then pins byte identity on top of that.
//

import Foundation
import GoDFoundation
@testable import Structs
import XCTest

final class StructTableCSVTests: XCTestCase {

    // MARK: - Fixtures

    private let colors = Enum(
        name: "Colors",
        allowUnknownCases: false,
        values: [
            .init(name: "Red", rawValue: 0),
            .init(name: "Green", rawValue: 1),
            .init(name: "Blue", rawValue: 2),
        ],
        propertyType: .uint8
    )

    private let openColors = Enum(
        name: "Open Colors",
        allowUnknownCases: true,
        values: [.init(name: "Red", rawValue: 0)],
        propertyType: .uint8
    )

    private func definition(
        _ name: String,
        _ properties: [StructDefinition.Property],
        alignment: StructAlignmentStyles = .none
    ) -> StructDefinition {
        StructDefinition(name: name, wordSize: 4, alignmentStyle: alignment, properties: properties)
    }

    private func entry(_ definition: StructDefinition, _ bytes: [UInt8]) -> StructData {
        StructData(definition: definition, data: GoDData(byteStream: bytes, byteOrder: .big))
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: - Encoding

    func testEncodesHeaderThenOneRowPerEntry() throws {
        let def = definition("Pair", [.uint8(name: "a"), .int16(name: "b")])
        let text = try StructTableCSV.encode(
            entries: [entry(def, [0x01, 0xFF, 0xFE]), entry(def, [0x02, 0x00, 0x05])],
            definition: def
        )
        XCTAssertEqual(lines(text), ["a,b", "1,-2", "2,5", ""])
    }

    func testEnumEncodesAsItsCaseName() throws {
        let def = definition("Painted", [.abstraction(name: "color", enumeration: colors)])
        let text = try StructTableCSV.encode(entries: [entry(def, [0x02])], definition: def)
        XCTAssertEqual(lines(text)[1], "Blue")
    }

    func testUnnamedEnumValueEncodesAsAnIntegerEvenWhenUnknownCasesAreAllowed() throws {
        // Not `Open_Colors_9`: in CSV every cell is text, so a synthesized
        // name could only be told from a real one by rebuilding the enum's
        // current name. An unnamed value is a number.
        let def = definition("Painted", [.abstraction(name: "color", enumeration: openColors)])
        let text = try StructTableCSV.encode(entries: [entry(def, [0x09])], definition: def)
        XCTAssertEqual(lines(text)[1], "9")
    }

    func testBooleansEncodeAsTrueAndFalse() throws {
        let def = definition("Flags", [.boolean(name: "on")])
        XCTAssertEqual(lines(try StructTableCSV.encode(entries: [entry(def, [1])], definition: def))[1], "true")
        XCTAssertEqual(lines(try StructTableCSV.encode(entries: [entry(def, [0])], definition: def))[1], "false")
    }

    func testNonBooleanByteFailsRatherThanBeingCollapsed() {
        let def = definition("Flags", [.boolean(name: "on")])
        XCTAssertThrowsError(try StructTableCSV.encode(entries: [entry(def, [2])], definition: def)) { error in
            guard case StructCSVError.nonBooleanByte(let column, _, let raw, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(column, "on")
            XCTAssertEqual(raw, 2)
        }
    }

    func testFiniteFloatsEncodeAsShortestDecimal() throws {
        let def = definition("Floats", [.float(name: "f")])
        let text = try StructTableCSV.encode(entries: [entry(def, [0x3F, 0xC0, 0x00, 0x00])], definition: def)
        XCTAssertEqual(lines(text)[1], "1.5")
    }

    func testCanonicalNonFiniteFloatsEncodeAsNamedSpellings() throws {
        let def = definition("Floats", [.float(name: "f")])
        func cell(_ bytes: [UInt8]) throws -> String {
            lines(try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def))[1]
        }
        XCTAssertEqual(try cell([0x7F, 0x80, 0x00, 0x00]), "Infinity")
        XCTAssertEqual(try cell([0xFF, 0x80, 0x00, 0x00]), "-Infinity")
        XCTAssertEqual(try cell([0x7F, 0xC0, 0x00, 0x00]), "NaN")
    }

    func testCanonicalNonFiniteDoublesEncodeAsNamedSpellings() throws {
        let def = definition("Doubles", [.double(name: "d")])
        func cell(_ bytes: [UInt8]) throws -> String {
            lines(try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def))[1]
        }
        XCTAssertEqual(try cell([0x7F, 0xF0, 0, 0, 0, 0, 0, 0]), "Infinity")
        XCTAssertEqual(try cell([0xFF, 0xF0, 0, 0, 0, 0, 0, 0]), "-Infinity")
        XCTAssertEqual(try cell([0x7F, 0xF8, 0, 0, 0, 0, 0, 0]), "NaN")
    }

    func testNaNWithAPayloadFallsBackToItsBitPattern() throws {
        // IEEE-754 gives NaN a 22-bit payload that the spelling "NaN" can't
        // carry, so a signalling or payload-bearing NaN keeps its bits. Real
        // data has float-typed fields that aren't really floats.
        let def = definition("Floats", [.float(name: "f")])
        func cell(_ bytes: [UInt8]) throws -> String {
            lines(try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def))[1]
        }
        XCTAssertEqual(try cell([0x7F, 0xA0, 0x00, 0x00]), "0x7FA00000")   // signalling
        XCTAssertEqual(try cell([0x7F, 0xC0, 0x00, 0x01]), "0x7FC00001")   // quiet, payload 1
        XCTAssertEqual(try cell([0xFF, 0xC0, 0x00, 0x00]), "0xFFC00000")   // negative NaN
    }

    func testNonFiniteSpellingsDecodeToTheirExactBits() throws {
        let floats = definition("Floats", [.float(name: "f")])
        func floatBytes(_ cell: String) throws -> [UInt8] {
            try StructTableCSV.decode("f\n\(cell)\n", definition: floats).entries[0].data.rawBytes
        }
        XCTAssertEqual(try floatBytes("Infinity"), [0x7F, 0x80, 0x00, 0x00])
        XCTAssertEqual(try floatBytes("-Infinity"), [0xFF, 0x80, 0x00, 0x00])
        XCTAssertEqual(try floatBytes("NaN"), [0x7F, 0xC0, 0x00, 0x00])
        // Spelling variants a person might type, matched case-insensitively.
        XCTAssertEqual(try floatBytes("nan"), [0x7F, 0xC0, 0x00, 0x00])
        XCTAssertEqual(try floatBytes("inf"), [0x7F, 0x80, 0x00, 0x00])
        XCTAssertEqual(try floatBytes("-INF"), [0xFF, 0x80, 0x00, 0x00])

        let doubles = definition("Doubles", [.double(name: "d")])
        func doubleBytes(_ cell: String) throws -> [UInt8] {
            try StructTableCSV.decode("d\n\(cell)\n", definition: doubles).entries[0].data.rawBytes
        }
        XCTAssertEqual(try doubleBytes("Infinity"), [0x7F, 0xF0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(try doubleBytes("-Infinity"), [0xFF, 0xF0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(try doubleBytes("NaN"), [0x7F, 0xF8, 0, 0, 0, 0, 0, 0])
    }

    func testNonFiniteValuesRoundTrip() throws {
        let def = definition("Floats", [.float(name: "f"), .double(name: "d")])
        for floatBits: [UInt8] in [
            [0x7F, 0x80, 0x00, 0x00],   // +Inf
            [0xFF, 0x80, 0x00, 0x00],   // -Inf
            [0x7F, 0xC0, 0x00, 0x00],   // canonical NaN
            [0x7F, 0xA0, 0x00, 0x00],   // signalling NaN, kept as bits
        ] {
            let bytes = floatBits + [0x7F, 0xF8, 0, 0, 0, 0, 0, 0]
            let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
            let rebuilt = try StructTableCSV.decode(text, definition: def).entries[0]
            XCTAssertEqual(rebuilt.data.rawBytes, bytes)
        }
    }

    func testStringsWithCommasAreQuoted() throws {
        let def = definition("Named", [.string(name: "name", format: .utf8, length: 8)])
        let bytes: [UInt8] = Array("a,b".utf8) + [0, 0, 0, 0, 0]
        let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
        XCTAssertEqual(lines(text)[1], "\"a,b\"")
    }

    func testLabelEncodesAsItsRecordedName() throws {
        let def = definition("Pointers", [.label(name: "ptr")])
        let structData = entry(def, [0x80, 0x00, 0x40, 0x00])
        structData.labelValues["ptr"] = "someSymbol"
        let text = try StructTableCSV.encode(entries: [structData], definition: def)
        XCTAssertEqual(lines(text)[1], "someSymbol")
    }

    func testUnnamedLabelFallsBackToTheRawPointer() throws {
        // `TypedDataExporter` records names for top-level labels only, so a
        // label array's elements arrive with no name. Emitting "" would drop
        // the pointer silently.
        let def = definition("Pointers", [.array(name: "ptrs", count: 2, of: .label)])
        let bytes: [UInt8] = [0x80, 0x00, 0x40, 0x00] + [0, 0, 0, 0]
        let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
        XCTAssertEqual(lines(text)[1], "lbl_80004000,")
    }

    func testDefinitionWithNoColumnsFailsToEncode() {
        let def = definition("Empty", [.padding(length: 4)])
        XCTAssertThrowsError(try StructTableCSV.encode(entries: [], definition: def)) { error in
            guard case StructCSVError.noColumns = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Decoding

    func testDecodesValuesIntoBytes() throws {
        let def = definition("Pair", [.uint8(name: "a"), .int16(name: "b")])
        let result = try StructTableCSV.decode("a,b\n1,-2\n255,5\n", definition: def)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].data.rawBytes, [0x01, 0xFF, 0xFE])
        XCTAssertEqual(result.entries[1].data.rawBytes, [0xFF, 0x00, 0x05])
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testDecodesEnumByCaseNameCaseInsensitively() throws {
        let def = definition("Painted", [.abstraction(name: "color", enumeration: colors)])
        XCTAssertEqual(try StructTableCSV.decode("color\nBlue\n", definition: def).entries[0].data.rawBytes, [2])
        XCTAssertEqual(try StructTableCSV.decode("color\ngreen\n", definition: def).entries[0].data.rawBytes, [1])
    }

    func testDecodesEnumByRawValueAndBySynthesizedName() throws {
        let def = definition("Painted", [.abstraction(name: "color", enumeration: openColors)])
        XCTAssertEqual(try StructTableCSV.decode("color\n9\n", definition: def).entries[0].data.rawBytes, [9])
        XCTAssertEqual(try StructTableCSV.decode("color\n0x0A\n", definition: def).entries[0].data.rawBytes, [10])
        // Still accepted for files written before the integer fallback, even
        // though it is never emitted.
        XCTAssertEqual(try StructTableCSV.decode("color\nOpen_Colors_9\n", definition: def).entries[0].data.rawBytes, [9])
    }

    func testDecodeRejectsAnUnresolvableEnumCell() {
        let def = definition("Painted", [.abstraction(name: "color", enumeration: colors)])
        XCTAssertThrowsError(try StructTableCSV.decode("color\nMauve\n", definition: def)) { error in
            guard case StructCSVError.invalidValue(let column, let row, let value, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(column, "color")
            XCTAssertEqual(row, 1)
            XCTAssertEqual(value, "Mauve")
        }
    }

    func testDecodesIntegersInDecimalHexAndBooleanForms() throws {
        let def = definition("Nums", [.uint8(name: "a"), .uint8(name: "b"), .uint8(name: "c")])
        let result = try StructTableCSV.decode("a,b,c\n16,0x10,true\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [16, 16, 1])
    }

    func testDecodesFloatBitPatterns() throws {
        let def = definition("Floats", [.float(name: "f")])
        XCTAssertEqual(
            try StructTableCSV.decode("f\n0x7FA00000\n", definition: def).entries[0].data.rawBytes,
            [0x7F, 0xA0, 0x00, 0x00]
        )
        XCTAssertEqual(
            try StructTableCSV.decode("f\n1.5\n", definition: def).entries[0].data.rawBytes,
            [0x3F, 0xC0, 0x00, 0x00]
        )
    }

    func testBuildsEachEntryFromScratchSoBlankCellsAreZero() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        let result = try StructTableCSV.decode("a,b\n7,\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 0])
    }

    func testColumnsAreMatchedByHeaderNotPosition() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        let result = try StructTableCSV.decode("b,a\n9,7\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 9])
    }

    func testMissingColumnsAreZeroedAndWarned() throws {
        let def = definition("Trio", [.uint8(name: "a"), .uint8(name: "b"), .uint8(name: "c")])
        let result = try StructTableCSV.decode("a\n7\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 0, 0])
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("b, c"))
    }

    func testUnknownColumnsAreIgnoredAndWarned() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        let result = try StructTableCSV.decode("a,nonsense,b\n7,999,9\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 9])
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("nonsense") }))
    }

    func testDuplicateColumnsKeepTheFirstAndWarn() throws {
        let def = definition("One", [.uint8(name: "a")])
        let result = try StructTableCSV.decode("a,a\n7,9\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7])
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("more than once") }))
    }

    func testShortAndLongRowsAreToleratedAndWarned() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        let result = try StructTableCSV.decode("a,b\n7\n1,2,3\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 0])
        XCTAssertEqual(result.entries[1].data.rawBytes, [1, 2])
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testOneIndexedArrayHeadersLandAtTheRightOffsets() throws {
        let def = definition("Moves", [.array(name: "moves", count: 3, of: .uint8)])
        let result = try StructTableCSV.decode("moves[1],moves[2],moves[3]\n7,8,9\n", definition: def)
        XCTAssertEqual(result.entries[0].data.rawBytes, [7, 8, 9])
    }

    func testHeaderWithoutRowsDecodesToNoEntries() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        XCTAssertTrue(try StructTableCSV.decode("a,b\n", definition: def).entries.isEmpty)
    }

    func testEmptyDocumentThrows() {
        let def = definition("Pair", [.uint8(name: "a")])
        XCTAssertThrowsError(try StructTableCSV.decode("", definition: def)) { error in
            guard case StructCSVError.missingHeaderRow = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Round trip

    /// Every `StructProperty` case in one definition. Padding is zero here
    /// deliberately — see `testNonZeroPaddingIsNotPreserved`.
    private func kitchenSink() -> StructDefinition {
        let stats = definition("Stats", [.uint8(name: "attack"), .uint8(name: "defense")])
        let slot = definition("Slot", [.uint8(name: "id"), .uint8(name: "pp")])
        return definition("Kitchen", [
            .uint8(name: "u8"),
            .int16(name: "i16"),
            .uint32(name: "u32"),
            .float(name: "f32"),
            .float(name: "notANumber"),
            .double(name: "f64"),
            .losslessFloat(name: "denormal"),
            .boolean(name: "flag"),
            .abstraction(name: "named", enumeration: colors),
            .abstraction(name: "unnamed", enumeration: openColors),
            .string(name: "name", format: .utf8, length: 6),
            .character(name: "initial", format: .utf8),
            .label(name: "ptr"),
            .array(name: "ptrs", count: 2, of: .label),
            .array(name: "shorts", count: 3, of: .uint16),
            .padding(length: 2),
            .subStruct(name: "base", defintion: stats),
            .array(name: "slots", count: 2, of: .subStruct(slot)),
            .array(name: "grid", count: 2, of: .array(.uint8, count: 2)),
        ])
    }

    private func kitchenSinkBytes() -> [UInt8] {
        var bytes = [UInt8]()
        bytes += [0x12]                                     // u8
        bytes += [0xFF, 0xFE]                               // i16 = -2
        bytes += [0xDE, 0xAD, 0xBE, 0xEF]                   // u32
        bytes += [0x3F, 0xC0, 0x00, 0x00]                   // f32 = 1.5
        bytes += [0x7F, 0xA0, 0x00, 0x00]                   // signalling NaN with payload
        bytes += [0xBF, 0xD0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]   // f64 = -0.25
        bytes += [0x00, 0x00, 0x00, 0x01]                   // smallest denormal float
        bytes += [0x01]                                     // flag
        bytes += [0x02]                                     // named -> Blue
        bytes += [0x09]                                     // unnamed -> 9
        bytes += Array("Abc".utf8) + [0, 0, 0]              // name
        bytes += Array("Z".utf8)                            // initial
        bytes += [0x80, 0x00, 0x40, 0x00]                   // ptr
        bytes += [0x80, 0x00, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00]   // ptrs
        bytes += [0x00, 0x01, 0x00, 0x02, 0x00, 0x03]       // shorts
        bytes += [0x00, 0x00]                               // padding
        bytes += [0x07, 0x08]                               // base
        bytes += [0x01, 0x02, 0x03, 0x04]                   // slots
        bytes += [0x0A, 0x0B, 0x0C, 0x0D]                   // grid
        return bytes
    }

    func testKitchenSinkFixtureMatchesTheDefinitionLength() {
        XCTAssertEqual(kitchenSinkBytes().count, kitchenSink().length)
    }

    func testRoundTripIsByteIdenticalAcrossEveryPropertyType() throws {
        let def = kitchenSink()
        let original = kitchenSinkBytes()
        let source = entry(def, original)

        let text = try StructTableCSV.encode(entries: [source], definition: def)
        let result = try StructTableCSV.decode(text, definition: def, byteOrder: .big)

        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
        let rebuilt = try XCTUnwrap(result.entries.first)

        // Label fields are the one documented asymmetry: their four bytes stay
        // zero until the assembler resolves the name through a LabelTable, so
        // the names round-trip in `labelValues` instead of in the buffer.
        var expected = original
        for column in StructCSVSchema.columns(of: def) where column.labelKey != nil {
            for i in 0 ..< 4 { expected[column.offset + i] = 0 }
        }
        XCTAssertEqual(rebuilt.data.rawBytes, expected)
        XCTAssertEqual(rebuilt.labelValues, [
            "ptr": "lbl_80004000",
            "ptrs[0]": "lbl_80005000",
        ])
    }

    /// Golden: the whole format in one frozen sample. Generated once and
    /// pinned, so any change to headers, ordering or value rendering has to
    /// be a deliberate edit here rather than a silent drift.
    func testKitchenSinkGoldenText() throws {
        let def = kitchenSink()
        let text = try StructTableCSV.encode(entries: [entry(def, kitchenSinkBytes())], definition: def)
        XCTAssertEqual(lines(text), [
            "u8,i16,u32,f32,notANumber,f64,denormal,flag,named,unnamed,name,initial,ptr,"
            + "ptrs[1],ptrs[2],shorts[1],shorts[2],shorts[3],base.attack,base.defense,"
            + "slots[1].id,slots[1].pp,slots[2].id,slots[2].pp,"
            + "grid[1][1],grid[1][2],grid[2][1],grid[2][2]",

            "18,-2,3735928559,1.5,0x7FA00000,-0.25,1e-45,true,Blue,9,Abc,Z,lbl_80004000,"
            + "lbl_80005000,,1,2,3,7,8,1,2,3,4,10,11,12,13",

            "",
        ])
    }

    func testRoundTripTextIsStable() throws {
        let def = kitchenSink()
        let first = try StructTableCSV.encode(entries: [entry(def, kitchenSinkBytes())], definition: def)
        let decoded = try StructTableCSV.decode(first, definition: def)
        let second = try StructTableCSV.encode(entries: decoded.entries, definition: def)
        XCTAssertEqual(first, second)
    }

    func testRoundTripHeaderIsTheFlattenedSchema() throws {
        let def = kitchenSink()
        let text = try StructTableCSV.encode(entries: [entry(def, kitchenSinkBytes())], definition: def)
        XCTAssertEqual(lines(text)[0], StructCSVSchema.columns(of: def).map(\.header).joined(separator: ","))
        // Spot-check the shapes the header is supposed to have.
        XCTAssertTrue(lines(text)[0].contains("base.attack"))
        XCTAssertTrue(lines(text)[0].contains("slots[2].pp"))
        XCTAssertTrue(lines(text)[0].contains("grid[2][2]"))
        XCTAssertFalse(lines(text)[0].contains("padding"))
    }

    func testNonZeroPaddingIsNotPreserved() throws {
        // Padding has no column, so it rebuilds as zeroes unless the caller
        // says what fills it — a file the decoder is handed on its own can't
        // know, and the CSV was never asked to carry it.
        let def = definition("Padded", [.uint8(name: "a"), .padding(length: 2)])
        let text = try StructTableCSV.encode(entries: [entry(def, [7, 0x11, 0x11])], definition: def)
        let rebuilt = try StructTableCSV.decode(text, definition: def).entries[0]
        XCTAssertEqual(rebuilt.data.rawBytes, [7, 0, 0])
    }

    func testDeclaredPaddingFillsAreWrittenBack() throws {
        // A packer that fills gaps with something other than zero (Battle
        // Revolution's table compiler writes 0xD0) names the runs, and the
        // bytes come back — without giving padding a column, because the fill
        // is one value for the whole table rather than per-row data.
        let def = definition("Padded", [.uint8(name: "a"), .padding(length: 2), .uint8(name: "b")])
        let rows = [entry(def, [7, 0xD0, 0xD0, 9]), entry(def, [8, 0xD0, 0xD0, 10])]
        let fills = try XCTUnwrap(StructPaddingFill.measure(in: rows, definition: def))
        XCTAssertEqual(fills, [StructPaddingFill(offset: 1, length: 2, byte: 0xD0)])

        let text = try StructTableCSV.encode(entries: rows, definition: def)
        XCTAssertFalse(lines(text)[0].contains("padding"), "the fill is not a column")
        let rebuilt = try StructTableCSV.decode(text, definition: def, paddingFills: fills).entries
        XCTAssertEqual(rebuilt.map(\.data.rawBytes), rows.map(\.data.rawBytes))
    }

    func testMeasuringRefusesAPaddingRunThatVariesBetweenRows() throws {
        // Two rows disagreeing about a "padding" byte means it carries
        // information, so it is a field the definition hasn't named. Saying
        // nil here is what lets a caller refuse to write a lossy CSV.
        let def = definition("Padded", [.uint8(name: "a"), .padding(length: 1)])
        let rows = [entry(def, [7, 0xD0]), entry(def, [8, 0x11])]
        XCTAssertNil(StructPaddingFill.measure(in: rows, definition: def))
    }

    func testAPaddingFillThatDoesNotFitTheRecordIsIgnored() throws {
        // A manifest naming a run the record doesn't have is describing some
        // other record. Writing it would grow the row and shift every entry
        // after it, so it is dropped instead.
        let def = definition("Padded", [.uint8(name: "a"), .padding(length: 1)])
        let text = try StructTableCSV.encode(entries: [entry(def, [7, 0])], definition: def)
        let rebuilt = try StructTableCSV.decode(
            text, definition: def,
            paddingFills: [StructPaddingFill(offset: 4, length: 2, byte: 0xD0)]
        ).entries[0]
        XCTAssertEqual(rebuilt.data.rawBytes, [7, 0])
    }

    func testPaddingRangesFlattenThroughSubStructsAndArrays() throws {
        let cell = definition("Cell", [.uint8(name: "v"), .padding(length: 1)])
        let def = definition("Grid", [
            .padding(length: 2),
            .subStruct(name: "head", defintion: cell),
            .array(name: "rest", count: 2, of: .subStruct(cell)),
        ])
        XCTAssertEqual(def.paddingRanges, [0..<2, 3..<4, 5..<6, 7..<8])
    }

    func testRoundTripSurvivesStringsThatNeedQuoting() throws {
        let def = definition("Named", [.string(name: "name", format: .utf8, length: 12)])
        let raw = "a,\"b\" c"
        let bytes = Array(raw.utf8) + [UInt8](repeating: 0, count: 12 - raw.utf8.count)
        let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
        let rebuilt = try StructTableCSV.decode(text, definition: def).entries[0]
        XCTAssertEqual(rebuilt.data.rawBytes, bytes)
    }

    func testRoundTripWithCStyleAlignment() throws {
        let def = definition("Aligned", [
            .uint8(name: "a"),
            .uint32(name: "b"),
            .uint8(name: "c"),
        ], alignment: .cStyle)
        // Alignment gaps carry no column, so they have to be zero to survive.
        let bytes: [UInt8] = [0x07, 0, 0, 0, 0xDE, 0xAD, 0xBE, 0xEF, 0x09, 0, 0, 0]
        XCTAssertEqual(bytes.count, def.length)
        let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
        let rebuilt = try StructTableCSV.decode(text, definition: def).entries[0]
        XCTAssertEqual(rebuilt.data.rawBytes, bytes)
    }

    func testEncodesAStructTable() throws {
        let def = definition("Pair", [.uint8(name: "a"), .uint8(name: "b")])
        let table = StructTableData(
            definition: def,
            data: GoDData(byteStream: [1, 2, 3, 4], byteOrder: .big)
        )
        XCTAssertEqual(lines(try StructTableCSV.encode(table: table)), ["a,b", "1,2", "3,4", ""])
    }

    // MARK: - Bit fields

    /// XD's map-REL character flags byte, in MSB-0 terms: bit 0 is `0x80`.
    private var characterFlags: StructDefinition.Property {
        .bits(name: "flags", fields: [
            .flag(name: "visible", bit: 0),
            .flag(name: "placed_on_load", bit: 1),
            .flag(name: "has_collision", bit: 2),
            .abstraction(name: "color", bits: 3...4, enumeration: colors),
            .number(name: "unknown_5_7", bits: 5...7),
        ])
    }

    func testEncodesOneCellPerBitField() throws {
        let def = definition("Character", [characterFlags])
        // 0xC5 = 1100 0101: visible and placed set, no collision,
        // color bits 3:4 = 00 (Red), unknown bits 5:7 = 101 (5).
        let text = try StructTableCSV.encode(entries: [entry(def, [0xC5])], definition: def)
        XCTAssertEqual(lines(text), [
            "flags.visible,flags.placed_on_load,flags.has_collision,flags.color,flags.unknown_5_7",
            "true,true,false,Red,5",
            "",
        ])
    }

    func testEncodesAnUnnamedEnumValueAsTheInteger() throws {
        let def = definition("Character", [
            .bits(name: "flags", fields: [
                .abstraction(name: "color", bits: 0...1, enumeration: openColors),
                .number(name: "rest", bits: 2...7),
            ]),
        ])
        // Raw 3 has no case; the cell is the number, never a synthesized
        // `Open_Colors_3` that couldn't be told from a real name.
        let text = try StructTableCSV.encode(entries: [entry(def, [0xC0])], definition: def)
        XCTAssertEqual(lines(text)[1], "3,0")
    }

    func testDecodesEachBitFieldIntoItsOwnBits() throws {
        let def = definition("Character", [characterFlags])
        let header = "flags.visible,flags.placed_on_load,flags.has_collision,flags.color,flags.unknown_5_7"
        let result = try StructTableCSV.decode(
            header + "\ntrue,false,true,Blue,1",
            definition: def
        )
        XCTAssertEqual(result.warnings, [])
        // visible 0x80 + collision 0x20 + color 2 at bits 3:4 (0x10) + 1
        XCTAssertEqual(result.entries.first?.data.rawBytes, [0xB1])
    }

    func testBitColumnsMayBeReorderedInTheFile() throws {
        let def = definition("Character", [characterFlags])
        let ordered = try StructTableCSV.decode(
            "flags.visible,flags.color\ntrue,Blue",
            definition: def
        )
        let reversed = try StructTableCSV.decode(
            "flags.color,flags.visible\nBlue,true",
            definition: def
        )
        // Disjoint ranges, read-modify-write: order can't matter.
        XCTAssertEqual(
            reversed.entries.first?.data.rawBytes,
            ordered.entries.first?.data.rawBytes
        )
        // visible 0x80 + color Blue (2) at bits 3:4 = 0x10
        XCTAssertEqual(ordered.entries.first?.data.rawBytes, [0x90])
    }

    func testABlankBitCellLeavesItsBitsZero() throws {
        let def = definition("Character", [characterFlags])
        let result = try StructTableCSV.decode(
            "flags.visible,flags.unknown_5_7\n,7",
            definition: def
        )
        XCTAssertEqual(result.entries.first?.data.rawBytes, [0x07])
    }

    func testARejectedBitCellNamesItsColumn() throws {
        let def = definition("Character", [characterFlags])
        XCTAssertThrowsError(
            try StructTableCSV.decode("flags.visible\nmaybe", definition: def)
        ) { error in
            XCTAssertTrue("\(error)".contains("flags.visible"), "\(error)")
        }
        XCTAssertThrowsError(
            try StructTableCSV.decode("flags.color\nMauve", definition: def)
        ) { error in
            XCTAssertTrue("\(error)".contains("Colors"), "\(error)")
        }
    }

    func testBitFieldsRoundTripByteIdentically() throws {
        let def = definition("Character", [
            .uint8(name: "model"),
            characterFlags,
            .bits(name: "behavior", storage: .uint16, fields: [
                .number(name: "move_type", bits: 0...2),
                .number(name: "talk_start", bits: 3...4),
                .number(name: "talk_end", bits: 5...6),
                .number(name: "signed_trim", bits: 7...10, signed: true),
                .number(name: "unknown_11_15", bits: 11...15),
            ]),
        ])
        for raw in [[0x12, 0x00, 0x00, 0x00], [0x34, 0xFF, 0xFF, 0xFF], [0x56, 0xA5, 0x5A, 0xC3]] {
            let bytes = raw.map(UInt8.init)
            let text = try StructTableCSV.encode(entries: [entry(def, bytes)], definition: def)
            let rebuilt = try StructTableCSV.decode(text, definition: def)
            XCTAssertEqual(rebuilt.warnings, [])
            XCTAssertEqual(rebuilt.entries.first?.data.rawBytes, bytes, "round trip of \(bytes)")
        }
    }

    func testALittleEndianContainerNumbersBitsInItsValue() throws {
        let def = definition("Wide", [
            .bits(name: "word", storage: .uint16, fields: [
                .flag(name: "top", bit: 0),
                .number(name: "rest", bits: 1...15),
            ]),
        ])
        // Bit 0 is the top bit of the *value*, so on disc it lands in the
        // second byte when the data is little-endian.
        let little = StructData(
            definition: def,
            data: GoDData(byteStream: [0x00, 0x00], byteOrder: .little)
        )
        little.setBits("word.top", to: 1)
        XCTAssertEqual(little.data.rawBytes, [0x00, 0x80])

        let big = StructData(
            definition: def,
            data: GoDData(byteStream: [0x00, 0x00], byteOrder: .big)
        )
        big.setBits("word.top", to: 1)
        XCTAssertEqual(big.data.rawBytes, [0x80, 0x00])
    }
}
