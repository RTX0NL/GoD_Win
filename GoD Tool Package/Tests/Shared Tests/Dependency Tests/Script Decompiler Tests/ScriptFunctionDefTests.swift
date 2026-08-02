//
//  ScriptFunctionDefTests.swift
//
//  Codable coverage for ScriptParamType (primitive + enum-ref custom
//  encoding, incl. the "enum:" prefix and bare-name back-compat) and
//  ScriptFunctionDef / ParameterDef round trips.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class ScriptFunctionDefTests: XCTestCase {

    // MARK: - ScriptParamType encoding

    func testPrimitiveTypesEncodeAsPlainStrings() throws {
        XCTAssertEqual(ScriptParamType.integer.encodeJSONString(), "\"integer\"")
        XCTAssertEqual(ScriptParamType.float.encodeJSONString(), "\"float\"")
        XCTAssertEqual(ScriptParamType.bool.encodeJSONString(), "\"bool\"")
    }

    func testEnumRefEncodesAsBareName() throws {
        XCTAssertEqual(ScriptParamType.enumRef("FlagName").encodeJSONString(), "\"FlagName\"")
    }

    // MARK: - ScriptParamType decoding

    func testPrimitiveTypesDecode() throws {
        XCTAssertEqual(try decodeParam("\"integer\""), .integer)
        XCTAssertEqual(try decodeParam("\"float\""), .float)
        XCTAssertEqual(try decodeParam("\"bool\""), .bool)
    }

    func testEnumRefDecodesFromPrefixedForm() throws {
        XCTAssertEqual(try decodeParam("\"enum:MyEnum\""), .enumRef("MyEnum"))
    }

    func testEnumRefDecodesFromBareName() throws {
        // Backwards-compat: any unrecognized string is treated as an enum ref.
        XCTAssertEqual(try decodeParam("\"SomeFlag\""), .enumRef("SomeFlag"))
    }

    func testParamTypeRoundTrip() throws {
        for value: ScriptParamType in [.integer, .float, .bool, .enumRef("Weather")] {
            let json = try XCTUnwrap(value.encodeJSON())
            XCTAssertEqual(try JSONDecoder().decode(ScriptParamType.self, from: json), value)
        }
    }

    private func decodeParam(_ json: String) throws -> ScriptParamType {
        try JSONDecoder().decode(ScriptParamType.self, from: json.data(format: .utf8))
    }

    // MARK: - ScriptFunctionDef

    func testFunctionDefDefaults() {
        let def = ScriptFunctionDef(name: "noop")
        XCTAssertEqual(def.name, "noop")
        XCTAssertTrue(def.parameters.isEmpty)
        XCTAssertNil(def.returnType)
        XCTAssertNil(def.hint)
    }

    func testFunctionDefRoundTrip() throws {
        let def = ScriptFunctionDef(
            name: "setFlag",
            parameters: [
                .init(name: "flag", type: .enumRef("StoryFlag")),
                .init(name: "value", type: .bool),
            ],
            returnType: .integer,
            hint: "sets a story flag"
        )
        let json = try XCTUnwrap(def.encodeJSON())
        let decoded = try JSONDecoder().decode(ScriptFunctionDef.self, from: json)
        XCTAssertEqual(decoded, def)
        XCTAssertEqual(decoded.parameters[0].name, "flag")
        XCTAssertEqual(decoded.parameters[0].type, .enumRef("StoryFlag"))
        XCTAssertEqual(decoded.returnType, .integer)
        XCTAssertEqual(decoded.hint, "sets a story flag")
    }

    func testParameterDefEquality() {
        XCTAssertEqual(ScriptFunctionDef.ParameterDef(name: "a", type: .integer),
                       ScriptFunctionDef.ParameterDef(name: "a", type: .integer))
        XCTAssertNotEqual(ScriptFunctionDef.ParameterDef(name: "a", type: .integer),
                          ScriptFunctionDef.ParameterDef(name: "a", type: .float))
    }
}
