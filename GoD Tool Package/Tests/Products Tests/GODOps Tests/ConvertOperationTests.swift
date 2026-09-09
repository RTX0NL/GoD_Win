//
//  ConvertOperationTests.swift
//  GODOpsTests
//
//  Exercises the standalone Convert operations against an InMemoryFST:
//  file-format decode/encode (via GTX) and struct / struct-table decode/
//  encode round trips (via a synthetic GenericEngine struct).
//

import XCTest
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority
import PBR
import FixtureCatalog
import TestSupport
@testable import GODOps

final class ConvertOperationTests: XCTestCase {

    // MARK: - Fixtures

    /// An 8-byte record: two uint32 fields. Tiles cleanly so tables of it
    /// are unambiguous.
    private func recordStructMap() -> StructMap {
        StructMap(
            name: "TestRecord",
            wordSize: 4,
            alignmentStyle: .cStyle,
            properties: [
                .uint32(name: "first"),
                .uint32(name: "second"),
            ]
        )
    }

    /// A GenericEngine carrying just `TestRecord`, serialized onto the tree.
    /// Returns the installed engine folder.
    private func installRecordEngine(in fst: InMemoryFST) throws -> Folder {
        let engine = try GenericEngine(
            data: .init(),
            enums: .init(unchecked: []),
            structs: .init(unchecked: [recordStructMap()])
        )
        return installEngine(engine, under: Folder("/project/Engines"), in: fst)
    }

