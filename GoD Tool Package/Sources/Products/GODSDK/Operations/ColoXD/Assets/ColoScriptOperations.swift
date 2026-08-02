//
//  ColoScriptOperations.swift
//  GODOps
//
//  Colosseum scripts (`.scd`) <-> source text.
//
//  Unlike the other asset formats these don't round-trip through a JSON
//  manifest: a script decompiles to readable source in one of two dialects and
//  recompiles from it. Both directions need the game engine, which is what
//  declares the builtin function signatures the text refers to by name.
//

import Foundation
import GoDFoundation
import Colosseum
import ScriptDecompiler

extension ColoXD {

    static func dumpColoScripts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        language: ColoScriptLanguage,
        gameEngine: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try ColosseumEngine(from: gameEngine, in: fileSystem)
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "scd" },
            label: "Colosseum script",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try scriptSource(
                    file: file, stem: stem, language: language,
                    engine: engine, fileSystem: fileSystem
                )
            }
        )
    }

    static func dumpColoScript(
        scdFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        language: ColoScriptLanguage,
        gameEngine: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try ColosseumEngine(from: gameEngine, in: fileSystem)
        try dumpSingle(
            file: scdFile,
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try scriptSource(
                    file: file, stem: stem, language: language,
                    engine: engine, fileSystem: fileSystem
                )
            }
        )
    }

    static func buildColoScripts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        gameEngine: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try ColosseumEngine(from: gameEngine, in: fileSystem)
        try buildBatch(
            in: folder,
            // Either dialect rebuilds to the same bytecode.
            matching: { $0.fileType == "swift" || $0.fileType == "py" },
            stem: { $0.fileName.withoutExtensions },
            label: "Colosseum script",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { source, stem in
                [FileData(
                    fileName: "\(stem).scd",
                    data: try scriptBinary(source: source, engine: engine, fileSystem: fileSystem)
                )]
            }
        )
    }

    static func buildColoScript(
        sourceFile: File,
        outputFile: File,
        overwrite: Bool,
        gameEngine: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let engine = try ColosseumEngine(from: gameEngine, in: fileSystem)
        let binary = try scriptBinary(source: sourceFile, engine: engine, fileSystem: fileSystem)
        try fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(sourceFile.fileName) → \(outputFile.fileName)"))
    }

    // MARK: - Format work

    private static func scriptSource(
        file: File,
        stem: String,
        language: ColoScriptLanguage,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file)?.allData else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let script = try ColoScript(data: data)
        let source = ColoScriptSourceEmitter(
            builtInFunctions: engine.scriptBuiltInFunctionsByID,
            enums: engine.enumsByName
        ).decompileToText(script: script, fileName: file.fileName, syntax: language)
        return [FileData(
            fileName: "\(stem).\(language.fileExtension)",
            data: GoDData(byteStream: Array(source.utf8), byteOrder: .big)
        )]
    }

    private static func scriptBinary(
        source: File,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        guard let sourceData = fileSystem.readFile(at: source)?.allData else {
            throw FSTErrors.fileNotFound(source, .init())
        }
        var parser = ColoScriptTextParser(builtInFunctions: engine.scriptBuiltInFunctionsByID)
        let parsed = try parser.parse(sourceData.string(format: .utf8))
        return try ColoScriptCompiler().compile(parsed)
    }
}
