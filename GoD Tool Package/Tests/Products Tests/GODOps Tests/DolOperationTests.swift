//
//  DolOperationTests.swift
//  GODOpsTests
//
//  Runs the real DolDisassembly/DolAssembly operations against an InMemoryFST
//  with a small in-memory DOL (one text section of real PPC instructions).
//  No symbol map — output is the single-file-per-section layout.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
import Disassembler
import GoDEngine
import Structs
@testable import GODOps

/// Trivial registry format for tests: the artifact is the binary with
/// every byte XORed with 0xFF. A raw-bytes fallback (the old, buggy
/// rebuild path) would embed the artifact bytes and fail the byte-exact
/// assertions.
private struct TestBlobFormat: FileFormat {
    static let formatName = "blob"
    var name = "blob"
    private let raw: [UInt8]

    init(binaries: [FileData]) throws {
        guard let first = binaries.first else { throw Self.invalidFileError }
        raw = first.data.rawBytes
    }

    var binaries: [FileData] {
        [FileData(file: File("blob.blob"), data: GoDData(byteStream: raw, byteOrder: .big))]
    }

    init(outputs: [FileData]) throws {
        guard let first = outputs.first else { throw Self.invalidFileError }
        raw = first.data.rawBytes.map { $0 ^ 0xFF }
    }

    var outputs: [FileData] {
        [FileData(file: File("blob.blob.enc"), data: GoDData(byteStream: raw.map { $0 ^ 0xFF }, byteOrder: .big))]
    }
}

final class DolOperationTests: XCTestCase {

    // stwu r1, -0x10(r1); mflr r0; li r3, 0x42; mtlr r0; addi r1, r1, 0x10; blr
    // No lis/branch instructions, so relocation analysis finds nothing and the
    // formatted text round-trips through the assembler verbatim.
    private static let instructionWords: [UInt32] = [
        0x9421_FFF0,
        0x7C08_02A6,
        0x3860_0042,
        0x7C08_03A6,
        0x3821_0010,
        0x4E80_0020,
    ]

    private static let textRAMAddress: UInt32 = 0x80003100
    private static let entryPoint: UInt32 = 0x80003100

