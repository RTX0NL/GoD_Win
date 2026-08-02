//
//  ColoScriptOperationTests.swift
//  GODOpsTests
//
//  Exercises the real ColoXD.dump script-decompile operation against an
//  InMemoryFST: install a Colosseum engine, seed a synthetic .scd, run the
//  op for each language, and confirm the emitted source recompiles to the
//  exact input bytes (so the operation + its language flag are lossless).
//

import XCTest
import Foundation
import GoDFoundation
import Colosseum
import ScriptDecompiler
@testable import GODOps

final class ColoScriptOperationTests: XCTestCase {

    /// Minimal single-function script: `function_0() { return }` (+ implicit
    /// terminating returnOp) then exit — a complete, valid .scd.
    private func makeScriptBytes() -> [UInt8] {
        var bytes = [UInt8]()
        bytes += [0x01, 0x00]                    // scriptTypeID
        bytes += [0x01, 0x01]                    // headerField2
        bytes += [0x00, 0x01]                    // 1 function
        bytes += [0x00, 0x00]                    // relocation count
        bytes += [0x00, 0x2A]                    // compilerMetadata
        bytes += [0x00, 0x00]                    // relocatedFlag
        bytes += [0x00, 0x00, 0x00, 0x1C]        // reloc table offset (= code start)
        bytes += [0x00, 0x00, 0x00, 0x1C]        // globals arena offset (empty)
        bytes += [0x00, 0x00, 0x00, 0x00]        // runtime next pointer
        bytes += [0x00, 0x00, 0x00, 0x1C]        // function 0 → 0x1C
        bytes += [0x05, 0x01]                    // returnOp, exit
        // pad to 32-byte boundary
        while bytes.count % 32 != 0 { bytes.append(0) }
        return bytes
    }

    private func runDump(language: ColoScriptLanguage) throws -> (fst: InMemoryFST, output: File) {
        let fst = InMemoryFST()
        let engineFolder = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)

        let scdFile = File("/project/Assets/Scripts/test.scd")
        try fst.writeFile(GoDData(byteStream: makeScriptBytes(), byteOrder: .big), at: scdFile, overwrite: true)

        let config = ColoXD.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpColoScript(
                    scdFile: scdFile,
                    outputFolder: Folder("/project/Source/Scripts"),
                    overwrite: true,
                    language: language,
                    gameEngine: engineFolder
                ),
                enabled: .yes
            )
        ])
        try ColoXD.dump(config: config, settings: .default, fileSystem: fst, logger: nil)

        return (fst, File("/project/Source/Scripts/test.\(language.fileExtension)"))
    }

    func testDumpSwiftDecompilesAndRecompilesByteExact() throws {
        let (fst, outFile) = try runDump(language: .swift)
        guard let source = fst.readFile(at: outFile)?.allData?.string(format: .utf8) else {
            return XCTFail("no .swift output written")
        }
        XCTAssertTrue(source.contains("func function_0()"))

        var parser = ColoScriptTextParser(builtInFunctions: [:])
        let compiled = try ColoScriptCompiler().compile(parser.parse(source)).rawBytes
        XCTAssertEqual(compiled, makeScriptBytes())
    }

    func testDumpPythonDecompilesAndRecompilesByteExact() throws {
        let (fst, outFile) = try runDump(language: .python)
        guard let source = fst.readFile(at: outFile)?.allData?.string(format: .utf8) else {
            return XCTFail("no .py output written")
        }
        XCTAssertTrue(source.contains("def function_0()"))

        var parser = ColoScriptTextParser(builtInFunctions: [:])
        let compiled = try ColoScriptCompiler().compile(parser.parse(source)).rawBytes
        XCTAssertEqual(compiled, makeScriptBytes())
    }

    /// Full operation round trip: dump `.scd` → source, then build source →
    /// `.scd`, entirely through the real ColoXD dump/build operations. The
    /// rebuilt binary must byte-match the original for both languages.
    func testDumpThenBuildOperationsAreByteExact() throws {
        for language in ColoScriptLanguage.allCases {
            let fst = InMemoryFST()
            let engineFolder = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)

            let scdFile = File("/project/Assets/Scripts/test.scd")
            try fst.writeFile(GoDData(byteStream: makeScriptBytes(), byteOrder: .big), at: scdFile, overwrite: true)

            let sourceFolder = Folder("/project/Source/Scripts")
            try ColoXD.dump(config: ColoXD.DumpConfig(operations: [
                OperationConfig(operation: .dumpColoScript(
                    scdFile: scdFile, outputFolder: sourceFolder,
                    overwrite: true, language: language,
                    gameEngine: engineFolder), enabled: .yes)
            ]), settings: .default, fileSystem: fst, logger: nil)

            let rebuiltFolder = Folder("/project/rebuilt")
            try ColoXD.build(config: ColoXD.BuildConfig(operations: [
                OperationConfig(operation: .buildColoScript(
                    sourceFile: sourceFolder.file("test.\(language.fileExtension)"),
                    outputFile: rebuiltFolder.file("test.scd"),
                    overwrite: true, gameEngine: engineFolder), enabled: .yes)
            ]), settings: .default, fileSystem: fst, logger: nil)

            let rebuilt = fst.readFile(at: rebuiltFolder.file("test.scd"))?.allData?.rawBytes
            XCTAssertEqual(rebuilt, makeScriptBytes(), "\(language) dump→build not byte-exact")
        }
    }

    /// The language flag selects the output extension and survives JSON config
    /// serialization (so it works from a `Dump-Config.json` on disk).
    func testLanguageFlagRoundTripsThroughConfigJSON() throws {
        for language in ColoScriptLanguage.allCases {
            let op = ColoXD.DumpConfig.Operations.dumpColoScript(
                scdFile: File("/a.scd"), outputFolder: Folder("/out"),
                overwrite: true, language: language, gameEngine: Folder("/engine"))
            let data: Data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(ColoXD.DumpConfig.Operations.self, from: data)
            guard case .dumpColoScript(_, _, _, let decodedLanguage, _) = decoded else {
                return XCTFail("wrong case decoded")
            }
            XCTAssertEqual(decodedLanguage, language)
        }
    }
}
