import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// One test per protocol member. Each asserts a single step; no
/// roundtrips. Uses real XD REL samples as the "known binary" input and
/// hand-built values as the "known properties" input.
final class RELFileTests: XCTestCase {

    private var windmillBytes: [UInt8]? {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/M2_windmill_1F/M2_windmill_1F.rel"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](raw)
    }

    // MARK: - init(binary:)

    /// Parses the real M2_windmill_1F.rel (version 3, 10 sections, 2
    /// imports) and asserts specific header fields. All values here were
    /// extracted from the on-disc header before writing this test.
    func testREL_initBinary_parsesHeaderSectionsAndImports() throws {
        guard let raw = windmillBytes else { throw XCTSkip("windmill.rel not available") }
        let rel = try RELFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "windmill")

        XCTAssertEqual(rel.name, "windmill")
        XCTAssertEqual(rel.moduleID, 31)
        XCTAssertEqual(rel.version, 3)
        XCTAssertEqual(rel.sectionAlign, 4)
        XCTAssertEqual(rel.bssAlign, 1)
        XCTAssertEqual(rel.bssSize, 0)
        XCTAssertEqual(rel.prologSection, 1)
        XCTAssertEqual(rel.prologOffset, 0)
        XCTAssertEqual(rel.epilogSection, 1)
        XCTAssertEqual(rel.epilogOffset, 0x9C)
        XCTAssertEqual(rel.unresolvedSection, 1)
        XCTAssertEqual(rel.unresolvedOffset, 0x118)

        XCTAssertEqual(rel.sections.count, 10)
        XCTAssertTrue(rel.sections[1].isExecutable, "section 1 holds code")
        XCTAssertEqual(rel.sections[1].size, 0x134)
        XCTAssertFalse(rel.sections[3].isExecutable, "section 3 holds data")
        XCTAssertEqual(rel.sections[3].size, 0xBC)