    private static var textSectionBytes: [UInt8] {
        instructionWords.flatMap { word in
            [UInt8(word >> 24 & 0xFF), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)]
        }
    }

    private func makeProject() throws -> (fst: InMemoryFST, dolphinFolder: Folder, engine: DolphinEngine) {
        let fst = InMemoryFST()
        let engine = try DolphinEngine.defaults()
        let folder = installEngine(engine, under: Folder("/project/Engines"), in: fst)
        return (fst, folder, engine)
    }

    private static let dataRAMAddress: UInt32 = 0x80004000
    private static let text1RAMAddress: UInt32 = 0x80003200

    private func seedDol(
        in fst: InMemoryFST,
        engine: DolphinEngine,
        dataBytes: [UInt8]? = nil,
        textWords: [UInt32]? = nil,
        secondTextWords: [UInt32]? = nil
    ) throws {
        let assembly = GoDData(byteOrder: .big)
        for word in textWords ?? Self.instructionWords { assembly.append(word) }
        var textSections = [Dol.TextSection(RAMAddress: Self.textRAMAddress, assembly: assembly)]
        if let secondTextWords {
            let second = GoDData(byteOrder: .big)
            for word in secondTextWords { second.append(word) }
            textSections.append(Dol.TextSection(RAMAddress: Self.text1RAMAddress, assembly: second))
        }
        var dataSections = [Dol.DataSection]()
        if let dataBytes {
            dataSections.append(Dol.DataSection(
                RAMAddress: Self.dataRAMAddress,
                data: GoDData(byteStream: dataBytes, byteOrder: .big)
            ))
        }
        let dol = Dol(
            dolphinEngine: engine,
            textSections: textSections,
            dataSections: dataSections,
            bssRAMAddress: 0,
            bssSize: 0,
            entryPoint: Self.entryPoint
        )
        try fst.writeFile(try dol.data, at: File("/project/main.dol"), overwrite: true)
    }

    private func disassemble(
        in fst: InMemoryFST,
        dolphinFolder: Folder,
        symbolMapPath: File? = nil,
        typeMapPath: File? = nil,
        engines: [Folder]? = nil,
        registry: FileFormatRegistry = .all(),
        logger: Logger = SilentLogger()
    ) throws {
        let config = DolDisassembly.Config(
            dolPath: File("/project/main.dol"),
            outputFolder: Folder("/project/Disassembly"),
            symbolMapPath: symbolMapPath,
            dolphinEngine: dolphinFolder,
            typeMapPath: typeMapPath,
            engines: engines
        )
        try DolDisassembly.disassemble(config: config, settings: .default, fileSystem: fst, logger: logger, registry: registry)
    }

    private func assemble(
        in fst: InMemoryFST,
        dolphinFolder: Folder,
        typeMapPath: File? = nil,
        engines: [Folder]? = nil,
        registry: FileFormatRegistry = .all(),
        symbolMapPath: File? = nil,
        outputSymbolMapPath: File? = nil,
        allowResizedChunks: Bool? = nil
    ) throws {
        let config = DolAssembly.Config(
            codeFolder: Folder("/project/Disassembly/main"),
            outputDolPath: File("/project/rebuilt.dol"),
            symbolMapPath: symbolMapPath,
            outputSymbolMapPath: outputSymbolMapPath,
            dolphinEngine: dolphinFolder,
            typeMapPath: typeMapPath,
            engines: engines,
            allowResizedChunks: allowResizedChunks
        )
        try DolAssembly.assemble(config: config, settings: .default, fileSystem: fst, logger: SilentLogger(), registry: registry)
    }

    private func blobRegistry() -> FileFormatRegistry {
        var registry = FileFormatRegistry()
        registry.register("blob", TestBlobFormat.self)
        return registry
    }

    /// Type map declaring a single `.file` chunk of `blobSize` bytes at
    /// 0x80004008 (offset 0x08 into the data section).
    private func writeTypeMap(in fst: InMemoryFST, blobSize: Int) throws -> File {
        let typeMap = TypeMap(chunks: [
            .file(.init(label: "lbl_80004008", extension: "blob", size: blobSize))
        ])
        let json: GoDData = try JSONEncoder().encode(typeMap)
        let path = File("/project/typemap.json")
        try fst.writeFile(json, at: path, overwrite: true)
        return path
    }

    func testDolDisassemblyWritesSectionsAndAssembly() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        try seedDol(in: fst, engine: engine)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        // Output lands in a subfolder named after the DOL ("main" for main.dol).
        let sections = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/sections.txt"))?.allData,
            "Expected sections.txt in the per-DOL output folder"
        )
        let sectionsText = sections.string(format: .utf8)
        XCTAssertTrue(sectionsText.contains("text0: 0x80003100"), "sections.txt must list the text section:\n\(sectionsText)")
        XCTAssertTrue(sectionsText.contains("# Entry point: 0x80003100"))

        let asm = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/text0.s"))?.allData,
            "Expected text0.s (single-file layout without a symbol map)"
        )
        let asmText = asm.string(format: .utf8)
        XCTAssertTrue(asmText.contains(".section .text0"))
        XCTAssertTrue(asmText.contains("blr"))
    }

    /// With a symbol map, each text section gets a `manifest.json` listing
    /// its function files in order. Its keys must come out in a fixed order:
    /// an unsorted encoder follows the per-process hash seed, so two dumps of
    /// the same disc differed in exactly these files.
    func testTextSectionManifestHasStableKeyOrder() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        try seedDol(in: fst, engine: engine)
        let map = File("/project/dol.map")
        try fst.writeFile(
            GoDData(string: """
            .text section layout
            80003100 00000018 80003100 0 __start\tos.a __start.o
            """, format: .utf8),
            at: map, overwrite: true
        )
        try disassemble(in: fst, dolphinFolder: dolphinFolder, symbolMapPath: map)

        let manifest = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/text0/manifest.json"))?.allData,
            "a symbol map should produce a per-function text section with a manifest"
        ).string(format: .utf8)
        XCTAssertTrue(manifest.hasPrefix("{\"files\":["), "keys must be sorted: \(manifest)")
        XCTAssertTrue(manifest.hasSuffix(",\"section\":\"text0\"}"), "keys must be sorted: \(manifest)")
    }

    func testDolDisassembleAssembleRoundTrip() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        try seedDol(in: fst, engine: engine)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        let asmConfig = DolAssembly.Config(
            codeFolder: Folder("/project/Disassembly/main"),
            outputDolPath: File("/project/rebuilt.dol"),
            dolphinEngine: dolphinFolder
        )
        try DolAssembly.assemble(config: asmConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)

        XCTAssertEqual(rebuilt.entryPoint, Self.entryPoint)
        XCTAssertEqual(rebuilt.textSections[0].RAMAddress, Self.textRAMAddress)
        XCTAssertEqual(
            rebuilt.textSections[0].assembly.rawBytes,
            Self.textSectionBytes,
            "reassembled text section must byte-match the original instructions"
        )
    }

    func testDolDisassemblyMissingDolThrows() throws {
        let (fst, dolphinFolder, _) = try makeProject()
        let config = DolDisassembly.Config(
            dolPath: File("/project/missing.dol"),
            outputFolder: Folder("/project/Disassembly"),
            dolphinEngine: dolphinFolder
        )
        XCTAssertThrowsError(
            try DolDisassembly.disassemble(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case DolDisassemblyErrors.dolNotFound = error else {
                return XCTFail("Expected DolDisassemblyErrors.dolNotFound, got \(error)")
            }
        }
    }

    // MARK: - Data section .file chunks (registry-routed)

    /// A type-mapped `.file` chunk dumps through the format registry
    /// (structured artifact in a per-chunk subfolder) and must rebuild
    /// through it too. Trailing bytes between the chunk's declared end
    /// and the end of the section must survive the round trip.
    func testDolDataFileChunkRegistryRoundTripPreservesGapBytes() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x80, 0x00, 0x40, 0x08,             // pointer → blob start (creates the label at +0x08)
            0xDE, 0xAD, 0xBE, 0xEF,             // plain word
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // blob (6 bytes, type-mapped .file chunk)
            0x00, 0x00, 0xCA, 0xFE, 0xBA, 0xBE, // gap after the blob — no label here
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        let typeMapPath = try writeTypeMap(in: fst, blobSize: 6)
        let registry = blobRegistry()
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, registry: registry)

        let artifact = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/data0/lbl_80004008/blob.blob.enc"))?.allData,
            "Expected the blob's registry artifact in a per-chunk subfolder"
        )
        XCTAssertEqual(artifact.rawBytes, [0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9],
                       "Artifact must be the XORed blob bytes, proving registry routing on dump")

        try assemble(in: fst, dolphinFolder: dolphinFolder, registry: registry)

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].RAMAddress, Self.dataRAMAddress)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, dataBytes,
                       "Data section must round-trip byte-exactly, including gap bytes after the blob")
    }

    /// Growing a `.file` chunk by editing its artifact must shift every
    /// label after it in the section, and pointers to those labels must
    /// follow. Pointers to addresses before the chunk stay put.
    ///
    /// The shift is what `allowResizedChunks` exists to gate: it is right
    /// here, because the edit was deliberate, and wrong when a writer
    /// re-derives a chunk a few bytes longer by accident.
    func testDolDataFileChunkResizeShiftsDownstreamPointers() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x80, 0x00, 0x40, 0x10,             // pointer → trailing word AFTER the blob
            0x80, 0x00, 0x40, 0x08,             // pointer → blob start
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // blob (8 bytes)
            0xCA, 0xFE, 0xBA, 0xBE,             // trailing chunk at +0x10
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        let typeMapPath = try writeTypeMap(in: fst, blobSize: 8)
        let registry = blobRegistry()
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, registry: registry)

        // Grow the blob from 8 to 12 bytes by editing its artifact.
        let grownBlob: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C]
        try fst.writeFile(
            GoDData(byteStream: grownBlob.map { $0 ^ 0xFF }, byteOrder: .big),
            at: File("/project/Disassembly/main/data0/lbl_80004008/blob.blob.enc"),
            overwrite: true
        )

        try assemble(in: fst, dolphinFolder: dolphinFolder, registry: registry, allowResizedChunks: true)

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        let expected: [UInt8] = [
            0x80, 0x00, 0x40, 0x14,             // shifted by +4: target label moved with the grown blob
            0x80, 0x00, 0x40, 0x08,             // unshifted: target sits before the blob
        ] + grownBlob + [0xCA, 0xFE, 0xBA, 0xBE]
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, expected,
                       "Pointer past the grown chunk must shift; pointer before it must not")
    }

    // MARK: - Chunk size enforcement

    /// A chunk that rebuilds shorter than it was dumped at is padded back
    /// to size rather than pulling everything after it backwards. The MSG
    /// writer re-derives its string layout and lands a byte or two under on
    /// real discs, which is what used to move every later symbol.
    func testAChunkThatRebuildsShortIsPaddedBackToSize() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x80, 0x00, 0x40, 0x10,             // pointer → the chunk after the blob
            0x80, 0x00, 0x40, 0x08,             // pointer → blob start, so a label lands there
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // blob (8 bytes)
            0xCA, 0xFE, 0xBA, 0xBE,
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        let typeMapPath = try writeTypeMap(in: fst, blobSize: 8)
        let registry = blobRegistry()
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, registry: registry)

        // Shrink the blob from 8 bytes to 5 by editing its artifact.
        let shortBlob: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        try fst.writeFile(
            GoDData(byteStream: shortBlob.map { $0 ^ 0xFF }, byteOrder: .big),
            at: File("/project/Disassembly/main/data0/lbl_80004008/blob.blob.enc"),
            overwrite: true
        )

        try assemble(in: fst, dolphinFolder: dolphinFolder, registry: registry)

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        let expected: [UInt8] = [
            0x80, 0x00, 0x40, 0x10,             // unshifted: the label after the blob has not moved
            0x80, 0x00, 0x40, 0x08,
        ] + shortBlob + [0x00, 0x00, 0x00]      // three zero bytes of padding
            + [0xCA, 0xFE, 0xBA, 0xBE]
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, expected)
    }

    /// A chunk that rebuilds longer stops the assembly by default, naming
    /// itself: it would move every symbol after it, and the type map that
    /// sits on top of the symbol map names its chunks by label.
    func testAChunkThatRebuildsLongStopsTheAssembly() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x00, 0x00, 0x00, 0x00,
            0x80, 0x00, 0x40, 0x08,             // pointer → blob start, so a label lands there
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0xCA, 0xFE, 0xBA, 0xBE,
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        let typeMapPath = try writeTypeMap(in: fst, blobSize: 8)
        let registry = blobRegistry()
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, registry: registry)

        let grownBlob: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
        try fst.writeFile(
            GoDData(byteStream: grownBlob.map { $0 ^ 0xFF }, byteOrder: .big),
            at: File("/project/Disassembly/main/data0/lbl_80004008/blob.blob.enc"),
            overwrite: true
        )

        XCTAssertThrowsError(
            try assemble(in: fst, dolphinFolder: dolphinFolder, registry: registry)
        ) { error in
            guard case let DolAssemblyErrors.chunkOverflow(section, label, recorded, assembled, _) = error else {
                return XCTFail("Expected chunkOverflow, got \(error)")
            }
            XCTAssertEqual(section, "data0")
            XCTAssertEqual(label, "lbl_80004008")
            XCTAssertEqual(recorded, 8)
            XCTAssertEqual(assembled, 10)
        }
    }

    /// A manifest written before chunk sizes were recorded has nothing to
    /// check against, and must still assemble.
    func testAChunkWithNoRecordedSizeIsNotEnforced() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        // Strip every `size` from the manifest, as an old dump would have it.
        let manifestFile = File("/project/Disassembly/main/data0/manifest.json")
        let raw = try XCTUnwrap(fst.readFile(at: manifestFile)?.allData)
        var manifest = try JSONDecoder().decode(DataSectionManifest.self, from: raw)
        manifest.chunks = manifest.chunks.map {
            .init(label: $0.label, type: $0.type, file: $0.file, structType: $0.structType)
        }
        try fst.writeFile(try JSONEncoder().encode(manifest), at: manifestFile, overwrite: true)

        try assemble(in: fst, dolphinFolder: dolphinFolder)
        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, dataBytes)
    }

    // MARK: - Symbol map rewrite

    /// The assembly writes the symbol map back out at the addresses it
    /// produced. Without that, a rebuild that shifts anything leaves the
    /// map — and the type map layered on it — pointing at the old
    /// addresses, and the next dump types the wrong bytes.
    func testAssemblyWritesTheSymbolMapItProduced() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x80, 0x00, 0x40, 0x08,             // pointer → label at +0x08
            0x00, 0x00, 0x00, 0x00,
            0xCA, 0xFE, 0xBA, 0xBE,
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        let inputMap = File("/project/dol.map")
        try fst.writeFile(
            GoDData(string: """
            .text section layout
            80003100 00000018 80003100 0 __start\tos.a __start.o
            """, format: .utf8),
            at: inputMap, overwrite: true
        )

        let outputMap = File("/project/rebuilt.map")
        try assemble(
            in: fst, dolphinFolder: dolphinFolder,
            symbolMapPath: inputMap, outputSymbolMapPath: outputMap
        )

        let written = try XCTUnwrap(fst.readFile(at: outputMap)?.allData)
        let symbols = SymbolMapParser().parse(written.string(format: .utf8))
        let byName = Dictionary(symbols.map { ($0.name, $0.address) }, uniquingKeysWith: { a, _ in a })

        XCTAssertEqual(byName["__start"], 0x8000_3100, "an input symbol keeps its address when nothing moved")
        XCTAssertEqual(
            byName["lbl_80004008"], 0x8000_4008,
            "a data chunk label the input map never had is added, so the type map can still resolve it"
        )
    }

    /// No output path, no map: the assembly leaves the project's map alone.
    func testAssemblyWritesNoSymbolMapWhenNoPathIsGiven() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        try seedDol(in: fst, engine: engine, dataBytes: [0xDE, 0xAD, 0xBE, 0xEF])
        try disassemble(in: fst, dolphinFolder: dolphinFolder)
        try assemble(in: fst, dolphinFolder: dolphinFolder)
        XCTAssertNil(fst.readFile(at: File("/project/rebuilt.map"))?.allData)
    }

    // MARK: - Shiftability guards

    /// A pointer-looking word whose target address is misaligned is a blob
    /// false positive: it must not mint a label or split a chunk, and the
    /// raw value must survive the round trip.
    func testMisalignedDataPointerTargetsDoNotMintLabels() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let dataBytes: [UInt8] = [
            0x80, 0x00, 0x40, 0x0D,             // "pointer" to odd in-range address — gated
            0x80, 0x00, 0x40, 0x08,             // real pointer → label at +0x08
            0xDE, 0xAD, 0xBE, 0xEF,
            0x00, 0x00, 0x00, 0x00,
        ]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        XCTAssertNil(fst.readFile(at: File("/project/Disassembly/main/data0/lbl_8000400D.s"))?.allData)
        XCTAssertNil(fst.readFile(at: File("/project/Disassembly/main/data0/lbl_8000400D.bin"))?.allData)
        XCTAssertNotNil(
            fst.readFile(at: File("/project/Disassembly/main/data0/lbl_80004008.bin"))?.allData,
            "aligned pointer target must still become a chunk boundary"
        )

        try assemble(in: fst, dolphinFolder: dolphinFolder)
        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, dataBytes)
    }

    /// Branches into another text section (millicode-style) must emit a
    /// shared label instead of a literal address, and still round-trip.
    func testCrossSectionBranchTargetsAreSymbolized() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        // text1 at 0x80003200 calls text0's entry at 0x80003100
        let text1Words: [UInt32] = [0x4BFF_FF01, 0x4E80_0020] // bl 0x80003100; blr
        try seedDol(in: fst, engine: engine, secondTextWords: text1Words)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        let text1 = try XCTUnwrap(fst.readFile(at: File("/project/Disassembly/main/text1.s"))?.allData).string(format: .utf8)
        XCTAssertTrue(text1.contains("bl lbl_80003100"),
                      "cross-section call must use a label, got:\n\(text1)")
        let text0 = try XCTUnwrap(fst.readFile(at: File("/project/Disassembly/main/text0.s"))?.allData).string(format: .utf8)
        XCTAssertTrue(text0.contains("lbl_80003100:"),
                      "target section must define the label the caller references")

        try assemble(in: fst, dolphinFolder: dolphinFolder)
        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.textSections[0].assembly.rawBytes, Self.textSectionBytes)
        XCTAssertEqual(
            rebuilt.textSections[1].assembly.rawBytes,
            [0x4B, 0xFF, 0xFF, 0x01, 0x4E, 0x80, 0x00, 0x20]
        )
    }

    /// Growing a data section that lies inside the small-data window must
    /// produce a loud warning — r13/r2 displacements don't relocate.
    func testSDAGuardWarnsOnSmallDataSectionSizeChange() throws {
        let (fst, dolphinFolder, _) = try makeProject()
        // lis r13, 0x8000; ori r13, r13, 0x8100; blr
        // → _SDA_BASE_ = 0x80008100, window 0x80000100-0x800100FF,
        //   which contains the data section at 0x80004000.
        let sdaInit: [UInt32] = [0x3DA0_8000, 0x61AD_8100, 0x4E80_0020]
        let dataBytes: [UInt8] = [
            0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        ]
        try seedDol(in: fst, engine: try DolphinEngine.defaults(), dataBytes: dataBytes, textWords: sdaInit)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        // Grow the section's single binary chunk by 4 bytes
        let grown = GoDData(byteStream: dataBytes + [0xAA, 0xBB, 0xCC, 0xDD], byteOrder: .big)
        try fst.writeFile(grown, at: File("/project/Disassembly/main/data0/lbl_80004000.bin"), overwrite: true)

        let logger = RecordingLogger()
        let asmConfig = DolAssembly.Config(
            codeFolder: Folder("/project/Disassembly/main"),
            outputDolPath: File("/project/rebuilt.dol"),
            dolphinEngine: dolphinFolder,
            // The resize is the point of this test, so accept it and let
            // the SDA guard have its say about where it landed.
            allowResizedChunks: true
        )
        try DolAssembly.assemble(config: asmConfig, settings: .default, fileSystem: fst, logger: logger)

        XCTAssertTrue(
            logger.warnings.contains { $0.contains("small-data window") },
            "expected an SDA guard warning, got: \(logger.warnings)"
        )
    }

    /// Same size change outside any small-data window must NOT warn.
    func testSDAGuardSilentWhenSectionOutsideWindow() throws {
        let (fst, dolphinFolder, _) = try makeProject()
        // SDA base far away from the data section: _SDA_BASE_ = 0x80408100
        let sdaInit: [UInt32] = [0x3DA0_8040, 0x61AD_8100, 0x4E80_0020]
        let dataBytes: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        try seedDol(in: fst, engine: try DolphinEngine.defaults(), dataBytes: dataBytes, textWords: sdaInit)
        try disassemble(in: fst, dolphinFolder: dolphinFolder)

        let grown = GoDData(byteStream: dataBytes + [0xAA, 0xBB, 0xCC, 0xDD], byteOrder: .big)
        try fst.writeFile(grown, at: File("/project/Disassembly/main/data0/lbl_80004000.bin"), overwrite: true)

        let logger = RecordingLogger()
        let asmConfig = DolAssembly.Config(
            codeFolder: Folder("/project/Disassembly/main"),
            outputDolPath: File("/project/rebuilt.dol"),
            dolphinEngine: dolphinFolder,
            allowResizedChunks: true
        )
        try DolAssembly.assemble(config: asmConfig, settings: .default, fileSystem: fst, logger: logger)

        XCTAssertFalse(logger.warnings.contains { $0.contains("small-data window") })
    }

    func testDolAssemblyMissingSectionsFileThrows() throws {
        let (fst, dolphinFolder, _) = try makeProject()
        let config = DolAssembly.Config(
            codeFolder: Folder("/project/EmptyCode"),
            outputDolPath: File("/project/rebuilt.dol"),
            dolphinEngine: dolphinFolder
        )
        XCTAssertThrowsError(
            try DolAssembly.assemble(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case DolAssemblyErrors.sectionsFileNotFound = error else {
                return XCTFail("Expected DolAssemblyErrors.sectionsFileNotFound, got \(error)")
            }
        }
    }

    // MARK: - Typed tables (CSV)

    /// Engine holding one struct with an enum-typed field and a pointer,
    /// so a dumped table exercises abstracted values and label columns.
    private func installTableEngine(in fst: InMemoryFST) throws -> Folder {
        let kind = Enum(
            name: "Kind",
            allowUnknownCases: false,
            values: [.init(name: "Fire", rawValue: 0), .init(name: "Water", rawValue: 1)],
            propertyType: .uint8
        )
        let entry = StructMap(
            name: "TestEntry",
            wordSize: 4,
            alignmentStyle: .none,
            properties: [
                .uint8(name: "level"),
                .abstraction(name: "kind", typeName: "Kind"),
                .uint16(name: "hp"),
                .label(name: "name_pointer"),
            ]
        )
        let engine = try GenericEngine(
            data: .init(),
            enums: .init(unchecked: [kind]),
            structs: .init(unchecked: [entry])
        )
        return installEngine(engine, under: Folder("/project/Engines"), in: fst)
    }

    /// Two 8-byte `TestEntry` values at 0x80004000.
    ///
    /// The first entry's pointer targets the table's own start address. That
    /// gives the label column something to resolve *and* is what mints the
    /// label at 0x80004000 in the first place — the type map matches chunks
    /// by label, so with nothing pointing there the section would have no
    /// labels and the whole thing would dump as one untyped chunk.
    private static let tableDataBytes: [UInt8] = [
        0x05, 0x01, 0x00, 0x64, 0x80, 0x00, 0x40, 0x00,
        0x09, 0x00, 0x00, 0xC8, 0x00, 0x00, 0x00, 0x00,
    ]

    private func writeTableTypeMap(in fst: InMemoryFST) throws -> File {
        let typeMap = TypeMap(chunks: [
            .table(.init(name: "TestTable", start: "lbl_80004000", entryType: "TestEntry", count: 2))
        ])
        let json: GoDData = try JSONEncoder().encode(typeMap)
        let path = File("/project/table-typemap.json")
        try fst.writeFile(json, at: path, overwrite: true)
        return path
    }

    func testTypedTableDumpsAsCSVWithAbstractedValues() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.tableDataBytes)
        let typeMapPath = try writeTableTypeMap(in: fst)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let csv = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/data0/TestTable.csv"))?.allData,
            "Expected the table to dump as CSV"
        ).string(format: .utf8)
        let rows = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(rows.first, "level,kind,hp,name_pointer")
        // Enum reads as its case name, not its index — the point of the format.
        XCTAssertEqual(rows[1], "5,Water,100,lbl_80004000")
        // A null pointer keeps the auto-label form the exporter gives it
        // (`TypedDataExporter` names every address, zero included); it
        // resolves straight back to 0, so the bytes still round-trip.
        XCTAssertEqual(rows[2], "9,Fire,200,lbl_00000000")

        // And no JSON artifact is left behind for the table.
        XCTAssertNil(fst.readFile(at: File("/project/Disassembly/main/data0/TestTable.json")),
                     "Tables are CSV only")

        // Entry symbols are metadata, so they live in the manifest rather
        // than as a column — a row is the struct's fields and nothing else.
        let manifestData = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/data0/manifest.json"))?.allData
        )
        let manifest = try JSONDecoder().decode(DataSectionManifest.self, from: manifestData)
        let chunk = try XCTUnwrap(manifest.chunks.first { $0.type == .table })
        XCTAssertEqual(chunk.file, "TestTable.csv")
        XCTAssertEqual(chunk.structType, "TestEntry")
        XCTAssertEqual(chunk.count, 2)
        XCTAssertEqual(chunk.entryLabels, ["0": "lbl_80004000"])
    }

    func testTypedTableCSVRoundTripsByteExactly() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.tableDataBytes)
        let typeMapPath = try writeTableTypeMap(in: fst)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, Self.tableDataBytes,
                       "The table must rebuild byte-exactly from the CSV alone")
    }

    /// An edit to a CSV cell has to reach the rebuilt DOL — otherwise the
    /// format is decoration.
    func testEditingACSVCellChangesTheRebuiltBytes() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.tableDataBytes)
        let typeMapPath = try writeTableTypeMap(in: fst)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let csvFile = File("/project/Disassembly/main/data0/TestTable.csv")
        let edited = try XCTUnwrap(fst.readFile(at: csvFile)?.allData)
            .string(format: .utf8)
            .replacingOccurrences(of: "5,Water,100", with: "7,Fire,999")
        try fst.writeFile(GoDData(string: edited, format: .utf8), at: csvFile, overwrite: true)

        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        var expected = Self.tableDataBytes
        expected[0] = 0x07          // level
        expected[1] = 0x00          // kind: Fire
        expected[2] = 0x03          // hp: 999 = 0x03E7
        expected[3] = 0xE7
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, expected)
    }

    // MARK: - Derived counts

    /// Two `TestEntry` rows, then a `uint16` count and two bytes of padding.
    /// The second row points at the count, which gives it a label.
    private static let countedTableBytes: [UInt8] = [
        0x05, 0x01, 0x00, 0x64, 0x80, 0x00, 0x40, 0x00,
        0x09, 0x00, 0x00, 0xC8, 0x80, 0x00, 0x40, 0x10,
        0x00, 0x02, 0xAB, 0xCD,
    ]

    private func writeCountedTypeMap(in fst: InMemoryFST, countType: IntegerProperties = .uint16) throws -> File {
        let typeMap = TypeMap(chunks: [
            .table(.init(name: "TestTable", start: "lbl_80004000", entryType: "TestEntry", count: 2)),
            .count(.init(label: "lbl_80004010", table: "lbl_80004000", type: countType)),
        ])
        let json: GoDData = try JSONEncoder().encode(typeMap)
        let path = File("/project/counted-typemap.json")
        try fst.writeFile(json, at: path, overwrite: true)
        return path
    }

    private func dataManifest(_ fst: InMemoryFST) throws -> DataSectionManifest {
        let data = try XCTUnwrap(fst.readFile(at: File("/project/Disassembly/main/data0/manifest.json"))?.allData)
        return try JSONDecoder().decode(DataSectionManifest.self, from: data)
    }

    private func editRows(_ fst: InMemoryFST, _ edit: ([String]) -> [String]) throws {
        let file = File("/project/Disassembly/main/data0/TestTable.csv")
        let lines = try XCTUnwrap(fst.readFile(at: file)?.allData).string(format: .utf8)
            .split(separator: "\n").map(String.init)
        try fst.writeFile(GoDData(string: edit(lines).joined(separator: "\n") + "\n", format: .utf8), at: file, overwrite: true)
    }

    /// A DOL count is its declared width; the bytes after it up to the next
    /// label stay a chunk of their own, and it rebuilds byte-exactly.
    func testADolCountIsDerivedAtItsDeclaredWidth() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.countedTableBytes)
        let typeMapPath = try writeCountedTypeMap(in: fst)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        let manifest = try dataManifest(fst)
        let count = try XCTUnwrap(manifest.chunks.first { $0.label == "lbl_80004010" })
        XCTAssertEqual(count.type, .count)
        XCTAssertEqual(count.countOf, "lbl_80004000")
        XCTAssertEqual(count.countType, .uint16)
        XCTAssertEqual(count.size, 2)
        XCTAssertTrue(manifest.chunks.contains { $0.label == "lbl_80004012" && $0.size == 2 },
                      "the padding after a narrower count is kept: \(manifest.chunks.map(\.label))")

        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        let rebuilt = try Dol(data: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData), dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, Self.countedTableBytes)
    }

    /// Code reaches a count through a small-data offset, so nothing points at
    /// it and it has no label. The type map's address is what places it.
    func testADolCountNothingPointsAtStillBecomesAChunk() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        var bytes = Self.countedTableBytes
        bytes.replaceSubrange(12..<16, with: [0, 0, 0, 0])
        try seedDol(in: fst, engine: engine, dataBytes: bytes)
        let typeMapPath = try writeCountedTypeMap(in: fst)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        let chunks = try dataManifest(fst).chunks
        let count = try XCTUnwrap(chunks.first { $0.label == "lbl_80004010" },
                                  "the count's address starts a chunk: \(chunks.map(\.label))")
        XCTAssertEqual(count.type, .count)

        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        XCTAssertEqual(try Dol(data: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData), dolphinEngine: engine)
            .dataSections[0].data.rawBytes, bytes)
    }

    /// A counted table is sized by its CSV. Removing a row changes the count;
    /// the DOL still holds the table to its recorded size, so the space the
    /// row took is zero-filled and nothing after it moves.
    func testRemovingARowUpdatesADolCount() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.countedTableBytes)
        let typeMapPath = try writeCountedTypeMap(in: fst)
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        try editRows(fst) { Array($0.dropLast()) }
        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let bytes = try Dol(data: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData), dolphinEngine: engine)
            .dataSections[0].data.rawBytes
        XCTAssertEqual(Array(bytes[0..<8]), Array(Self.countedTableBytes[0..<8]))
        XCTAssertEqual(Array(bytes[8..<16]), [UInt8](repeating: 0, count: 8), "the dropped row's space is zero-filled")
        XCTAssertEqual(Array(bytes[16...]), [0x00, 0x01, 0xAB, 0xCD], "the count follows the CSV")
    }

    /// Growing a counted table is a resize like any other on a DOL.
    func testAddingARowToADolTableNeedsAllowResizedChunks() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        try seedDol(in: fst, engine: engine, dataBytes: Self.countedTableBytes)
        let typeMapPath = try writeCountedTypeMap(in: fst)
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        try editRows(fst) { $0 + [$0[1]] }
        XCTAssertThrowsError(
            try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        ) { error in
            guard case DolAssemblyErrors.chunkOverflow = error else { return XCTFail("expected chunkOverflow, got \(error)") }
        }

        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder],
                     allowResizedChunks: true)
        let bytes = try Dol(data: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData), dolphinEngine: engine)
            .dataSections[0].data.rawBytes
        XCTAssertEqual(Array(bytes[24..<26]), [0x00, 0x03], "with the resize allowed, the count reports three rows")
    }

    /// A value that disagrees with its table keeps its bytes.
    func testADolCountThatDisagreesStaysRaw() throws {
        let (fst, dolphinFolder, engine) = try makeProject()
        let engineFolder = try installTableEngine(in: fst)
        var bytes = Self.countedTableBytes
        bytes[17] = 0x07
        try seedDol(in: fst, engine: engine, dataBytes: bytes)
        let typeMapPath = try writeCountedTypeMap(in: fst)
        let logger = RecordingLogger()
        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder], logger: logger)

        let chunk = try XCTUnwrap(try dataManifest(fst).chunks.first { $0.label == "lbl_80004010" })
        XCTAssertEqual(chunk.type, .binary)
        XCTAssertTrue(logger.warnings.contains { $0.contains("holds 7") }, "\(logger.warnings)")
        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        XCTAssertEqual(try Dol(data: try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData), dolphinEngine: engine)
            .dataSections[0].data.rawBytes, bytes)
    }

    /// A struct with a label *array* must still dump as a table. The dump's
    /// self-check compares the pointer names it recorded against the ones the
    /// CSV gives back, and `TypedDataExporter` names only top-level `.label`
    /// properties — so the CSV legitimately comes back with *more* names than
    /// went in. Treating that as a round-trip failure demoted every such
    /// table to raw binary.
    func testTableWithALabelArrayStaysATable() throws {
        let (fst, dolphinFolder, engine) = try makeProject()

        let entry = StructMap(
            name: "PointerPair",
            wordSize: 4,
            alignmentStyle: .none,
            properties: [.array(name: "pointers", count: 2, of: .label)]
        )
        let engineFolder = installEngine(
            try GenericEngine(data: .init(), enums: .init(unchecked: []), structs: .init(unchecked: [entry])),
            under: Folder("/project/Engines"),
            in: fst
        )

        // One entry; its first pointer targets the table start, which is what
        // mints the label the type map matches on.
        let dataBytes: [UInt8] = [0x80, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00]
        try seedDol(in: fst, engine: engine, dataBytes: dataBytes)

        let typeMap = TypeMap(chunks: [
            .table(.init(name: "Pairs", start: "lbl_80004000", entryType: "PointerPair", count: 1))
        ])
        let typeMapPath = File("/project/pairs-typemap.json")
        try fst.writeFile(try JSONEncoder().encode(typeMap) as GoDData, at: typeMapPath, overwrite: true)

        try disassemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])

        let csv = try XCTUnwrap(
            fst.readFile(at: File("/project/Disassembly/main/data0/Pairs.csv"))?.allData,
            "A label array must not demote the table to a raw binary chunk"
        ).string(format: .utf8)
        let rows = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(rows.first, "pointers[1],pointers[2]")
        XCTAssertEqual(rows[1], "lbl_80004000,")

        try assemble(in: fst, dolphinFolder: dolphinFolder, typeMapPath: typeMapPath, engines: [engineFolder])
        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.dol"))?.allData)
        let rebuilt = try Dol(data: rebuiltData, dolphinEngine: engine)
        XCTAssertEqual(rebuilt.dataSections[0].data.rawBytes, dataBytes)
    }
}
