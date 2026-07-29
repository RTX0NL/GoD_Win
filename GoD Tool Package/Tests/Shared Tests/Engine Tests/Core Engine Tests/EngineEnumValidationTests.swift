//
//  EngineEnumValidationTests.swift
//  GoDEngineTests
//
//  Enum case names are the serialized form of an enum-typed field, so an
//  unusable name has to be rejected where the engine loads rather than
//  where the field is written. Two enforcement points: decoding an engine
//  folder, and resolving a struct's `.enumeration` reference.
//

import XCTest
import GoDFoundation
import Structs
@testable import GoDEngine

final class EngineEnumValidationTests: XCTestCase {

    private let root = Folder("/engines")

    /// Writes an engine folder by hand rather than via `Engine.write`, so the
    /// enum JSON can hold a name the in-memory type would never produce.
    private func installEngine(
        named name: String,
        enums: [String: [String]],
        structs: [String: GoDData] = [:],
        in fst: FileSystemTree
    ) throws -> Folder {
        let folder = root.folder(name)
        try fst.createFolder(at: folder, overwrite: true)
        try fst.writeFile(GoDData(data: Data("{}".utf8), byteOrder: .big),
                          at: folder.file("\(name).json"), overwrite: true)

        let enumsFolder = folder.folder("Enumerations")
        try fst.createFolder(at: enumsFolder, overwrite: true)
        for (enumName, cases) in enums {
            let json = """
            {"name":"\(enumName)","allowUnknownCases":false,\
            "values":[\(cases.map { "\"\($0)\"" }.joined(separator: ","))],\
            "propertyType":"uint8"}
            """
            try fst.writeFile(GoDData(data: Data(json.utf8), byteOrder: .big),
                              at: enumsFolder.file("\(enumName).json"), overwrite: true)
        }

        let structsFolder = folder.folder("Structs")
        try fst.createFolder(at: structsFolder, overwrite: true)
        for (structName, data) in structs {
            try fst.writeFile(data, at: structsFolder.file("\(structName).json"), overwrite: true)
        }
        return folder
    }

    /// Properties serialize as `"<type> <name>"` tokens (see `StructMap`).
    private func structJSON(name: String, enumName: String) -> GoDData {
        let json = """
        {"name":"\(name)","wordSize":4,"alignmentStyle":"none","description":null,\
        "properties":["enum \(enumName) kind"]}
        """
        return GoDData(data: Data(json.utf8), byteOrder: .big)
    }

    // MARK: - Engine folder load

    func testEngineLoadsWhenCaseNamesAreValid() throws {
        let fst = InMemoryFST()
        // Punctuation is fine — FsysGroupIDs really does name its cases after
        // archive filenames.
        let folder = try installEngine(
            named: "Test",
            enums: ["Archives": ["B1_1.fsys = 0", "bgm_archive.fsys = 1", "_reserved = 2"]],
            in: fst
        )
        let engine = try GenericEngine(from: folder, in: fst)
        XCTAssertEqual(engine.getEnum("Archives")?.values.count, 3)
    }

    func testEngineLoadRejectsCaseNameStartingWithADigit() throws {
        let fst = InMemoryFST()
        let folder = try installEngine(
            named: "Test",
            enums: ["Broken": ["Fine = 0", "2ndStage = 1"]],
            in: fst
        )
        XCTAssertThrowsError(try GenericEngine(from: folder, in: fst)) { error in
            guard case EngineDecodingError.invalidEnumCaseNames(let enumName, let names, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(enumName, "Broken")
            XCTAssertEqual(names, ["2ndStage"])
        }
    }

    func testEngineLoadRejectsCaseNameThatIsJustANumber() throws {
        let fst = InMemoryFST()
        // The exact ambiguity the rule exists for: an unnamed raw value
        // serializes as its integer, so a case *named* "22" is undecidable.
        let folder = try installEngine(
            named: "Test",
            enums: ["Broken": ["22 = 0"]],
            in: fst
        )
        XCTAssertThrowsError(try GenericEngine(from: folder, in: fst)) { error in
            guard case EngineDecodingError.invalidEnumCaseNames(_, let names, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(names, ["22"])
        }
    }

    func testEngineLoadRejectsUnreferencedEnum() throws {
        let fst = InMemoryFST()
        // No struct mentions this enum — it still must not load.
        let folder = try installEngine(
            named: "Test",
            enums: ["Orphan": ["1up = 0"]],
            in: fst
        )
        XCTAssertThrowsError(try GenericEngine(from: folder, in: fst))
    }

    // MARK: - Struct resolution

    func testStructResolutionRejectsInvalidCaseNames() throws {
        let fst = InMemoryFST()
        let folder = try installEngine(
            named: "Test",
            enums: ["Kinds": ["Good = 0"]],
            structs: ["Thing": structJSON(name: "Thing", enumName: "Kinds")],
            in: fst
        )
        let engine = try GenericEngine(from: folder, in: fst)
        XCTAssertNoThrow(try engine.getStruct("Thing") as StructDefinition)

        // Same engine, but the enum is swapped for one the folder loader never
        // saw — the resolution-time check is what catches it.
        let broken = GenericEngine.Enums(unchecked: [
            Enum(name: "Kinds", allowUnknownCases: false,
                 values: [.init(name: "Bad Name", rawValue: 0)], propertyType: .uint8)
        ])
        let brokenEngine = try GenericEngine(
            data: engine.data, enums: broken, structs: engine.structs
        )
        XCTAssertThrowsError(try brokenEngine.getStruct("Thing") as StructDefinition) { error in
            guard case EngineDecodingError.invalidEnumCaseNames(let enumName, let names, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(enumName, "Kinds")
            XCTAssertEqual(names, ["Bad Name"])
        }
    }

    // MARK: - Error description

    func testErrorDescriptionNamesTheEnumAndTheRule() {
        let description = EngineDecodingError
            .invalidEnumCaseNames(enumName: "Broken", names: ["2nd", "Bad Name"], .init())
            .description
        XCTAssertTrue(description.contains("Broken"))
        XCTAssertTrue(description.contains("2nd, Bad Name"))
        XCTAssertTrue(description.contains("start with a letter or '_'"))
    }
}
