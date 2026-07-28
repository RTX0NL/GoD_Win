//
//  ColosseumXDDumpOperation.swift
//  
//
//  Created by Stars Momodu on 28/08/2024.
//

import GoDFoundation
import Dolphin
import GeniusSonority
import GTX
import Colosseum
import ScriptDecompiler

extension ColoXD {
    
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpColosseum(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
                
                let output = try geniusEngine.unpackProject(
                    from: fstFolder,
                    fileSystem: fileSystem,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)
            case let .dumpXD(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)

                let output = try geniusEngine.unpackProject(
                    from: fstFolder,
                    fileSystem: fileSystem,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)

            case let .unpackFSYS(fsysFile, outputFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let data = fileSystem.readFile(at: fsysFile) else {
                    throw FSTErrors.fileNotFound(fsysFile, .init())
                }

                let archive = try FSYSArchive(data: data, engine: gsEngine)
                let archiveName = fsysFile.fileName.withoutExtensions

                logger?.log(.info("Unpacking FSYS archive: \(fsysFile.fileName) (\(archive.entries.count) entries)"))

                // Build registry and extract files
                var registryEntries = [FSYSRegistry.Entry]()
                for entry in archive.entries {
                    let targetFolder = gsEngine.resolveFolder(
                        forFileType: entry.metadata.fileType,
                        entryFilename: entry.filename,
                        archiveName: archiveName
                    ).resolvedFolder
                    let targetFile = targetFolder.file(entry.filename)
                    registryEntries.append(.init(metadata: entry.metadata, file: targetFile))
                    if overwrite || fileSystem.inspectFile(at: targetFile) == nil {
                        try fileSystem.writeFile(entry.data, at: targetFile, overwrite: overwrite)
                    }
                }

                let registry = FSYSRegistry(
                    groupID: archive.groupID,
                    metaData: archive.metaData,
                    entries: registryEntries
                )
                let registryFile = outputFolder.file(archiveName + ".json")
                try fileSystem.encodeJSON(registry, to: registryFile, overwrite: overwrite)

                logger?.log(.info("Wrote registry: \(registryFile.fileName)"))

            case let .dumpAssets(format, input, outputFolder, overwrite):
                try dumpAssets(
                    format: format,
                    input: input,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    /// Decompiles a single `.scd` script to source text in the requested
    /// language and writes `<name>.<swift|py>` into `outputFolder`. Shared by
    /// the batch (`dumpColoScripts`) and single-file (`dumpColoScript`) ops.
    private static func dumpColoScript(
        scdFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        language: ColoScriptLanguage,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let data = fileSystem.readFile(at: scdFile) else {
            throw FSTErrors.fileNotFound(scdFile, .init())
        }
        let name = scdFile.fileName.withoutExtensions
        let script = try ColoScript(data: data)

        let builtInFunctions = engine.data.scriptBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
        let enums = Dictionary(engine.enums.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let source = ColoScriptSourceEmitter(builtInFunctions: builtInFunctions, enums: enums)
            .decompileToText(script: script, fileName: scdFile.fileName, syntax: language)

        let outFile = outputFolder.file("\(name).\(language.fileExtension)")
        try fileSystem.writeFile(GoDData(byteStream: Array(source.utf8), byteOrder: .big), at: outFile, overwrite: overwrite)
        logger?.log(.info("Decompiled \(scdFile.fileName) -> \(outFile.fileName) (\(language.rawValue))"))
    }

    /// Parses a single `.atx` file and writes its `<name>.atx.json` +
    /// frame PNGs into `outputFolder`. Shared between batch (`dumpATXs`)
    /// and single-file (`dumpATX`) ops.
    private static func dumpATX(
        atxFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let data = fileSystem.readFile(at: atxFile) else {
            throw FSTErrors.fileNotFound(atxFile, .init())
        }
        let name = atxFile.fileName.withoutExtensions
        let parsed: ATXFile
        do {
            parsed = try ATXFile(binary: data, name: name)
        } catch {
            logger?.log(.warning("Failed to parse ATX file: \(atxFile.fileName) — \(error)"))
            return
        }
        try fileSystem.createFolder(at: outputFolder, overwrite: overwrite)
        for artifact in try parsed.outputs {
            try fileSystem.writeFile(artifact.data, at: outputFolder.file(artifact.file.path), overwrite: overwrite)
        }
        logger?.log(.info("  \(name): \(parsed.framePixels.count) frames, \(parsed.animations.count) animations → \(outputFolder.path)"))
    }

    /// Parses an ISH/ISD pair, decodes DSP ADPCM → PCM → WAV, and writes
    /// `<stem>.isf.json` + `<stem>.wav` into `outputFolder`. Shared between
    /// the batch (`dumpAudios`) and single-pair (`dumpAudio`) ops.
    private static func dumpAudio(
        ishFile: File,
        isdFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let ishData = fileSystem.readFile(at: ishFile) else {
            throw FSTErrors.fileNotFound(ishFile, .init())
        }
        guard let isdData = fileSystem.readFile(at: isdFile) else {
            throw FSTErrors.fileNotFound(isdFile, .init())
        }
        let stem = ishFile.fileName.withoutExtensions
        let parsed: ISFFile
        do {
            parsed = try ISFFile(ish: ishData, isd: isdData, name: stem)
        } catch {
            logger?.log(.warning("Failed to parse ISF pair \(ishFile.fileName): \(error)"))
            return
        }
        try fileSystem.createFolder(at: outputFolder, overwrite: overwrite)
        for artifact in try parsed.outputs {
            try fileSystem.writeFile(artifact.data, at: outputFolder.file(artifact.file.path), overwrite: overwrite)
        }
        let loopDesc = parsed.loop.enabled
            ? "loop \(parsed.loop.startSample)-\(parsed.loop.endSample) samples"
            : "no loop"
        logger?.log(.info("  \(stem): \(parsed.sampleRate) Hz, \(parsed.channelCount) ch, \(parsed.sampleCountPerChannel) samples/ch, \(loopDesc) → \(outputFolder.path)"))
    }

    private static func parseMSGVariant(_ value: String) -> MSGFile.Variant {
        switch value.lowercased() {
        case "colo", "colosseum": return .colo
        default: return .xd
        }
    }

    /// Parses a single `.msg` file and writes a `<name>.json` artifact into
    /// `outputFolder`. Shared between batch (`dumpMessages`) and individual
    /// (`dumpMessage`) ops.
    private static func dumpMessage(
        msgFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        variant: MSGFile.Variant,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let data = fileSystem.readFile(at: msgFile) else {
            throw FSTErrors.fileNotFound(msgFile, .init())
        }
        let name = msgFile.fileName.withoutExtensions
        let parsed: MSGFile
        do {
            parsed = try MSGFile(binary: data, variant: variant)
        } catch {
            logger?.log(.warning("Failed to parse message file: \(msgFile.fileName) — \(error)"))
            return
        }
        try fileSystem.createFolder(at: outputFolder, overwrite: overwrite)
        // Use the format's standard naming (<name>.msg.json) so the build
        // op can read it back via ATX-style folder scan if needed.
        var named = parsed
        named.name = name
        for artifact in try named.outputs {
            try fileSystem.writeFile(artifact.data, at: outputFolder.file(artifact.file.path), overwrite: overwrite)
        }
        logger?.log(.info("  \(name): \(parsed.entries.count) entries → \(outputFolder.path)"))
    }
    
    /// Parses a single `.gsw` file and writes a structured project folder
    /// (metadata.json + per-texture PNGs) under `outputFolder`. Shared between
    /// the batch (`dumpFlashMenus`) and individual (`dumpFlashMenu`) ops.
    private static func dumpFlashMenu(
        gswFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let data = fileSystem.readFile(at: gswFile) else {
            throw FSTErrors.fileNotFound(gswFile, .init())
        }
        let name = gswFile.fileName.withoutExtensions
        let parsed: (file: GSWFile, images: [GoDImage])
        do {
            parsed = try GSWParser.parse(data: data, name: name)
        } catch {
            logger?.log(.warning("Failed to parse flash menu: \(gswFile.fileName) — \(error)"))
            return
        }

        try fileSystem.createFolder(at: outputFolder, overwrite: overwrite)
        // Route through FileFormat outputs so filenames follow the
        // project-wide `<name>_texture_NNN.png` convention and nothing
        // needs to know a stored `pngPath` per ref.
        var gsw = parsed.file
        gsw.name = name
        gsw.images = parsed.images
        for artifact in try gsw.outputs {
            try fileSystem.writeFile(artifact.data, at: outputFolder.file(artifact.file.path), overwrite: overwrite)
        }
        logger?.log(.info("  \(name): \(gsw.tags.count) tags, \(gsw.allTextureRefs.count) textures → \(outputFolder.path)"))
    }

    



    /// Resolves a relative path string (e.g. `./textures/foo.png`) against
    /// `base`, normalizing leading `.`/`..` components. Used for paths stored
    /// inside metadata JSONs (GSW `pngPath`, font `atlasPath`, etc.).
    static func resolveRelativeFile(_ relativePath: String, in base: Folder) -> File {
        guard let lastSlash = relativePath.lastIndex(of: "/") else {
            return base.file(relativePath)
        }
        let dir = String(relativePath[..<lastSlash])
        let name = String(relativePath[relativePath.index(after: lastSlash)...])
        return base.folder(dir).file(name)
    }
}
