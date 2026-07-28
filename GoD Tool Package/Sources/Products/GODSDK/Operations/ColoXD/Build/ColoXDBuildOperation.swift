import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import GTX
import Colosseum
import ScriptDecompiler

extension ColoXD {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildColosseum(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try gsEngine.packProject(
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildXD(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try gsEngine.packProject(
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildGSfsysTOC(fstRegistryFile, outputFile, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let sourceFolder = fstRegistryFile.parentFolder else {
                    throw FSTErrors.fileNotFound(fstRegistryFile, .init())
                }

                logger?.log(.info("Building GSfsys.toc from FSTRegistry"))
                let tocData = try gsEngine.buildGSfsysTOC(
                    fstRegistryFile: fstRegistryFile,
                    sourceFolder: sourceFolder,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(tocData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(tocData.length) bytes)"))
                }

            case let .buildFST(contentsFolder, outputFile, overwrite, dolphinEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)

                logger?.log(.info("Building fst.bin from \(contentsFolder.path)"))
                let fst = DolphinFST(fileSystem: fileSystem, root: contentsFolder)
                let fstData = try fst.tocData(userOffset: 0, dolphinEngine: dolphinEngine)

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(fstData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(fstData.length) bytes, \(fst.files.count) files)"))
                }

            case let .packFSYS(registryFile, outputFile, sourceFolder, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                logger?.log(.info("Packing FSYS archive from \(registryFile.fileName) entries)"))

                let archiveData = try gsEngine.packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(archiveData.data, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(archiveData.data.length) bytes)"))
                }

            case let .buildAssets(format, input, outputFolder, overwrite):
                try buildAssets(
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

    /// Compiles a single decompiled script source file (`.swift` or `.py` —
    /// the parser auto-detects the dialect) back to a `.scd` binary. Shared by
    /// the batch (`buildColoScripts`) and single-file (`buildColoScript`) ops.
    private static func buildColoScript(
        sourceFile: File,
        outputFile: File,
        overwrite: Bool,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let data = fileSystem.readFile(at: sourceFile) else {
            throw FSTErrors.fileNotFound(sourceFile, .init())
        }
        let source = data.string(format: .utf8)

        let builtInFunctions = engine.data.scriptBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }

        var parser = ColoScriptTextParser(builtInFunctions: builtInFunctions)
        let parsed = try parser.parse(source)
        let binary = try ColoScriptCompiler().compile(parsed)

        try fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("Compiled \(sourceFile.fileName) -> \(outputFile.fileName)"))
    }

    private static func buildMessage(
        jsonFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let json = fileSystem.readFile(at: jsonFile) else {
            throw FSTErrors.fileNotFound(jsonFile, .init())
        }
        // The MSG init(outputs:) needs a key matching `*.msg.json`. We don't
        // know the source filename here, so use a generic key — the format
        // recovers any stem (or empty) from the suffix match.
        let stem = jsonFile.fileName.withoutExtensions
        let file = try MSGFile(outputs: [FileData(file: File("\(stem).msg.json"), data: json)])
        let binary = try file.binaryData
        try fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(jsonFile.fileName): \(file.entries.count) entries → \(outputFile.fileName)"))
    }

    /// Reads the ATX manifest JSON and the sibling frame PNGs it references,
    /// feeds them through `ATXFile.init(outputs:)`, and writes the rebuilt
    /// `.atx` binary. Only files named in the manifest's `framePaths` list
    /// are read — no folder-wide scan — so the JSON is the single entry
    /// point.
    private static func buildATX(
        metadataFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let jsonData = fileSystem.readFile(at: metadataFile),
              let baseFolder = metadataFile.parentFolder else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }
        var outputs: [FileData] = [
            // Feed the JSON into ATXFile using just its filename so
            // `init(outputs:)` recovers the correct `<stem>` from the key.
            FileData(file: File(metadataFile.fileName), data: jsonData)
        ]

        // Peek at the DTO purely to discover the declared frame paths.
        // Older manifests without `framePaths` fall back to a folder scan
        // of PNGs matching `<stem>_frame_NNN.png`.
        struct FramePathsOnly: Codable { let framePaths: [String]? }
        let peek = (try? JSONDecoder().decode(FramePathsOnly.self, from: jsonData.data))
        let framePaths: [String]
        if let declared = peek?.framePaths, !declared.isEmpty {
            framePaths = declared
        } else {
            let stem = metadataFile.fileName
                .replacingOccurrences(of: ".atx.json", with: "")
            let framePrefix = "\(stem)_frame_"
            framePaths = (fileSystem.inspectFolder(at: baseFolder)?.files ?? [])
                .map(\.fileName)
                .filter { $0.hasPrefix(framePrefix) && $0.hasSuffix(".png") }
                .sorted()
        }

        for relative in framePaths {
            let file = ColoXD.resolveRelativeFile(relative, in: baseFolder)
            guard let data = fileSystem.readFile(at: file) else {
                throw FSTErrors.fileNotFound(file, .init())
            }
            outputs.append(FileData(file: File(relative), data: data))
        }

        let atx = try ATXFile(outputs: outputs)
        let binary = try atx.binaryData
        try fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(atx.name): \(atx.framePixels.count) frames → \(outputFile.fileName)"))
    }

    /// Reads an ISF manifest JSON, resolves the sibling `.wav` it points
    /// at, re-encodes DSP ADPCM, and writes paired `.ish` + `.isd` files.
    /// The JSON is the single entry point — no folder scan.
    private static func buildAudio(
        metadataFile: File,
        ishOutputFile: File,
        isdOutputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let jsonData = fileSystem.readFile(at: metadataFile),
              let baseFolder = metadataFile.parentFolder else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }
        // Peek at the manifest just to find the wavPath; full parsing
        // happens inside ISFFile.init(outputs:).
        struct WavPathOnly: Codable { let wavPath: String }
        let peek = try JSONDecoder().decode(WavPathOnly.self, from: jsonData.data)
        let wavFile = ColoXD.resolveRelativeFile(peek.wavPath, in: baseFolder)
        guard let wavData = fileSystem.readFile(at: wavFile) else {
            throw FSTErrors.fileNotFound(wavFile, .init())
        }

        let outputs: [FileData] = [
            FileData(file: File(metadataFile.fileName), data: jsonData),
            FileData(file: File(peek.wavPath), data: wavData)
        ]
        let isf = try ISFFile(outputs: outputs)
        let (ish, isd) = try isf.ishISDBytes()
        if overwrite || fileSystem.inspectFile(at: ishOutputFile) == nil {
            try fileSystem.writeFile(ish, at: ishOutputFile, overwrite: overwrite)
        }
        if overwrite || fileSystem.inspectFile(at: isdOutputFile) == nil {
            try fileSystem.writeFile(isd, at: isdOutputFile, overwrite: overwrite)
        }
        logger?.log(.info("Built ISF \(ishOutputFile.fileName)/\(isdOutputFile.fileName) (\(isf.sampleRate) Hz, \(isf.channelCount) ch, \(ish.length + isd.length) bytes)"))
    }

    // MARK: - GSfsys.toc building


    // MARK: - Flash menu (GSW) building

    /// Reads a structured flash-menu project folder (metadata.json + textures/)
    /// and writes a rebuilt `.gsw` to `outputFile`. Shared between the batch
    /// (`buildFlashMenus`) and individual (`buildFlashMenu`) ops.
    private static func buildFlashMenu(
        metadataFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let jsonData = fileSystem.readFile(at: metadataFile),
              let baseFolder = metadataFile.parentFolder else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }

        // Preflight the JSON to discover the sibling PNG paths the GSW
        // declares. Only those files are read — the JSON is the single
        // entry point.
        struct TextureRefPath: Codable { let pngPath: String? }
        struct TagTextures: Codable { let textures: [TextureRefPath] }
        struct GSWManifestPeek: Codable { let tags: [TagTextures] }
        let peek = try? JSONDecoder().decode(GSWManifestPeek.self, from: jsonData.data)
        let declaredPaths = (peek?.tags ?? [])
            .flatMap(\.textures)
            .compactMap(\.pngPath)

        var outputs: [FileData] = [
            FileData(file: File(metadataFile.fileName), data: jsonData)
        ]

        if !declaredPaths.isEmpty {
            for relative in declaredPaths {
                let file = ColoXD.resolveRelativeFile(relative, in: baseFolder)
                guard let data = fileSystem.readFile(at: file) else {
                    throw FSTErrors.fileNotFound(file, .init())
                }
                outputs.append(FileData(file: File(relative), data: data))
            }
        } else {
            // Legacy dumps without stamped texture paths — scan the folder
            // for PNG siblings. Leave it permissive so existing projects
            // keep building.
            if let meta = fileSystem.inspectFolder(at: baseFolder) {
                for f in meta.files where f.fileName != metadataFile.fileName {
                    if let data = fileSystem.readFile(at: f) {
                        outputs.append(FileData(file: File(f.fileName), data: data))
                    }
                }
            }
        }

        let gsw = try GSWFile(outputs: outputs)
        let gswData = try gsw.binaryData
        if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
            try fileSystem.writeFile(gswData, at: outputFile, overwrite: overwrite)
            logger?.log(.info("Built flash menu \(outputFile.fileName) (\(gsw.tags.count) tags, \(gsw.allTextureRefs.count) textures, \(gswData.length) bytes)"))
        }
    }

    // MARK: - Font (FNT) building

    /// Reads a dumped font project (a `<name>.json` metadata file whose
    /// `atlasPath` field points at the paired `.pgm` atlas in the same folder)
    /// and writes a rebuilt `.fnt` to `outputFile`. The atlas location is
    /// resolved from the metadata rather than a separate config field.
    private static func buildFont(
        metadataFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard fileSystem.inspectFile(at: metadataFile) != nil else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }
        let metadata: GSFontAtlas.Metadata = try fileSystem.decodeJSON(from: metadataFile)

        // Resolve atlas path relative to the metadata file's directory.
        guard let baseFolder = metadataFile.parentFolder else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }
        let atlasFile = baseFolder.file(metadata.atlasPath)
        guard let imageData = fileSystem.readFile(at: atlasFile) else {
            throw FSTErrors.fileNotFound(atlasFile, .init())
        }

        let font = try GSFontAtlas.importAtlas(imageData: imageData, metadata: metadata)
        let fontData = try font.data

        if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
            try fileSystem.writeFile(fontData, at: outputFile, overwrite: overwrite)
            logger?.log(.info("Built font \(outputFile.fileName) (\(font.visibleGlyphs.count) glyphs, \(fontData.length) bytes)"))
        }
    }

    // MARK: - Core FSYS packing



    // MARK: - Build all FSYS archives from an unpacked project

}