        XCTAssertEqual(rel.imports.count, 2)
        XCTAssertEqual(rel.imports[0].moduleID, 31,
                       "first import is self-referencing (moduleID = own)")
    }

    // MARK: - binaryData

    /// Builds a minimal v3 REL with a single 8-byte executable section,
    /// one self-import with one R_PPC_ADDR32 relocation. Asserts the
    /// exact bytes emitted at known offsets — catches any change to the
    /// serializer layout.
    func testREL_binaryData_writesKnownHeaderAndRelocationChain() throws {
        var rel = RELFile(
            moduleID: 0x2A,
            version: 3,
            sections: [
                .init(index: 0, isExecutable: false),
                .init(index: 1, isExecutable: true,
                      data: [0x4E, 0x80, 0x00, 0x20, 0x60, 0x00, 0x00, 0x00])
            ],
            imports: [
                .init(moduleID: 0x2A, relocations: [
                    .init(seekOffset: 0x10,
                          command: RELFile.Relocation.R_PPC_ADDR32,
                          targetSection: 1,
                          addend: 0x100)
                ])
            ]
        )
        rel.prologSection = 1
        rel.sectionAlign = 4
        rel.bssAlign = 1
        let bytes = try rel.binaryData.rawBytes

        // Header
        XCTAssertEqual(Array(bytes[0..<4]),   [0x00, 0x00, 0x00, 0x2A], "moduleID")
        XCTAssertEqual(Array(bytes[0x0C..<0x10]), [0x00, 0x00, 0x00, 0x02], "section count = 2")
        XCTAssertEqual(Array(bytes[0x10..<0x14]), [0x00, 0x00, 0x00, 0x4C], "section table offset")
        XCTAssertEqual(Array(bytes[0x1C..<0x20]), [0x00, 0x00, 0x00, 0x03], "version 3")
        XCTAssertEqual(bytes[0x30], 1, "prolog section")

        // Section table at 0x4C — two entries × 8 bytes.
        // Section 0: offset=0, size=0.
        XCTAssertEqual(Array(bytes[0x4C..<0x54]), [UInt8](repeating: 0, count: 8))
        // Section 1: offset (with exec flag bit 0) = 0x5C | 1, size = 8.
        let sec1Raw = UInt32(bytes[0x54]) << 24 | UInt32(bytes[0x55]) << 16
                    | UInt32(bytes[0x56]) << 8  | UInt32(bytes[0x57])
        XCTAssertEqual(sec1Raw & ~UInt32(1), 0x5C, "section 1 file offset")
        XCTAssertEqual(sec1Raw & 1, 1, "exec flag set on section 1")
        XCTAssertEqual(Array(bytes[0x58..<0x5C]), [0x00, 0x00, 0x00, 0x08], "section 1 size")

        // Section 1 data at 0x5C.
        XCTAssertEqual(Array(bytes[0x5C..<0x64]),
                       [0x4E, 0x80, 0x00, 0x20, 0x60, 0x00, 0x00, 0x00])

        // Import table + relocation chain follow the section data.
        // First reloc entry: seek=0x10, command=R_PPC_ADDR32=1, target=1, addend=0x100.
        // Followed by a R_DOLPHIN_END terminator.
        let importTableOff = 0x64
        let relocOff = importTableOff + 8
        XCTAssertEqual(Array(bytes[relocOff..<(relocOff + 8)]),
                       [0x00, 0x10, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(bytes[relocOff + 8 + 2], RELFile.Relocation.R_DOLPHIN_END,
                       "chain must end with R_DOLPHIN_END")
    }

    // MARK: - init(outputs:)

    /// Construct outputs artifacts for a trivial REL and confirm
    /// init(outputs:) rebuilds the declared structure.
    func testREL_initOutputs_parsesJSONAndSectionBins() throws {
        // Section 0 is empty (no bssSize, no bin file).
        // Section 1 is an on-disc 4-byte code section (data comes from
        // the .bin file — no `size` declared in JSON).
        let jsonText = """
        {
          "moduleID": 123,
          "version": 3,
          "nextLink": 0,
          "prevLink": 0,
          "nameStringOffset": 0,
          "nameStringSize": 0,
          "bssSize": 0,
          "prologSection": 1,
          "epilogSection": 1,
          "unresolvedSection": 1,
          "headerPadByte": 0,
          "prologOffset": 0,
          "epilogOffset": 0,
          "unresolvedOffset": 0,
          "sectionAlign": 4,
          "bssAlign": 1,
          "fixSize": 0,
          "sections": [
            {"index": 0, "isExecutable": false},
            {"index": 1, "isExecutable": true}
          ],
          "imports": []
        }
        """
        let json = GoDData(data: jsonText.data(using: .utf8)!, byteOrder: .big)
        let sectionBytes = GoDData(byteStream: [0x60, 0x00, 0x00, 0x00], byteOrder: .big)
        let outputs: [File: GoDData] = [
            File("mod.rel.json"): json,
            File("mod_section_001.bin"): sectionBytes
        ]

        let parsed = try RELFile(outputs: outputs)
        XCTAssertEqual(parsed.name, "mod")
        XCTAssertEqual(parsed.moduleID, 123)
        XCTAssertEqual(parsed.sections.count, 2)
        XCTAssertEqual(parsed.sections[1].size, 4, "size derived from .bin byte count")
        XCTAssertTrue(parsed.sections[1].isExecutable)
        XCTAssertEqual(parsed.sections[1].data, [0x60, 0x00, 0x00, 0x00])
        XCTAssertFalse(parsed.sections[1].isBSS)
        XCTAssertTrue(parsed.imports.isEmpty)
    }

    // MARK: - outputs

    /// Given a known REL value, `outputs` must produce the expected set
    /// of artifacts with the right keys and inspectable metadata.
    func testREL_outputs_emitsJSONAndOneBinPerDataSection() throws {
        let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        var rel = RELFile(
            moduleID: 7,
            version: 3,
            sections: [
                .init(index: 0, isExecutable: false),
                .init(index: 1, isExecutable: true, data: payload),
                .init(index: 2, isExecutable: false),
                .init(index: 3, isExecutable: false,
                      data: [UInt8](repeating: 0xFF, count: 8)),
                .init(index: 4, isExecutable: false, bssSize: 16)    // BSS — no bytes
            ],
            imports: []
        )
        rel.name = "mod"
        let artifacts = try rel.outputs

        // Exactly one JSON + one .bin per non-BSS non-empty section.
        XCTAssertEqual(artifacts.count, 1 + 2)
        XCTAssertNotNil(artifacts[File("mod.rel.json")])
        XCTAssertEqual(artifacts[File("mod_section_001.bin")]?.rawBytes, payload)
        XCTAssertEqual(artifacts[File("mod_section_003.bin")]?.length, 8)
        XCTAssertNil(artifacts[File("mod_section_004.bin")],
                     "BSS section gets no sidecar")

        // JSON declares all 5 sections; the BSS section carries bssSize.
        let json = artifacts[File("mod.rel.json")]!.data
        let text = String(data: json, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"moduleID\" : 7"))
        XCTAssertTrue(text.contains("\"bssSize\" : 16"),
                      "BSS section is present in the JSON")
    }

    // MARK: - Convenience naming

    func testREL_jsonAndSectionFilenamesFollowNamePattern() {
        var rel = RELFile(moduleID: 1, version: 3)
        rel.name = "pocket"
        XCTAssertEqual(rel.jsonFilename, File("pocket.rel.json"))
        XCTAssertEqual(rel.sectionBinFilename(index: 7), File("pocket_section_007.bin"))
    }
}
