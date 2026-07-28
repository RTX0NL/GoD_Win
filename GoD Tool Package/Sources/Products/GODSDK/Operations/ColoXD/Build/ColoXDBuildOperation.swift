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

                try buildColosseumXD(
                    fileSystem: fileSystem,
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    dolphinEngine: dolphinEngine,
                    gsEngine: gsEngine,
                    logger: logger
                )

            case let .buildXD(fstRegistry, outputFolder, overwrite, dolphinPath, gsEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                try buildColosseumXD(
                    fileSystem: fileSystem,
                    fstRegistryFile: fstRegistry,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    dolphinEngine: dolphinEngine,
                    gsEngine: gsEngine,
                    logger: logger
                )

            case let .buildGSfsysTOC(fstRegistryFile, outputFile, overwrite, gsEnginePath):
                let gsEngine = try GeniusSonorityEngine(from: gsEnginePath, in: fileSystem)

                guard let sourceFolder = fstRegistryFile.parentFolder else {
                    throw FSTErrors.fileNotFound(fstRegistryFile, .init())
                }

                logger?.log(.info("Building GSfsys.toc from FSTRegistry"))
                let tocData = try buildGSfsysTOC(
                    fstRegistryFile: fstRegistryFile,
                    sourceFolder: sourceFolder,
                    gsEngine: gsEngine,
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

                let archiveData = try packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    gsEngine: gsEngine,
                    fileSystem: fileSystem
                )

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(archiveData.data, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(archiveData.data.length) bytes)"))
                }

            case let .buildFont(metadataFile, outputFile, overwrite):
                try buildFont(
                    metadataFile: metadataFile,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildFonts(fontsFolder, outputFolder, overwrite):
                guard let contents = fileSystem.inspectFolder(at: fontsFolder) else { break }
                let metadataFiles = contents.files.filter { $0.fileType == "json" }
                logger?.log(.info("Found \(metadataFiles.count) font metadata files"))
                for metadataFile in metadataFiles {
                    let fontName = metadataFile.fileName.replacingOccurrences(of: ".json", with: "")
                    let outputFile = outputFolder.file("\(fontName).fnt")
                    try buildFont(
                        metadataFile: metadataFile,
                        outputFile: outputFile,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildFlashMenus(projectsFolder, outputFolder, overwrite):
                // Recurse so language subfolders (French/, German/, etc.) are
                // preserved on output. A project is any folder containing a
                // `<folderName>.json` metadata file; non-project folders
                // (e.g. an enclosing `German/`) are descended into.
                var projects = [(folder: Folder, relative: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    if fileSystem.inspectFile(at: folder.file(folder.folderName + ".json")) != nil {
                        projects.append((folder, relative))
                        return
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                if let contents = fileSystem.inspectFolder(at: projectsFolder) {
                    for sub in contents.subFolders {
                        collect(sub, Folder(".").folder(sub.folderName))
                    }
                }

                logger?.log(.info("Found \(projects.count) flash menu projects"))
                for (project, relative) in projects {
                    let metadataFile = project.file(project.folderName + ".json")
                    // relative includes the project folder itself; strip it
                    // so the output sits beside it (mirroring the input layout).
                    let parentRelative = relative.folder("..")
                    let outputFile = outputFolder.folder(parentRelative.path).file(project.folderName + ".gsw")
                    try buildFlashMenu(
                        metadataFile: metadataFile,
                        outputFile: outputFile,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildFlashMenu(metadataFile, outputFile, overwrite):
                try buildFlashMenu(
                    metadataFile: metadataFile,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildMessages(jsonFolder, outputFolder, overwrite):
                var jsonFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "json" {
                        jsonFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(jsonFolder, Folder("."))
                logger?.log(.info("Found \(jsonFiles.count) message JSON files"))

                for (jsonFile, relative) in jsonFiles {
                    let name = jsonFile.fileName.withoutExtensions
                    let outputFile = outputFolder.folder(relative.path).file("\(name).msg")
                    try buildMessage(
                        jsonFile: jsonFile,
                        outputFile: outputFile,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildMessage(jsonFile, outputFile, overwrite):
                try buildMessage(
                    jsonFile: jsonFile,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildATXs(jsonFolder, outputFolder, overwrite):
                // Each ATX is driven by its `<name>.atx.json` manifest which
                // declares its frame PNG siblings. Recurse so nested layouts
                // (e.g. poke_dance/<name>/<name>.atx.json) still get picked
                // up without the build op needing to know about them.
                var manifests = [File]()
                func collect(_ folder: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileName.hasSuffix(".atx.json") {
                        manifests.append(file)
                    }
                    for sub in contents.subFolders { collect(sub) }
                }
                collect(jsonFolder)
                logger?.log(.info("Building \(manifests.count) ATX manifests"))
                for manifest in manifests {
                    let stem = manifest.fileName
                        .replacingOccurrences(of: ".atx.json", with: "")
                    let outputFile = outputFolder.file("\(stem).atx")
                    try buildATX(
                        metadataFile: manifest,
                        outputFile: outputFile,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildATX(metadataFile, outputFile, overwrite):
                try buildATX(
                    metadataFile: metadataFile,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildAudios(jsonFolder, outputFolder, overwrite):
                // Each audio pair is driven by its `<name>.isf.json`
                // manifest which references the sibling `.wav`. Output
                // filenames (`.ish` + `.isd`) are stem-derived.
                var manifests = [File]()
                func collect(_ folder: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileName.hasSuffix(".isf.json") {
                        manifests.append(file)
                    }
                    for sub in contents.subFolders { collect(sub) }
                }
                collect(jsonFolder)
                logger?.log(.info("Building \(manifests.count) ISF audio manifests"))
                for manifest in manifests {
                    let stem = manifest.fileName
                        .replacingOccurrences(of: ".isf.json", with: "")
                    try buildAudio(
                        metadataFile: manifest,
                        ishOutputFile: outputFolder.file("\(stem).ish"),
                        isdOutputFile: outputFolder.file("\(stem).isd"),
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildAudio(metadataFile, ishOutputFile, isdOutputFile, overwrite):
                try buildAudio(
                    metadataFile: metadataFile,
                    ishOutputFile: ishOutputFile,
                    isdOutputFile: isdOutputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .buildColoScripts(sourceFolder, outputFolder, overwrite, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                var sourceFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "swift" || file.fileType == "py" {
                        sourceFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(sourceFolder, Folder("."))
                logger?.log(.info("Found \(sourceFiles.count) Colosseum script source files"))

                for (sourceFile, relative) in sourceFiles {
                    let name = sourceFile.fileName.withoutExtensions
                    try buildColoScript(
                        sourceFile: sourceFile,
                        outputFile: outputFolder.folder(relative.path).file("\(name).scd"),
                        overwrite: overwrite,
                        engine: engine,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildColoScript(sourceFile, outputFile, overwrite, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                try buildColoScript(
                    sourceFile: sourceFile,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    engine: engine,
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

    /// Builds GSfsys.toc from the FSYS entries in an FSTRegistry.
    /// Reads each FSYSRegistry JSON to get the groupID, then serializes a FsysTOC.
    private static func buildGSfsysTOC(
        fstRegistryFile: File,
        sourceFolder: Folder,
        gsEngine: GeniusSonorityEngine,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        let fstRegistry: FSTRegistry = try fileSystem.decodeJSON(from: fstRegistryFile)
        var fsysIDsByFilename = [String: Int]()

        for entry in fstRegistry.entries where entry.type == .fsys {
            let registryPath = sourceFolder.file(entry.file.path)
            let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryPath)
            // Registry filename is e.g. "D1_out.fsys.json" → FSYS name is "D1_out"
            // Only include archives with a valid groupID (non-zero) in the TOC
            guard registry.groupID != 0 else { continue }
            let fsysName = registryPath.fileName.withoutExtensions
            fsysIDsByFilename[fsysName] = registry.groupID
        }

        let toc = FsysTOC(fsysIDsByFilename: fsysIDsByFilename, unknown: gsEngine.data.toc.unknown)
        toc.padding = gsEngine.data.toc.padding
        toc.junk1 = gsEngine.data.toc.junk1
        toc.junk2 = gsEngine.data.toc.junk2
        toc.junk3 = gsEngine.data.toc.junk3
        return try toc.tocData(with: gsEngine)
    }

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

    /// Resolves one `FSYSRegistry.Entry` to the list of archive entries
    /// it expands to. Most registry entries map 1:1 to an archive entry;
    /// THP-pair entries expand into the two THH + THD entries the
    /// archive originally held.
    private static func resolveArchiveEntries(
        registryEntry: FSYSRegistry.Entry,
        sourceFolder: Folder,
        fileSystem: FileSystemTree
    ) throws -> [FSYSArchive.Entry] {
        let filePath = sourceFolder.file(registryEntry.file.path)
        guard let data = fileSystem.readFile(at: filePath) else {
            throw FSTErrors.fileNotFound(filePath, .init())
        }

        // THP pair: split the combined `.thp` back into THH + THD and
        // emit two FSYS entries with the preserved metadata pair.
        if let thdMetadata = registryEntry.thdMetadata {
            let thp = try THPFile(outputs: [
                FileData(file: registryEntry.file, data: data)
            ])
            let (thh, thd) = try thp.splitCombined()
            return [
                FSYSArchive.Entry(
                    metadata: registryEntry.metadata,
                    filename: registryEntry.metadata.name + "." + registryEntry.metadata.fileType,
                    data: thh
                ),
                FSYSArchive.Entry(
                    metadata: thdMetadata,
                    filename: thdMetadata.name + "." + thdMetadata.fileType,
                    data: thd
                )
            ]
        }

        // Re-encode PNG back to GTX/ATX if texture metadata is present.
        var entryData = data
        if filePath.fileType == "png" {
            let decoder = GXTextureDecoder()
            if let atxMeta = registryEntry.atxMetadata {
                if let image = GoDImage.fromPNG(data),
                   let atxData = decoder.encodeATX(image: image, metadata: atxMeta) {
                    entryData = atxData
                }
            } else if let texMeta = registryEntry.textureMetadata {
                if let image = GoDImage.fromPNG(data),
                   let gtxData = decoder.encode(image: image, metadata: texMeta) {
                    entryData = gtxData
                }
            }
        }
        let filename = registryEntry.metadata.name + "." + registryEntry.metadata.fileType
        return [
            FSYSArchive.Entry(
                metadata: registryEntry.metadata,
                filename: filename,
                data: entryData
            )
        ]
    }

    /// Reads a registry JSON and its entry files from the filesystem,
    /// packs into an FSYS archive. Pure function safe for concurrent use.
    private static func packFSYSFromRegistry(
        registryFile: File,
        sourceFolder: Folder,
        discPath: String? = nil,
        gsEngine: GeniusSonorityEngine,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryFile)

        var archiveEntries: [FSYSArchive.Entry] = []
        for registryEntry in registry.entries {
            archiveEntries.append(contentsOf: try resolveArchiveEntries(
                registryEntry: registryEntry,
                sourceFolder: sourceFolder,
                fileSystem: fileSystem
            ))
        }

        let archive = FSYSArchive(metadata: registry.metaData, entries: archiveEntries)
        // `discPath` is the archive's original location relative to `files/`;
        // fall back to the registry-derived filename for callers (and older
        // registries) that don't carry one.
        let outputPath = discPath ?? registryFile.fileName.withoutExtension
        return FileData(
            file: File(outputPath),
            data: try archive.data(groupID: registry.groupID, engine: gsEngine)
        )
    }

    // MARK: - Build all FSYS archives from an unpacked project

    private static func buildColosseumXD(
        fileSystem: FileSystemTree,
        fstRegistryFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        logger: Logger? = nil
    ) throws {
        guard let sourceFolder = fstRegistryFile.parentFolder else {
            throw FSTErrors.fileNotFound(fstRegistryFile, .init())
        }
        let fstRegistry: FSTRegistry = try fileSystem.decodeJSON(from: fstRegistryFile)

        logger?.log(.info("Building Colosseum/XD File System"))
        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .started))

        let fsysEntries = fstRegistry.entries.filter { $0.type == .fsys }
        let binaryEntries = fstRegistry.entries.filter { $0.type == .binary }
        let totalCount = fsysEntries.count + binaryEntries.count

        // Phase 1: Copy non-FSYS binary files to output
        for (i, entry) in binaryEntries.enumerated() {
            let sourcePath = sourceFolder.file(entry.file.path)
            guard let data = fileSystem.readFile(at: sourcePath) else {
                throw FSTErrors.fileNotFound(sourcePath, .init())
            }
            // `rebuildPath` is the file's original location relative to
            // `files/`, so subdirectories on the disc are reproduced rather
            // than flattened into one folder (which also collided whenever
            // two directories held the same filename).
            let outputFile = outputFolder.folder("files").file(entry.rebuildPath)
            if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                try fileSystem.writeFile(data, at: outputFile, overwrite: overwrite)
            }

            let percent = Int(Double(i + 1) / Double(totalCount) * 100)
            if percent > 0 {
                logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
            }
        }

        // Phase 2: Pack FSYS archives concurrently.
        //
        // Results go through an unsafe buffer pointer, not `array[i] = …`:
        // subscripting an Array from several threads races even with one
        // distinct index per thread, because the setter first runs
        // `_makeMutableAndUnique()` on the shared array struct. See the
        // matching note in `ColoXDDumpOperation`.
        //
        // Every worker only *reads* `fileSystem` here; `FileSystemTree` is
        // documented as safe for concurrent reads but not for any write, so
        // nothing in this loop may mutate the tree.
        var fsysResults = [Result<FileData, Error>?](repeating: nil, count: fsysEntries.count)
        let progressLock = NSLock()
        var fsysProcessed = 0
        var lastReportedPercent = Int(Double(binaryEntries.count) / Double(totalCount) * 100)

        fsysResults.withUnsafeMutableBufferPointer { results in
            DispatchQueue.concurrentPerform(iterations: fsysEntries.count) { i in
                let entry = fsysEntries[i]
                let registryFile = sourceFolder.file(entry.file.path)

                do {
                    results[i] = .success(try packFSYSFromRegistry(
                        registryFile: registryFile,
                        sourceFolder: sourceFolder,
                        discPath: entry.rebuildPath,
                        gsEngine: gsEngine,
                        fileSystem: fileSystem
                    ))
                } catch {
                    results[i] = .failure(error)
                }

                if let logger {
                    progressLock.lock()
                    fsysProcessed += 1
                    let processed = binaryEntries.count + fsysProcessed
                    let percent = Int(min(Double(processed) / Double(totalCount) * 100, 100))
                    if percent > lastReportedPercent {
                        lastReportedPercent = percent
                        logger.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
                    }
                    progressLock.unlock()
                }
            }
        }

        // Write packed archives to output
        for result in fsysResults {
            guard let result else { continue }
            switch result {
            case .success(let packed):
                let outputFile = outputFolder.folder("files").file(packed.file.path)
                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(packed.data, at: outputFile, overwrite: overwrite)
                }
            case .failure(let error):
                throw error
            }
        }

        // Phase 3: Rebuild GSfsys.toc from FSYS registries
        logger?.log(.info("Rebuilding GSfsys.toc"))
        let tocData = try buildGSfsysTOC(
            fstRegistryFile: fstRegistryFile,
            sourceFolder: sourceFolder,
            gsEngine: gsEngine,
            fileSystem: fileSystem
        )
        let tocOutputFile = outputFolder.file("files/" + gsEngine.data.fsys.GSfsysFile.fileName)
        try fileSystem.writeFile(tocData, at: tocOutputFile, overwrite: true)
        logger?.log(.info("Wrote \(tocOutputFile.fileName) (\(tocData.length) bytes)"))

        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .completed(true)))
    }
}
