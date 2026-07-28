import XCTest
import Foundation
import GoDFoundation
import Structs
import Disassembler

/// Tests for the typed data reassembly pipeline used by DOL assembly:
/// binary → `TypedDataExporter` → JSON (`StructData` encode) →
/// `StructData(definition:json:)` → `TypedDataImporter.importStruct` →
/// binary. Ground truth is hand-computed bytes; labels resolve through
/// a `LabelTable` the way the assembler drives it.
final class TypedDataImporterTests: XCTestCase {

    private let exporter = TypedDataExporter()
    private let importer = TypedDataImporter()

    /// JSON encoder matching the DOL dump's configuration — sentinel
    /// strings for non-finite floats.
    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return e
    }()

    /// 8-byte struct: `id` (u32) then `ptr` (label = 4-byte pointer).
    private var pointerStruct: StructDefinition {
        StructDefinition(
            name: "PointerStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .uint32(name: "id"),
                .label(name: "ptr"),
            ]
        )
    }

    private func entryBytes(id: UInt32, ptr: UInt32) -> [UInt8] {
        [UInt8(id >> 24), UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF),
         UInt8(ptr >> 24), UInt8((ptr >> 16) & 0xFF), UInt8((ptr >> 8) & 0xFF), UInt8(ptr & 0xFF)]
    }

    /// Export binary to a StructData, serialize to JSON, decode back
    /// via the schema-aware initializer, and import to binary again.
    private func roundTrip(
        bytes: [UInt8],
        definition: StructDefinition,
        addressToLabel: [UInt32: String] = [:],
        labelTable: LabelTable = LabelTable(),
        editJSON: ((inout [String: Any]) -> Void)? = nil
    ) throws -> GoDData {
        let exported = exporter.exportStruct(
            data: GoDData(byteStream: bytes, byteOrder: .big),
            definition: definition,
            addressToLabel: addressToLabel
        )
        var jsonBytes: Data = try jsonEncoder.encode(exported)

        if let editJSON {
            var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any])
            var fields = try XCTUnwrap(obj["data"] as? [String: Any])
            editJSON(&fields)
            obj["data"] = fields
            jsonBytes = try JSONSerialization.data(withJSONObject: obj)
        }

        let decoded = try StructData(
            definition: definition,
            json: GoDData(byteStream: [UInt8](jsonBytes), byteOrder: .big),
            byteOrder: .big
        )
        return importer.importStruct(
            structData: decoded,
            labelTable: labelTable,
            byteOrder: .big
        )
    }

    // MARK: - Basic round trip

    func testRoundTrip_unedited_reproducesOriginalBytes() throws {
        let labelTable = LabelTable()
        labelTable.addLabel("my_func", address: 0x8000_3000)

        let original = entryBytes(id: 0x2A, ptr: 0x8000_3000)
        let imported = try roundTrip(
            bytes: original,
            definition: pointerStruct,
            addressToLabel: [0x8000_3000: "my_func"],
            labelTable: labelTable
        )
        XCTAssertEqual(imported.rawBytes, original)
    }

    func testRoundTrip_autoLabel_resolvesIntrinsically() throws {
        // Unknown pointer targets export as lbl_XXXXXXXX; an empty
        // LabelTable still resolves those from the hex in the name.
        let original = entryBytes(id: 7, ptr: 0x8000_4000)
        let imported = try roundTrip(bytes: original, definition: pointerStruct)
        XCTAssertEqual(imported.rawBytes, original)
    }

    func testRoundTrip_editedField_landsInOutput() throws {
        let original = entryBytes(id: 1, ptr: 0x8000_3000)
        let imported = try roundTrip(
            bytes: original,
            definition: pointerStruct,
            editJSON: { fields in
                fields["id"] = 0x0102_0304
            }
        )
        XCTAssertEqual(imported.rawBytes, entryBytes(id: 0x0102_0304, ptr: 0x8000_3000))
    }

    func testRoundTrip_editedLabel_resolvesNewAddress() throws {
        let labelTable = LabelTable()
        labelTable.addLabel("other_func", address: 0x8000_5000)

        let original = entryBytes(id: 1, ptr: 0x8000_3000)
        let imported = try roundTrip(
            bytes: original,
            definition: pointerStruct,
            labelTable: labelTable,
            editJSON: { fields in
                fields["ptr"] = "other_func"
            }
        )
        XCTAssertEqual(imported.rawBytes, entryBytes(id: 1, ptr: 0x8000_5000))
    }

    // MARK: - Padding

    func testRoundTrip_paddingBytes_arePreserved() throws {
        // `.padding(length:)` expands to a uint8 array named "padding",
        // which round-trips its actual byte values through padding_0.
        let definition = StructDefinition(
            name: "Padded",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .uint16(name: "a"),
                .padding(length: 2),
                .uint32(name: "b"),
            ]
        )
        let original: [UInt8] = [0x00, 0x2A, 0xDE, 0xAD, 0x01, 0x02, 0x03, 0x04]
        let imported = try roundTrip(bytes: original, definition: definition)
        XCTAssertEqual(imported.rawBytes, original)
    }

    // MARK: - Label arrays

    func testRoundTrip_labelArray_resolvesEachElement() throws {
        let definition = StructDefinition(
            name: "PointerArrayStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .uint32(name: "id"),
                .array(name: "ptrs", count: 2, of: .label),
            ]
        )
        let labelTable = LabelTable()
        labelTable.addLabel("func_a", address: 0x8000_1000)

        let original: [UInt8] =
            [0x00, 0x00, 0x00, 0x05,
             0x80, 0x00, 0x10, 0x00,
             0x80, 0x00, 0x20, 0x00]
        let imported = try roundTrip(
            bytes: original,
            definition: definition,
            addressToLabel: [0x8000_1000: "func_a"],
            labelTable: labelTable
        )
        XCTAssertEqual(imported.rawBytes, original)
    }

    // MARK: - Enums

    func testRoundTrip_enum_namedAndUnnamedValues() throws {
        let element = Enum(
            name: "Element",
            allowUnknownCases: false,
            values: [.init(name: "fire", rawValue: 1), .init(name: "water", rawValue: 2)],
            propertyType: .uint8
        )
        let definition = StructDefinition(
            name: "EnumStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .abstraction(name: "known", enumeration: element),
                .abstraction(name: "unknown", enumeration: element),
                .uint16(name: "tail"),
            ]
        )
        // 1 = "fire" (named), 9 has no case — encodes as raw integer.
        let original: [UInt8] = [0x01, 0x09, 0x12, 0x34]
        let imported = try roundTrip(bytes: original, definition: definition)
        XCTAssertEqual(imported.rawBytes, original)
    }

    func testRoundTrip_enum_allowUnknownCases_synthesizedName() throws {
        let element = Enum(
            name: "Open Enum",
            allowUnknownCases: true,
            values: [.init(name: "zero", rawValue: 0)],
            propertyType: .uint8
        )
        let definition = StructDefinition(
            name: "OpenEnumStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .abstraction(name: "value", enumeration: element),
                .uint8(name: "tail"),
            ]
        )
        // 5 has no named case; allowUnknownCases synthesizes
        // "Open_Enum_5" on encode — decode parses the raw value back.
        let original: [UInt8] = [0x05, 0xAA]
        let imported = try roundTrip(bytes: original, definition: definition)
        XCTAssertEqual(imported.rawBytes, original)
    }

    // MARK: - Non-finite floats

    func testRoundTrip_nanFloat_decodesAsNaN() throws {
        let definition = StructDefinition(
            name: "FloatStruct",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .float(name: "f"),
            ]
        )
        // A NaN payload: encodes as the string sentinel "NaN"; decode
        // restores a (canonical) NaN — payload bits are not preserved
        // for plain .float fields, only NaN-ness.
        let original: [UInt8] = [0x7F, 0xC0, 0x00, 0x01]
        let imported = try roundTrip(bytes: original, definition: definition)
        let bits = UInt32(imported.rawBytes[0]) << 24
            | UInt32(imported.rawBytes[1]) << 16
            | UInt32(imported.rawBytes[2]) << 8
            | UInt32(imported.rawBytes[3])
        XCTAssertTrue(Float(bitPattern: bits).isNaN)
    }

    // MARK: - Table entry wrap (the DolAssembly path)

    func testTableEntry_flatDictWrap_decodesAndImports() throws {
        // DolAssembly wraps each flat table entry into {type, data}
        // before handing it to StructData's decoder — mirror that.
        let labelTable = LabelTable()
        labelTable.addLabel("func_a", address: 0x8000_3000)

        let fields: [String: Any] = ["id": 3, "ptr": "func_a"]
        let wrapped: [String: Any] = ["type": "PointerStruct", "data": fields]
        let wrappedBytes = try JSONSerialization.data(withJSONObject: wrapped)

        let decoded = try StructData(
            definition: pointerStruct,
            json: GoDData(byteStream: [UInt8](wrappedBytes), byteOrder: .big),
            byteOrder: .big
        )
        let imported = importer.importStruct(
            structData: decoded,
            labelTable: labelTable,
            byteOrder: .big
        )
        XCTAssertEqual(imported.rawBytes, entryBytes(id: 3, ptr: 0x8000_3000))
    }
}