    private func run(
        _ operation: Convert.Config.Operations,
        in fst: InMemoryFST,
        logger: Logger = SilentLogger()
    ) throws {
        let config = Convert.Config(operations: [OperationConfig(operation: operation, enabled: .yes)])
        try Convert.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    // MARK: - File format (GTX)

    func testDecodeFileWritesGTXArtifacts() throws {
        let fst = InMemoryFST()
        let gtxBinary = try GTXFixtures.model().binaryData
        try fst.writeFile(gtxBinary, at: File("/project/in/tex.gtx"), overwrite: true)

        try run(.decodeFile(
            inputFile: File("/project/in/tex.gtx"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .gtx
        ), in: fst)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/tex.gtx.json")), "expected GTX JSON manifest")
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/tex.gtx.png")), "expected GTX PNG companion")
    }

    func testDecodeThenEncodeFileRoundTripsGTX() throws {
        let fst = InMemoryFST()
        let gtxBinary = try GTXFixtures.model().binaryData
        try fst.writeFile(gtxBinary, at: File("/project/in/tex.gtx"), overwrite: true)

        try run(.decodeFile(
            inputFile: File("/project/in/tex.gtx"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .gtx
        ), in: fst)

        try run(.encodeFile(
            inputFolder: Folder("/project/out"),
            outputFolder: Folder("/project/rebuilt"),
            overwrite: true,
            format: .gtx
        ), in: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt/tex.gtx"))?.allData, "expected rebuilt GTX binary")
        assertBytesEqual(rebuilt, gtxBinary, "GTX round trip")
    }

    func testDecodeThenEncodeFileRoundTripsGSW() throws {
        let fst = InMemoryFST()
        let gswBinary = try GSWFixtures.model().binaryData
        try fst.writeFile(gswBinary, at: File("/project/in/menu.gsw"), overwrite: true)

        try run(.decodeFile(
            inputFile: File("/project/in/menu.gsw"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .gsw
        ), in: fst)
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/menu.gsw.json")), "expected GSW JSON manifest")

        try run(.encodeFile(
            inputFolder: Folder("/project/out"),
            outputFolder: Folder("/project/rebuilt"),
            overwrite: true,
            format: .gsw
        ), in: fst)
        XCTAssertNotNil(fst.readFile(at: File("/project/rebuilt/menu.gsw"))?.allData, "expected rebuilt GSW binary")
    }

    func testDecodeThenEncodePairedISF() throws {
        let fst = InMemoryFST()
        // Write both halves adjacent, same stem — the decode derives `.isd`
        // from the `.ish` input.
        let binaries = try ISFFixtures.model().binaries
        for binary in binaries {
            try fst.writeFile(binary.data, at: File("/project/in/\(binary.file.fileName)"), overwrite: true)
        }

        try run(.decodeFile(
            inputFile: File("/project/in/\(ISFFixtures.name).ish"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .ish
        ), in: fst)
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/\(ISFFixtures.name).isf.json")), "expected ISF JSON manifest")
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/\(ISFFixtures.name).wav")), "expected WAV companion")

        try run(.encodeFile(
            inputFolder: Folder("/project/out"),
            outputFolder: Folder("/project/rebuilt"),
            overwrite: true,
            format: .ish
        ), in: fst)
        // Paired encode restores both halves (ISF is a lossy codec, so we
        // assert the pair is produced, not byte-equality).
        XCTAssertNotNil(fst.readFile(at: File("/project/rebuilt/\(ISFFixtures.name).ish")), "expected rebuilt ISH")
        XCTAssertNotNil(fst.readFile(at: File("/project/rebuilt/\(ISFFixtures.name).isd")), "expected rebuilt ISD")
    }

    func testDecodePairedISFFailsWhenCompanionMissing() throws {
        let fst = InMemoryFST()
        // Only the header half present — the `.isd` is missing.
        let ish = try XCTUnwrap(ISFFixtures.model().binaries.first { $0.file.fileName.hasSuffix(".ish") })
        try fst.writeFile(ish.data, at: File("/project/in/\(ISFFixtures.name).ish"), overwrite: true)

        XCTAssertThrowsError(try run(.decodeFile(
            inputFile: File("/project/in/\(ISFFixtures.name).ish"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .ish
        ), in: fst))
    }

    // MARK: - File format (PBR font, same `.fnt` extension as the GS font)

    func testDecodeThenEncodeFileRoundTripsAPBRFontUnderTheSharedExtension() throws {
        let fst = InMemoryFST()
        let font = PBRFont(blocks: [
            .init(language: "J", nominalSize: 32, glyphs: [
                .init(code: 0x41, width: 4, firstRow: 0, lastRow: 1,
                      lineHeight: 26, bitmap: [0x12, 0x34, 0x56, 0x78]),
            ]),
        ])
        try fst.writeFile(font.data, at: File("/project/in/menu.fnt"), overwrite: true)

        // The bytes are a PBR font, so `fntColoXD` would be wrong here: the
        // format name is what routes to the PBR registry, not the extension.
        try run(.decodeFile(
            inputFile: File("/project/in/menu.fnt"),
            outputFolder: Folder("/project/out"),
            overwrite: true,
            format: .fntPBR
        ), in: fst)
        try run(.encodeFile(
            inputFolder: Folder("/project/out"),
            outputFolder: Folder("/project/rebuilt"),
            overwrite: true,
            format: .fntPBR
        ), in: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt/menu.fnt"))?.allData, "expected rebuilt PBR font")
        assertBytesEqual(rebuilt, font.data, "PBR font round trip through Convert")
    }

    // MARK: - Struct

    func testDecodeStructWritesJSONThenEncodesBackToBinary() throws {
        let fst = InMemoryFST()
        let engineFolder = try installRecordEngine(in: fst)
        let original = GoDData(byteStream: [0x00, 0x00, 0x00, 0x2A, 0xDE, 0xAD, 0xBE, 0xEF], byteOrder: .big)
        try fst.writeFile(original, at: File("/project/in/record.bin"), overwrite: true)

        try run(.decodeStruct(
            inputFile: File("/project/in/record.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/json/record.json")), "expected struct JSON")

        try run(.encodeStruct(
            inputFile: File("/project/json/record.json"),
            outputFolder: Folder("/project/bin"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/bin/record.bin"))?.allData, "expected rebuilt binary")
        assertBytesEqual(rebuilt, original, "struct round trip")
    }

    func testDecodeStructFailsWhenSizeMismatch() throws {
        let fst = InMemoryFST()
        let engineFolder = try installRecordEngine(in: fst)
        // 6 bytes, but TestRecord is 8.
        try fst.writeFile(GoDData(byteStream: [1, 2, 3, 4, 5, 6], byteOrder: .big),
                      at: File("/project/in/bad.bin"), overwrite: true)

        XCTAssertThrowsError(try run(.decodeStruct(
            inputFile: File("/project/in/bad.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst))
    }

    // MARK: - Struct table

    func testDecodeStructTableWritesArrayThenEncodesBack() throws {
        let fst = InMemoryFST()
        let engineFolder = try installRecordEngine(in: fst)
        // Three 8-byte records = 24 bytes.
        let original = GoDData(byteStream: (0..<24).map { UInt8($0) }, byteOrder: .big)
        try fst.writeFile(original, at: File("/project/in/table.bin"), overwrite: true)

        try run(.decodeStructTable(
            inputFile: File("/project/in/table.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/json/table.json")), "expected table JSON")

        try run(.encodeStructTable(
            inputFile: File("/project/json/table.json"),
            outputFolder: Folder("/project/bin"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst)

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/bin/table.bin"))?.allData, "expected rebuilt table binary")
        assertBytesEqual(rebuilt, original, "struct table round trip")
    }

    func testDecodeStructTableFailsWhenStructDoesNotTile() throws {
        let fst = InMemoryFST()
        let engineFolder = try installRecordEngine(in: fst)
        // 20 bytes is not a multiple of 8.
        try fst.writeFile(GoDData(byteStream: (0..<20).map { UInt8($0) }, byteOrder: .big),
                      at: File("/project/in/ragged.bin"), overwrite: true)

        XCTAssertThrowsError(try run(.decodeStructTable(
            inputFile: File("/project/in/ragged.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "TestRecord",
            engines: [engineFolder]
        ), in: fst))
    }

    // MARK: - Multiple engines

    /// A struct that names an enum another engine declares. Each engine is
    /// installed under its own parent because `GenericEngine` serializes to
    /// a fixed folder name.
    private func installSplitEngines(in fst: InMemoryFST) throws -> (game: Folder, pokemon: Folder) {
        let game = try GenericEngine(
            data: .init(),
            enums: .init(unchecked: []),
            structs: .init(unchecked: [StructMap(
                name: "Gift",
                wordSize: 4,
                alignmentStyle: .cStyle,
                properties: [
                    .abstraction(name: "species", typeName: "Species"),
                    .uint16(name: "level"),
                ]
            )])
        )
        let pokemon = try GenericEngine(
            data: .init(),
            enums: .init(unchecked: [Enum(
                name: "Species", allowUnknownCases: false,
                values: [.init(name: "Bulbasaur", rawValue: 1)], propertyType: .uint16
            )]),
            structs: .init(unchecked: [])
        )
        return (
            installEngine(game, under: Folder("/project/Engines/Game"), in: fst),
            installEngine(pokemon, under: Folder("/project/Engines/Pokemon"), in: fst)
        )
    }

    func testStructResolvesAnEnumDeclaredByAnotherListedEngine() throws {
        let fst = InMemoryFST()
        let engines = try installSplitEngines(in: fst)
        let original = GoDData(byteStream: [0x00, 0x01, 0x00, 0x05], byteOrder: .big)
        try fst.writeFile(original, at: File("/project/in/gift.bin"), overwrite: true)

        try run(.decodeStruct(
            inputFile: File("/project/in/gift.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "Gift",
            engines: [engines.game, engines.pokemon]
        ), in: fst)

        let json = try XCTUnwrap(fst.readFile(at: File("/project/json/gift.json"))?.allData)
        XCTAssertTrue(json.string(format: .utf8).contains("Bulbasaur"),
                      "the enum from the second engine should abstract the species field")

        try run(.encodeStruct(
            inputFile: File("/project/json/gift.json"),
            outputFolder: Folder("/project/bin"),
            overwrite: true,
            structName: "Gift",
            engines: [engines.game, engines.pokemon]
        ), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/bin/gift.bin"))?.allData)
        assertBytesEqual(rebuilt, original, "cross-engine struct round trip")
    }

    func testStructFailsWhenTheEngineDeclaringItsEnumIsNotListed() throws {
        let fst = InMemoryFST()
        let engines = try installSplitEngines(in: fst)
        try fst.writeFile(GoDData(byteStream: [0, 1, 0, 5], byteOrder: .big),
                          at: File("/project/in/gift.bin"), overwrite: true)

        XCTAssertThrowsError(try run(.decodeStruct(
            inputFile: File("/project/in/gift.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "Gift",
            engines: [engines.game]
        ), in: fst))
    }

    func testEmptyEngineListIsAnError() throws {
        let fst = InMemoryFST()
        try fst.writeFile(GoDData(byteStream: [0, 1, 0, 5], byteOrder: .big),
                          at: File("/project/in/gift.bin"), overwrite: true)

        XCTAssertThrowsError(try run(.decodeStruct(
            inputFile: File("/project/in/gift.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "Gift",
            engines: []
        ), in: fst)) { error in
            guard case ConvertErrors.noEngines(let name, _) = error else {
                return XCTFail("expected noEngines, got \(error)")
            }
            XCTAssertEqual(name, "Gift")
        }
    }

    func testDuplicateNamesAcrossEnginesAreWarnedAndTheFirstWins() throws {
        let fst = InMemoryFST()
        // Two engines both declare TestRecord: the second's is half the size.
        let first = try installRecordEngine(in: fst)
        let smaller = try GenericEngine(
            data: .init(),
            enums: .init(unchecked: []),
            structs: .init(unchecked: [StructMap(
                name: "TestRecord", wordSize: 4, alignmentStyle: .cStyle,
                properties: [.uint32(name: "only")]
            )])
        )
        let second = installEngine(smaller, under: Folder("/project/Engines/Other"), in: fst)
        // 8 bytes: exactly one of the first engine's record, two of the second's.
        try fst.writeFile(GoDData(byteStream: (0..<8).map { UInt8($0) }, byteOrder: .big),
                          at: File("/project/in/record.bin"), overwrite: true)

        let logger = RecordingLogger()
        try run(.decodeStruct(
            inputFile: File("/project/in/record.bin"),
            outputFolder: Folder("/project/json"),
            overwrite: true,
            structName: "TestRecord",
            engines: [first, second]
        ), in: fst, logger: logger)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/json/record.json")),
                        "the first engine's 8-byte TestRecord should have matched the input")
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings.first?.contains("TestRecord") ?? false, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings.first?.contains("earliest listed engine wins") ?? false)
    }
}
