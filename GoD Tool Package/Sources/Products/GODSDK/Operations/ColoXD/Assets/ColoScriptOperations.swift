//
//  ColoScriptOperations.swift
//  GODOps
//
//  Colosseum scripts (`.scd`) <-> source text.
//
//  Unlike the other asset formats these don't round-trip through a JSON
//  manifest: a script decompiles to readable source in one of two dialects and
//  recompiles from it. Both directions need the game engine, which is what
//  declares the builtin function signatures the text refers to by name, and
//  the engine list, which is what resolves the enums those signatures name.
//

import Foundation
import GoDFoundation
import Colosseum
import Structs
import ScriptDecompiler

extension ColoXD {

    static func dumpColoScripts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        language: ColoScriptLanguage,
        gameEngine: Folder,
        engines: [Folder]?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let context = try scriptContext(
            gameEngine: gameEngine, engines: engines, fileSystem: fileSystem, logger: logger
        )
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
                    context: context, fileSystem: fileSystem
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
        engines: [Folder]?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let context = try scriptContext(
            gameEngine: gameEngine, engines: engines, fileSystem: fileSystem, logger: logger
        )
        try dumpSingle(
            file: scdFile,
            label: "Colosseum script",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try scriptSource(
                    file: file, stem: stem, language: language,
                    context: context, fileSystem: fileSystem
                )
            }
        )
    }

    static func buildColoScripts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        gameEngine: Folder,
        engines: [Folder]?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let context = try scriptContext(
            gameEngine: gameEngine, engines: engines, fileSystem: fileSystem, logger: logger
        )
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
                    data: try scriptBinary(source: source, context: context, fileSystem: fileSystem)
                )]
            }
        )
    }

    static func buildColoScript(
        sourceFile: File,
        outputFile: File,
        overwrite: Bool,
        gameEngine: Folder,
        engines: [Folder]?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let task = "Build Colosseum script file"
        logger?.log(.taskStatus(taskName: task, status: .started))
        let context = try scriptContext(
            gameEngine: gameEngine, engines: engines, fileSystem: fileSystem, logger: logger
        )
        do {
            let binary = try scriptBinary(source: sourceFile, context: context, fileSystem: fileSystem)
            try fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        } catch {
            // A failed compile is the whole operation here, and the reason is
            // worth saying out loud: an unresolvable `EnumName.case` throws
            // from the parser, and its message names the line.
            logger?.log(.error("Failed to build \(sourceFile.fileName): \(error)"))
            logger?.log(.taskStatus(taskName: task, status: .completed(false)))
            throw error
        }
        logger?.log(.info("  \(sourceFile.fileName) → \(outputFile.fileName)"))
        logger?.log(.taskStatus(taskName: task, status: .completed(true)))
    }

    // MARK: - Resolution context

    /// What both directions need: the builtin signatures, and the enums those
    /// signatures name.
    ///
    /// The two are resolved from different places on purpose. Signatures are
    /// the Colosseum engine's own data — only it knows what builtin 218 is
    /// called. The enums are looked up across the whole `engines` list, in the
    /// order given, so a signature can name a type its own engine doesn't
    /// declare.
    struct ScriptContext {
        let builtInFunctions: [Int: ScriptFunctionDef]
        let enums: [String: Enum]
    }

    private static func scriptContext(
        gameEngine: Folder,
        engines: [Folder]?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> ScriptContext {
        let engine = try ColosseumEngine(from: gameEngine, in: fileSystem)
        // Absent = just the game engine, which carries every enum its own
        // builtin signatures currently name. A longer list is how a signature
        // reaches an enum declared somewhere else.
        let folders = engines ?? [gameEngine]
        let combined = try GenericEngine(combining: folders, in: fileSystem)
        let shadowed = combined.shadowedNames.enums
        if !shadowed.isEmpty {
            // First engine in the list wins, so the rest are unreachable —
            // and an enum resolving to a different case set than its author
            // meant renders confident, wrong names.
            logger?.log(.warning(
                "Enum name(s) declared by more than one engine, earliest wins: "
                    + shadowed.joined(separator: ", ")
            ))
        }
        return ScriptContext(
            builtInFunctions: engine.scriptBuiltInFunctionsByID,
            enums: Dictionary(
                combined.enums.entries.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    // MARK: - Format work

    private static func scriptSource(
        file: File,
        stem: String,
        language: ColoScriptLanguage,
        context: ScriptContext,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file)?.allData else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let script = try ColoScript(data: data)
        let source = ColoScriptSourceEmitter(
            builtInFunctions: context.builtInFunctions,
            enums: context.enums
        ).decompileToText(script: script, fileName: file.fileName, syntax: language)
        return [FileData(
            fileName: "\(stem).\(language.fileExtension)",
            data: GoDData(byteStream: Array(source.utf8), byteOrder: .big)
        )]
    }

    private static func scriptBinary(
        source: File,
        context: ScriptContext,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        guard let sourceData = fileSystem.readFile(at: source)?.allData else {
            throw FSTErrors.fileNotFound(source, .init())
        }
        var parser = ColoScriptTextParser(
            builtInFunctions: context.builtInFunctions,
            enums: context.enums
        )
        let parsed = try parser.parse(sourceData.string(format: .utf8))
        return try ColoScriptCompiler().compile(parsed)
    }
}
