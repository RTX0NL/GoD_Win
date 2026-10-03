//
//  EngineBitFieldValidationTests.swift
//  GoDEngineTests
//
//  A bit layout that doesn't tile its storage, overlaps, or holds an enum
//  case too wide for its run would read and write silently wrong bits, so
//  it is refused where the engine loads — not where a dump serializes it.
//

import XCTest
import GoDFoundation
import Structs
@testable import GoDEngine

final class EngineBitFieldValidationTests: XCTestCase {

    private let root = Folder("/engines")

    private func installEngine(
        structJSON: String,
        enums: [String: [String]] = ["Kinds": ["None = 0", "Field = 1", "Battle = 2"]],
        in fst: FileSystemTree
    ) throws -> Folder {
        let folder = root.folder("Test")
        try fst.createFolder(at: folder, overwrite: true)
        try fst.writeFile(GoDData(data: Data("{}".utf8), byteOrder: .big),
                          at: folder.file("Test.json"), overwrite: true)

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
        try fst.writeFile(GoDData(data: Data(structJSON.utf8), byteOrder: .big),
                          at: structsFolder.file("Packed.json"), overwrite: true)
        return folder
    }

    /// A bit container is declared as an object, not a `"<type> <name>"`
    /// string: its layout is a list.
    private func structJSON(bits: String, storage: String = "uint8") -> String {
        """
        {"name":"Packed","wordSize":1,"alignmentStyle":"none","description":null,
         "properties":[
           {"name":"flags","description":null,"storage":"\(storage)","bits":[\(bits)]}
         ]}
        """
    }

    private func resolve(_ bits: String, storage: String = "uint8") throws -> StructDefinition {
        let fst = InMemoryFST()
        let folder = try installEngine(structJSON: structJSON(bits: bits, storage: storage), in: fst)
        let engine = try GenericEngine(from: folder, in: fst)
        return try engine.getStruct("Packed")
    }

    // MARK: - Resolution

    func testATilingLayoutResolvesWithItsEnumBound() throws {
        let definition = try resolve("""
        {"name":"kind","range":"0:2","enum":"Kinds"},
        {"name":"visible","range":"3","type":"boolean"},
        {"name":"delta","range":"4:5","type":"signed"},
        {"name":"unknown_6_7","range":"6:7"}
        """)
        XCTAssertEqual(definition.length, 1)
        guard case .bits(let layout)? = definition.property(for: "flags") else {
            return XCTFail("expected a bit field, got \(String(describing: definition.property(for: "flags")))")
        }
        XCTAssertEqual(layout.storage, .uint8)
        XCTAssertEqual(layout.fields.map(\.name), ["kind", "visible", "delta", "unknown_6_7"])
        XCTAssertEqual(layout.fields[0].value, .enumeration(
            Enum(name: "Kinds", allowUnknownCases: false, values: [
                .init(name: "None", rawValue: 0),
                .init(name: "Field", rawValue: 1),
                .init(name: "Battle", rawValue: 2),
            ], propertyType: .uint8)
        ))
        XCTAssertEqual(layout.fields[2].value, .signed)
        XCTAssertEqual(definition.bitLocation(for: "flags.kind")?.byteOffset, 0)
    }

    func testAWiderContainerResolves() throws {
        let definition = try resolve(
            #"{"name":"whole","range":"0:15"}"#,
            storage: "uint16"
        )
        XCTAssertEqual(definition.length, 2)
    }

    // MARK: - Refusals

    private func assertRefused(
        _ bits: String,
        storage: String = "uint8",
        mentioning fragment: String,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try resolve(bits, storage: storage), line: line) { error in
            let message = "\(error)"
            XCTAssertTrue(
                message.contains(fragment),
                "expected '\(fragment)' in: \(message)",
                line: line
            )
        }
    }

    func testAGapIsRefused() {
        assertRefused(
            #"{"name":"top","range":"0"},{"name":"rest","range":"2:7"}"#,
            mentioning: "bits 1 are not covered"
        )
    }

    func testAnOverlapIsRefused() {
        assertRefused(
            #"{"name":"a","range":"0:4"},{"name":"b","range":"3:7"}"#,
            mentioning: "overlaps"
        )
    }

    func testAnOutOfOrderDeclarationIsRefused() {
        assertRefused(
            #"{"name":"low","range":"4:7"},{"name":"high","range":"0:3"}"#,
            mentioning: "most significant first"
        )
    }

    func testARangePastTheStorageIsRefused() {
        assertRefused(
            #"{"name":"a","range":"0:7"},{"name":"b","range":"8"}"#,
            mentioning: "outside the storage unit"
        )
    }

    func testAWideBooleanIsRefused() {
        assertRefused(
            #"{"name":"pair","range":"0:1","type":"boolean"},{"name":"rest","range":"2:7"}"#,
            mentioning: "boolean but covers 2 bits"
        )
    }

    func testAnEnumCaseTooWideForItsRunIsRefused() {
        // The run's width decides the field's size, so `Battle` (2) can't
        // live in one bit — it would read back as `None`.
        assertRefused(
            #"{"name":"kind","range":"0","enum":"Kinds"},{"name":"rest","range":"1:7"}"#,
            mentioning: "doesn't fit 1 bit"
        )
    }

    func testAnUnknownEnumIsRefused() {
        assertRefused(
            #"{"name":"kind","range":"0:7","enum":"Nope"}"#,
            mentioning: "Nope"
        )
    }

    func testTheErrorNamesTheStructAndTheProperty() {
        assertRefused(#"{"name":"a","range":"0:3"}"#, mentioning: "'flags' of struct 'Packed'")
    }
}
