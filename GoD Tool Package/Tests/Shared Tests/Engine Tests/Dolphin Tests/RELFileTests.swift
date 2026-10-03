import XCTest
import Foundation
import GoDFoundation
import Dolphin

/// One test per protocol member. Each asserts a single step; no
/// roundtrips. Uses real XD REL samples as the "known binary" input and
/// hand-built values as the "known properties" input.
///
/// The on-disc relocation list is derived at serialize time from
/// SymbolRefs on text instructions / pointer chunks in data, so tests
/// exercise that rather than a stored `imports` array.
final class RELFileTests: XCTestCase {

    /// Folders of real `.rel` files to walk. The two project dumps, plus
    /// whatever `GODDESS_REL_CORPUS` names (a colon-separated list), so the
    /// corpus tests can run against RELs extracted anywhere.
    private static let corpusSearchPaths: [String] = {
        var paths = [
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Data/Relocatable Modules",
            "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Build/Unpacked/Data/Relocatable Modules",
        ]
        if let extra = ProcessInfo.processInfo.environment["GODDESS_REL_CORPUS"] {
            paths += extra.split(separator: ":").map(String.init)
        }
        return paths
    }()

    private static func firstCorpusFile(named stem: String) -> [UInt8]? {
        for dir in corpusSearchPaths {
            let path = "\(dir)/\(stem).rel"
            if FileManager.default.fileExists(atPath: path),
               let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return [UInt8](raw)
            }
        }
        return nil
    }

    // MARK: - init(binary:)

    /// Parses a real XD REL (version 3, 10 sections) and asserts specific
    /// header fields + derived body shapes. All values here were extracted
    /// from the on-disc header before writing this test.
    func testREL_initBinary_parsesHeaderAndSectionBodies() throws {
        guard let raw = Self.firstCorpusFile(named: "M2_windmill_1F") else {
            throw XCTSkip("M2_windmill_1F.rel not available")
        }
        let rel = try RELFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "windmill")

        XCTAssertEqual(rel.name, "windmill")
        XCTAssertEqual(rel.moduleID, 31)
        XCTAssertEqual(rel.version, 3)
        XCTAssertEqual(rel.sectionAlign, 4)
        XCTAssertEqual(rel.bssAlign, 1)
        XCTAssertEqual(rel.bssSize, 0, "no BSS section in windmill")
        XCTAssertEqual(rel.prologSection, 1)
        XCTAssertEqual(rel.prologOffset, 0)
        XCTAssertEqual(rel.epilogSection, 1)
        XCTAssertEqual(rel.epilogOffset, 0x9C)
        XCTAssertEqual(rel.unresolvedSection, 1)
        XCTAssertEqual(rel.unresolvedOffset, 0x118)

        XCTAssertEqual(rel.sections.count, 10)
        XCTAssertTrue(rel.sections[1].isExecutable, "section 1 holds code")
        XCTAssertEqual(rel.sections[1].size, 0x134)
        if case .text(let ins) = rel.sections[1].body {
            XCTAssertEqual(ins.count, 0x134 / 4)
            // Epilog has known DOL relocations on its lis/addi/stw triples.
            XCTAssertTrue(ins.contains { $0.ref?.moduleID == 0 },
                          "expected at least one DOL-targeted SymbolRef in the epilog")
        } else {
            XCTFail("section 1 body should be .text")
        }

        XCTAssertFalse(rel.sections[3].isExecutable, "section 3 holds data")
        XCTAssertEqual(rel.sections[3].size, 0xBC)
        if case .data(let chunks) = rel.sections[3].body {
            XCTAssertFalse(chunks.isEmpty)
        } else {
            XCTFail("section 3 body should be .data")
        }

        XCTAssertEqual(rel.importedModules.count, 2)
        XCTAssertEqual(rel.importedModules[0], 31,
                       "first import is self-referencing (moduleID = own)")
    }

    /// A REL header has no magic, so the version and section count are what
    /// reject a file that isn't one. The first 0x20 bytes here are XD's
    /// `tractorbeam.rel` — a particle file with a `.rel` name — which used to
    /// parse into an empty module and rebuild as 76 bytes.
    func testREL_initBinary_rejectsAFileThatIsntARel() {
        var bytes: [UInt8] = [
            0x01, 0xF0, 0x56, 0xDA, 0x00, 0x03, 0x00, 0x02, 0x00, 0x3F, 0x00, 0x13, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4C, 0xE0, 0x01, 0x00, 0x04, 0x04,
        ]
        bytes += [UInt8](repeating: 0, count: 0x60)
        XCTAssertThrowsError(try RELFile(binary: GoDData(byteStream: bytes, byteOrder: .big), name: "tractorbeam"))

        // The same header with a real version but no sections is rejected too.
        bytes[0x1C...0x1F] = [0, 0, 0, 3]
        XCTAssertThrowsError(try RELFile(binary: GoDData(byteStream: bytes, byteOrder: .big), name: "empty"))
    }

    // MARK: - binaryData

    /// Builds a minimal v3 REL with a single 8-byte executable section
    /// containing two instructions, and one self-relocation expressed as
    /// a SymbolRef. Asserts exact bytes at known offsets — catches any
    /// change to the serializer layout or derived-reloc encoding.
    func testREL_binaryData_writesKnownHeaderAndRelocationChain() throws {
        let selfRef = RELFile.SymbolRef(moduleID: 0x2A, section: 1, offset: 0x100)
        // Two instructions: a `blr` (0x4E800020) and a nop that carries a
        // self-ADDR32 fixup. ADDR32 on a text word is non-standard but the
        // serializer only cares about the byte-level encoding.
        let nopWithRef = RELFile.TextInstruction(raw: 0x60000000, ref: selfRef, fixup: .addr32)
        let blr = RELFile.TextInstruction(raw: 0x4E800020)
        let section1 = RELFile.Section(index: 1, body: .text([blr, nopWithRef]))
        let section0 = RELFile.Section(index: 0, body: .empty(fileOffset: 0))

        var rel = RELFile(
            moduleID: 0x2A,
            version: 3,
            sections: [section0, section1],
            importedModules: [0x2A]
        )
        rel.prologSection = 1
        rel.sectionAlign = 4
        rel.bssAlign = 1
        let bytes = try rel.binaryData.rawBytes

        // Header
        XCTAssertEqual(Array(bytes[0..<4]), [0x00, 0x00, 0x00, 0x2A], "moduleID")
        XCTAssertEqual(Array(bytes[0x0C..<0x10]), [0x00, 0x00, 0x00, 0x02], "section count = 2")
        XCTAssertEqual(Array(bytes[0x10..<0x14]), [0x00, 0x00, 0x00, 0x4C], "section table offset")
        XCTAssertEqual(Array(bytes[0x1C..<0x20]), [0x00, 0x00, 0x00, 0x03], "version 3")
        XCTAssertEqual(bytes[0x30], 1, "prolog section")

        // Section table at 0x4C — two entries × 8 bytes.
        // Section 0 is .empty → offset=0, size=0.
        XCTAssertEqual(Array(bytes[0x4C..<0x54]), [UInt8](repeating: 0, count: 8))
        // Section 1 is .text with 2 insns → offset=0x5C | 1, size=8.
        let sec1Raw = UInt32(bytes[0x54]) << 24 | UInt32(bytes[0x55]) << 16
                    | UInt32(bytes[0x56]) << 8  | UInt32(bytes[0x57])
        XCTAssertEqual(sec1Raw & ~UInt32(1), 0x5C, "section 1 file offset")
        XCTAssertEqual(sec1Raw & 1, 1, "exec flag set on section 1")
        XCTAssertEqual(Array(bytes[0x58..<0x5C]), [0x00, 0x00, 0x00, 0x08], "section 1 size")

        // Section 1 bytes at 0x5C — blr, then nop (raw preserved as-is,
        // even though it carries a SymbolRef).
        XCTAssertEqual(Array(bytes[0x5C..<0x64]),
                       [0x4E, 0x80, 0x00, 0x20, 0x60, 0x00, 0x00, 0x00])

        // Import table (8 bytes: moduleID + chain offset) then the
        // derived relocation chain: R_DOLPHIN_SECTION for section 1, the
        // ADDR32 edge at instruction 1 (offset 4), R_DOLPHIN_END.
        let importTableOff = 0x64
        let chainOff = importTableOff + 8
        // Entry 0: section marker.
        XCTAssertEqual(Array(bytes[chainOff..<(chainOff + 8)]),
                       [0x00, 0x00, 202, 0x01, 0x00, 0x00, 0x00, 0x00],
                       "chain begins with R_DOLPHIN_SECTION for section 1")
        // Entry 1: ADDR32 at offset 4 in section 1, target section 1, addend 0x100.
        XCTAssertEqual(Array(bytes[(chainOff + 8)..<(chainOff + 16)]),
                       [0x00, 0x04, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00])
        // Entry 2: END.
        XCTAssertEqual(bytes[chainOff + 16 + 2], 203,
                       "chain must end with R_DOLPHIN_END")
    }

    // MARK: - init(outputs:)

    /// Construct a JSON artifact representing a trivial REL and confirm
    /// `init(outputs:)` rebuilds the declared semantic structure.
    func testREL_initOutputs_roundTripsJSON() throws {
        // Build a minimal REL, encode to JSON via `outputs`, decode back.
        let rel = RELFile(
            moduleID: 123,
            version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text([.init(raw: 0x60000000)])),
                .init(index: 2, body: .data([.binary(bytes: [0xAA, 0xBB, 0xCC, 0xDD])])),
                .init(index: 3, body: .bss(size: 16)),
            ],
            importedModules: []
        )
        var namedRel = rel
        namedRel.name = "mod"
        namedRel.prologSection = 1
        namedRel.sectionAlign = 4
        namedRel.bssAlign = 1

        let artifacts = try namedRel.outputs
        let reloaded = try RELFile(outputs: artifacts)

        XCTAssertEqual(reloaded.name, "mod")
        XCTAssertEqual(reloaded.moduleID, 123)
        XCTAssertEqual(reloaded.sections.count, 4)
        XCTAssertEqual(reloaded.sections[2].size, 4,
                       "size derived from .data chunk lengths")
        XCTAssertTrue(reloaded.sections[1].isExecutable)
        XCTAssertTrue(reloaded.sections[3].isBSS)
        XCTAssertEqual(reloaded.bssSize, 16, "derived from .bss body")
    }

    // MARK: - outputs

    /// `outputs` is the source tree: a manifest that carries no bytes, plus
    /// one assembly file per text section (and per data section), plus the
    /// human summary.
    func testREL_outputs_emitsManifestAndSectionSources() throws {
        var rel = RELFile(
            moduleID: 7,
            version: 3,
            sections: [
                .init(index: 0, body: .empty(fileOffset: 0)),
                .init(index: 1, body: .text([.init(raw: 0x60000000)])),
            ],
            importedModules: []
        )
        rel.name = "mod"
        let artifacts = try rel.outputs

        XCTAssertEqual(artifacts.first?.file, File("mod.rel.json"), "manifest comes first")
        XCTAssertEqual(
            Set(artifacts.map(\.file.path)), ["mod.rel.json", "text1.s", "sections.txt"],
            "one .s per non-empty section beside the manifest"
        )
        let text = String(data: artifacts.first!.data.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"moduleID\" : \"0x7\""),
                      "moduleID should emit as hex; got: \(text.prefix(200))")
        XCTAssertTrue(text.contains("\"file\" : \"text1.s\""), "the manifest points at the section source")
        XCTAssertFalse(text.contains("\"raw\""), "no instruction words in the manifest")
        XCTAssertFalse(text.contains("\"bytes\""), "no chunk bytes in the manifest")

        let source = String(data: artifacts.first { $0.file.path == "text1.s" }!.data.data, encoding: .utf8) ?? ""
        XCTAssertTrue(source.contains("nop"), "the text section is real assembly; got: \(source)")
    }

    // MARK: - Convenience naming

    func testREL_jsonFilenameFollowsNamePattern() {
        var rel = RELFile(moduleID: 1, version: 3)
        rel.name = "pocket"
        XCTAssertEqual(rel.jsonFilename, File("pocket.rel.json"))
    }

    /// Dump a tiny REL's JSON to stdout so we can see the wire format
    /// when tuning (e.g. HexInt migrations). Enabled via env var.
    func testREL_printJSONSample() throws {
        guard ProcessInfo.processInfo.environment["PRINT_REL_JSON"] != nil else {
            throw XCTSkip("set PRINT_REL_JSON=1 to enable")
        }
        guard let raw = Self.firstCorpusFile(named: "D1_garage_1F") else {
            throw XCTSkip("sample REL not available")
        }
        let rel = try RELFile(binary: GoDData(byteStream: raw, byteOrder: .big), name: "sample")
        let artifacts = try rel.outputs
        let json = artifacts.first!.data.data
        let text = String(data: json, encoding: .utf8) ?? ""
        // Show head + tail (where .bss / .empty cases usually live) so
        // we can see every body shape.
        print("--- head ---")
        print(String(text.prefix(3000)))
        print("--- tail ---")
        print(String(text.suffix(3000)))
    }

    // MARK: - Outputs/init(outputs:) lossless roundtrip

    /// Every REL in the corpus must roundtrip byte-identically through
    /// `outputs` (JSON) and `init(outputs:)` — this is what the assembly
    /// operation relies on. Catches any semantic state we're emitting
    /// only to the binary writer and forgetting in the JSON DTO.
    func testREL_outputsRoundtripIsByteIdentical() throws {
        var tested = 0
        var failed: [(String, Int)] = []
        for dir in Self.corpusSearchPaths {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".rel") {
                let path = "\(dir)/\(name)"
                guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
                let input = [UInt8](raw)
                let stem = name.replacingOccurrences(of: ".rel", with: "")
                let rel: RELFile
                do {
                    rel = try RELFile(binary: GoDData(byteStream: input, byteOrder: .big), name: stem)
                } catch {
                    failed.append(("parse-failed: \(path)", 0)); continue
                }
                let outputs: [FileData]
                do { outputs = try rel.outputs } catch {
                    failed.append(("outputs-failed: \(path)", 0)); continue
                }
                let rebuilt: RELFile
                do { rebuilt = try RELFile(outputs: outputs) } catch {
                    failed.append(("initOutputs-failed: \(path)", 0)); continue
                }
                let serialized: [UInt8]
                do { serialized = try rebuilt.binaryData.rawBytes } catch {
                    failed.append(("serialize-failed: \(path)", 0)); continue
                }
                tested += 1
                if serialized != input {
                    let diverge = zip(input, serialized).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(input.count, serialized.count)
                    failed.append((path, diverge))
                }
            }
        }
        if tested == 0 { throw XCTSkip("no REL corpus found") }
        if !failed.isEmpty {
            XCTFail("\(failed.count)/\(tested) failed; first 5: \(failed.prefix(5))")
        }
    }

    // MARK: - Corpus roundtrip (byte-identical)

    /// Walk the XD + Colo REL corpora and assert binary→RELFile→binary
    /// reproduces the input byte-for-byte. Any divergence points at an
    /// ordering/alignment rule the semantic model still needs to capture.
    func testREL_corpusRoundtripIsByteIdentical() throws {
        var tested = 0
        var failed: [(String, Int)] = []  // (path, firstDivergingByte)
        for dir in Self.corpusSearchPaths {
            let url = URL(fileURLWithPath: dir)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".rel") {
                let path = url.appendingPathComponent(name).path
                guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
                let input = [UInt8](raw)
                let rel: RELFile
                do {
                    rel = try RELFile(binary: GoDData(byteStream: input, byteOrder: .big),
                                      name: name.replacingOccurrences(of: ".rel", with: ""))
                } catch {
                    failed.append(("parse-failed: \(path)", 0))
                    continue
                }
                let output: [UInt8]
                do {
                    output = try rel.binaryData.rawBytes
                } catch {
                    failed.append(("serialize-failed: \(path)", 0))
                    continue
                }
                tested += 1
                if output != input {
                    let diverge = zip(input, output).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(input.count, output.count)
                    failed.append((path, diverge))
                }
            }
        }
        if tested == 0 {
            throw XCTSkip("no REL corpus found")
        }
        if !failed.isEmpty {
            XCTFail("\(failed.count)/\(tested) RELs failed roundtrip; first 5: \(failed.prefix(5))")
        }
    }
}
