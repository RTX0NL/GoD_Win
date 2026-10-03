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

    // MARK: - Enum-typed arguments through the real operations

    /// The unit tests resolve enums from `ColosseumEngine.Enums.allItems` in
    /// memory; this one resolves them the way a project does — out of a
    /// *serialized* engine folder, through the `engines` list the operation
    /// takes — and is therefore the only check that the enum a signature names
    /// survives being written to disk and read back.
    func testOperationsResolveEnumArgumentsFromTheEngineFolder() throws {
        let fst = InMemoryFST()
        let engineFolder = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)

        // Compile the input rather than hand-building bytecode: what is under
        // test is the operations' enum resolution, not a byte layout.
        let builtins = ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
        var compiler = ColoScriptTextParser(builtInFunctions: builtins)
        let original = try ColoScriptCompiler().compile(compiler.parse("""
        static let __scriptType = 0x100
        static let __compilerMetadata = 0x0

        func function_0() {
            soundPlayPokemonCry(25)
        }
        """))

        let scdFile = File("/project/Assets/Scripts/cry.scd")
        try fst.writeFile(original, at: scdFile, overwrite: true)

        let sourceFolder = Folder("/project/Source/Scripts")
        try ColoXD.dump(config: ColoXD.DumpConfig(operations: [
            OperationConfig(operation: .dumpColoScript(
                scdFile: scdFile, outputFolder: sourceFolder,
                overwrite: true, language: .python,
                gameEngine: engineFolder,
                engines: [engineFolder]), enabled: .yes)
        ]), settings: .default, fileSystem: fst, logger: nil)

        guard let source = fst.readFile(at: sourceFolder.file("cry.py"))?.allData?.string(format: .utf8) else {
            return XCTFail("no .py output written")
        }
        XCTAssertTrue(
            source.contains("soundPlayPokemonCry(PokemonSpecies.PIKACHU)"),
            "species 25 should render as its case name; got:\n\(source)"
        )

        // And back: the enum spelling the dump wrote compiles to the bytes it
        // was rendered from.
        let rebuiltFolder = Folder("/project/rebuilt")
        try ColoXD.build(config: ColoXD.BuildConfig(operations: [
            OperationConfig(operation: .buildColoScript(
                sourceFile: sourceFolder.file("cry.py"),
                outputFile: rebuiltFolder.file("cry.scd"),
                overwrite: true, gameEngine: engineFolder,
                engines: [engineFolder]), enabled: .yes)
        ]), settings: .default, fileSystem: fst, logger: nil)

        XCTAssertEqual(
            fst.readFile(at: rebuiltFolder.file("cry.scd"))?.allData?.rawBytes,
            original.rawBytes
        )
    }

    /// A source file naming an enum no engine in the list declares fails the
    /// build. The alternative — treating it as an unknown identifier, or as a
    /// zero — would write a script that means something the author didn't say.
    func testBuildFailsOnAnUnresolvableEnumName() throws {
        let fst = InMemoryFST()
        let engineFolder = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let sourceFile = File("/project/Source/Scripts/bad.py")
        try fst.writeFile("""
        __SCRIPT_TYPE__ = 0x100
        __COMPILER_METADATA__ = 0x0

        def function_0():
            soundPlayPokemonCry(Pokemon.PIKACHU)
        """.data(format: .utf8), at: sourceFile, overwrite: true)

        XCTAssertThrowsError(
            try ColoXD.build(config: ColoXD.BuildConfig(operations: [
                OperationConfig(operation: .buildColoScript(
                    sourceFile: sourceFile,
                    outputFile: File("/project/rebuilt/bad.scd"),
                    overwrite: true, gameEngine: engineFolder,
                    engines: [engineFolder]), enabled: .yes)
            ]), settings: .default, fileSystem: fst, logger: nil)
        ) { error in
            guard case ColoScriptTextParser.ParseError.unknownEnum(let name, _) = error else {
                return XCTFail("expected unknownEnum, got \(error)")
            }
            XCTAssertEqual(name, "Pokemon")
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
            guard case .dumpColoScript(_, _, _, let decodedLanguage, _, _) = decoded else {
                return XCTFail("wrong case decoded")
            }
            XCTAssertEqual(decodedLanguage, language)
        }
    }
}
