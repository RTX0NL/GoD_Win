import XCTest
import Foundation
import GoDFoundation
import Dolphin

final class RELFileTests: XCTestCase {

    // MARK: - Synthetic round-trip

    /// Build a minimal REL: 1 section (8 bytes of code), 1 import with 2
    /// relocations, version 3 header. Assert binary → parse → binary is
    /// byte-identical.
    func testSyntheticV3RELRoundTripsByteIdentical() throws {
        var rel = RELFile(
            moduleID: 42,
            version: 3,
            sections: [
                .init(index: 0, size: 0, isExecutable: false, isBSS: false),
                .init(index: 1, size: 8, isExecutable: true, isBSS: false,
                      data: [0x4E, 0x80, 0x00, 0x20, 0x60, 0x00, 0x00, 0x00])
            ],
            imports: [
                .init(moduleID: 42, relocations: [
                    .init(seekOffset: 0x10, command: RELFile.Relocation.R_PPC_ADDR32,
                          targetSection: 1, addend: 0x100)
                ]),
                .init(moduleID: 0, relocations: [
                    .init(seekOffset: 0x20, command: RELFile.Relocation.R_PPC_REL24,
                          targetSection: 0, addend: 0x200)
                ])
            ]
        )
        rel.prologSection = 1
        rel.epilogSection = 1
        rel.unresolvedSection = 1
        rel.sectionAlign = 4
        rel.bssAlign = 1

        let binary = try rel.binaryData
        let reParsed = try RELFile(binary: binary)
        let reSerialized = try reParsed.binaryData
        XCTAssertEqual(reSerialized.rawBytes, binary.rawBytes,
                       "REL parse → serialize → parse → serialize must be stable")

        XCTAssertEqual(reParsed.moduleID, 42)
        XCTAssertEqual(reParsed.version, 3)
        XCTAssertEqual(reParsed.sections.count, 2)
        XCTAssertEqual(reParsed.sections[1].size, 8)
        XCTAssertTrue(reParsed.sections[1].isExecutable)
        XCTAssertEqual(reParsed.imports.count, 2)
        XCTAssertEqual(reParsed.imports[0].relocations.count, 1)
        XCTAssertEqual(reParsed.imports[0].relocations[0].command, RELFile.Relocation.R_PPC_ADDR32)
    }

    // MARK: - Real samples

    func testWindmillRELRoundTrips() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/M2_windmill_1F/M2_windmill_1F.rel"
        try assertRealSampleRoundTrips(at: path, expectedSections: 10, expectedImports: 2)
    }

    func testPocketMenuRELRoundTrips() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pocket_menu/pocket_menu.rel"
        try assertRealSampleRoundTrips(at: path, expectedSections: 9, expectedImports: 2)
    }

    /// Asserts that parsing a real REL exposes the expected structure and
    /// that re-parsing the serialized bytes yields the same sections,
    /// imports, and relocation chains.
    private func assertRealSampleRoundTrips(
        at path: String,
        expectedSections: Int,
        expectedImports: Int
    ) throws {
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("REL sample not available: \(path)")
        }
        let original = try RELFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big))
        XCTAssertEqual(original.sections.count, expectedSections)
        XCTAssertEqual(original.imports.count, expectedImports)

        let serialized = try original.binaryData
        let reParsed = try RELFile(binary: serialized)
        XCTAssertEqual(reParsed.moduleID, original.moduleID)
        XCTAssertEqual(reParsed.version, original.version)
        XCTAssertEqual(reParsed.sections.count, original.sections.count)
        XCTAssertEqual(reParsed.imports.count, original.imports.count)
        for (a, b) in zip(reParsed.sections, original.sections) {
            XCTAssertEqual(a.size, b.size)
            XCTAssertEqual(a.isExecutable, b.isExecutable)
            XCTAssertEqual(a.isBSS, b.isBSS)
            XCTAssertEqual(a.data, b.data)
        }
        for (a, b) in zip(reParsed.imports, original.imports) {
            XCTAssertEqual(a.moduleID, b.moduleID)
            XCTAssertEqual(a.relocations, b.relocations)
        }
    }

    // MARK: - JSON outputs

    func testOutputsContainJSONAndOneSidecarPerNonEmptySection() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/M2_windmill_1F/M2_windmill_1F.rel"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("M2_windmill_1F.rel not available")
        }
        let rel = try RELFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            name: "windmill"
        )
        let artifacts = try rel.outputs

        XCTAssertNotNil(artifacts[File("windmill.rel.json")],
                        "expected named JSON artifact")

        let nonEmptyDataSections = rel.sections.filter { !$0.isBSS && $0.size > 0 }
        let binKeys = artifacts.keys.filter { $0.path.hasSuffix(".bin") }
        XCTAssertEqual(binKeys.count, nonEmptyDataSections.count,
                       "one .bin sidecar per non-empty non-BSS section")

        // Roundtrip through outputs.
        let rebuilt = try RELFile(outputs: artifacts).binaryData
        let reParsed = try RELFile(binary: rebuilt)
        XCTAssertEqual(reParsed.sections.count, rel.sections.count)
    }

    // MARK: - Convenience init

    public func testConvenienceInitsCompose() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pocket_menu/pocket_menu.rel"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pocket_menu.rel not available")
        }
        let rel = try RELFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big), name: "pocket")
        XCTAssertEqual(rel.name, "pocket")
        XCTAssertEqual(rel.jsonFilename, File("pocket.rel.json"))
        XCTAssertEqual(rel.sectionBinFilename(index: 1), File("pocket_section_001.bin"))
    }
}

