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
                
                let output = try dumpColosseum(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)
            case let .dumpXD(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)

                let output = try dumpXD(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings,
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

            case let .dumpFonts(fontsFolder, outputFolder, overwrite):
                // Find all .fnt files in the fonts folder
                guard let contents = fileSystem.inspectFolder(at: fontsFolder) else { break }
                let fntFiles = contents.files.filter { $0.fileType == "fnt" }
                logger?.log(.info("Found \(fntFiles.count) font files"))

                for fntFile in fntFiles {
                    guard let data = fileSystem.readFile(at: fntFile) else { continue }
                    guard let font = try? GSFont(data: data) else {
                        logger?.log(.warning("Failed to parse font: \(fntFile.fileName)"))
                        continue
                    }

                    let fontName = fntFile.fileName.replacingOccurrences(of: ".fnt", with: "")
                    let atlasFileName = "\(fontName)_atlas.pgm"
                    let atlasFile = outputFolder.file(atlasFileName)
                    let metadataFile = outputFolder.file("\(fontName).json")

                    let (imageData, metadata) = GSFontAtlas.exportAtlas(
                        font: font,
                        atlasPath: atlasFileName
                    )

                    if overwrite || fileSystem.inspectFile(at: atlasFile) == nil {
                        try fileSystem.writeFile(imageData, at: atlasFile, overwrite: overwrite)
                    }
                    try fileSystem.encodeJSON(metadata, to: metadataFile, overwrite: overwrite)

                    logger?.log(.info("  \(fontName): \(font.visibleGlyphs.count) glyphs → \(metadataFile.fileName)"))
                }

            case let .dumpFlashMenus(flashMenusFolder, outputFolder, overwrite):
                // Recurse so language subfolders (French/, German/, etc.) are
                // preserved under the output, e.g.
                //   Flash Menus/German/disk_vs_00.gsw
                //   → Source/Menus/German/disk_vs_00/disk_vs_00.json
                var gswFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "gsw" {
                        gswFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(flashMenusFolder, Folder("."))

                logger?.log(.info("Found \(gswFiles.count) flash menu files"))

                for (gswFile, relative) in gswFiles {
                    let name = gswFile.fileName.withoutExtensions
                    let projectFolder = outputFolder.folder(relative.path).folder(name)
                    try dumpFlashMenu(
                        gswFile: gswFile,
                        outputFolder: projectFolder,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .dumpFlashMenu(gswFile, outputFolder, overwrite):
                try dumpFlashMenu(
                    gswFile: gswFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .dumpMessages(messagesFolder, outputFolder, overwrite, variant):
                var msgFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "msg" {
                        msgFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(messagesFolder, Folder("."))
                logger?.log(.info("Found \(msgFiles.count) message files"))

                let msgVariant = parseMSGVariant(variant)
                for (msgFile, relative) in msgFiles {
                    let targetFolder = outputFolder.folder(relative.path)
                    try dumpMessage(
                        msgFile: msgFile,
                        outputFolder: targetFolder,
                        overwrite: overwrite,
                        variant: msgVariant,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .dumpMessage(msgFile, outputFolder, overwrite, variant):
                try dumpMessage(
                    msgFile: msgFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    variant: parseMSGVariant(variant),
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .dumpATXs(atxFolder, outputFolder, overwrite):
                var atxFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "atx" {
                        atxFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(atxFolder, Folder("."))
                logger?.log(.info("Found \(atxFiles.count) ATX files"))

                for (atxFile, relative) in atxFiles {
                    let name = atxFile.fileName.withoutExtensions
                    let projectFolder = outputFolder.folder(relative.path).folder(name)
                    try dumpATX(
                        atxFile: atxFile,
                        outputFolder: projectFolder,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .dumpATX(atxFile, outputFolder, overwrite):
                // Single-file variant also creates a per-ATX subfolder under
                // `outputFolder` to keep the layout consistent with the batch
                // op and avoid collisions when the same output folder is
                // reused across files.
                let name = atxFile.fileName.withoutExtensions
                let projectFolder = outputFolder.folder(name)
                try dumpATX(
                    atxFile: atxFile,
                    outputFolder: projectFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .dumpAudios(audioFolder, outputFolder, overwrite):
                // ISH/ISD come in pairs sharing a stem. Scan `audioFolder`
                // (recursively) for .ish files, then locate the matching
                // .isd sibling in the same folder.
                var ishFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "ish" {
                        ishFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(audioFolder, Folder("."))
                logger?.log(.info("Found \(ishFiles.count) ISH/ISD audio pairs"))

                for (ishFile, relative) in ishFiles {
                    let stem = ishFile.fileName.withoutExtensions
                    guard let parent = ishFile.parentFolder else { continue }
                    let isdFile = parent.file("\(stem).isd")
                    guard fileSystem.inspectFile(at: isdFile) != nil else {
                        logger?.log(.warning("Missing ISD sibling for \(ishFile.fileName); skipping"))
                        continue
                    }
                    let projectFolder = outputFolder.folder(relative.path)
                    try dumpAudio(
                        ishFile: ishFile,
                        isdFile: isdFile,
                        outputFolder: projectFolder,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .dumpAudio(ishFile, isdFile, outputFolder, overwrite):
                try dumpAudio(
                    ishFile: ishFile,
                    isdFile: isdFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )

            case let .dumpColoScripts(scriptsFolder, outputFolder, overwrite, language, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                var scriptFiles = [(file: File, relativeFolder: Folder)]()
                func collect(_ folder: Folder, _ relative: Folder) {
                    guard let contents = fileSystem.inspectFolder(at: folder) else { return }
                    for file in contents.files where file.fileType == "scd" {
                        scriptFiles.append((file, relative))
                    }
                    for sub in contents.subFolders {
                        collect(sub, relative.folder(sub.folderName))
                    }
                }
                collect(scriptsFolder, Folder("."))
                logger?.log(.info("Found \(scriptFiles.count) Colosseum script files"))

                for (scdFile, relative) in scriptFiles {
                    try dumpColoScript(
                        scdFile: scdFile,
                        outputFolder: outputFolder.folder(relative.path),
                        overwrite: overwrite,
                        language: language,
                        engine: engine,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .dumpColoScript(scdFile, outputFolder, overwrite, language, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                try dumpColoScript(
                    scdFile: scdFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    language: language,
                    engine: engine,
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
    
    private static func dumpColosseum(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings,
            logger: logger
        )
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

    private static func dumpXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings,
            logger: logger
        )
    }
    
    /// Result of processing a single FSYS archive
    private struct FsysResult {
        let registry: FSYSRegistry
        let registryFile: File
        /// The archive's path relative to the disc's `files/` folder, so the
        /// rebuild can put it back where it came from.
        let discPath: String
        let extractedFiles: [(file: File, data: GoDData)]
    }

    /// Processes a single FSYS archive (parsing + LZSS decompression).
    /// Pure function with no side effects — safe to call from any thread.
    private static func processFsys(
        data: GoDData,
        fileName: String,
        discPath: String,
        toc: FsysTOC,
        gsEngine: GeniusSonorityEngine
    ) throws -> FsysResult {
        let archive = try FSYSArchive(data: data, engine: gsEngine)
        let archiveName = fileName.withoutExtensions
        let groupID = archive.groupID != 0 ? archive.groupID : (toc.fsysID(for: archiveName) ?? 0)

        var entries = [FSYSRegistry.Entry]()
        var extractedFiles = [(file: File, data: GoDData)]()

        let textureDecoder = GXTextureDecoder()

        // Pre-pass: pair THH + THD entries by stem. Each pair is
        // collapsed into a single combined `.thp` artifact; the
        // registry keeps both FSYS metadata blocks so pack can emit
        // two entries again. Orphan THH or THD (without a partner in
        // the same archive) fall through to the normal extraction
        // path and stay as-is.
        var thdByStem: [String: FSYSArchive.Entry] = [:]
        for entry in archive.entries where entry.metadata.fileType == "thd" {
            thdByStem[entry.metadata.name] = entry
        }
        var thhStemsPaired = Set<String>()
        var thdStemsPaired = Set<String>()
        for entry in archive.entries
        where entry.metadata.fileType == "thh" && thdByStem[entry.metadata.name] != nil {
            thhStemsPaired.insert(entry.metadata.name)
            thdStemsPaired.insert(entry.metadata.name)
        }

        for entry in archive.entries {
            let targetFolder = gsEngine.resolveFolder(
                forFileType: entry.metadata.fileType,
                entryFilename: entry.filename,
                archiveName: archiveName
            ).resolvedFolder

            let fileType = entry.metadata.fileType

            // THH half of a paired video — combine with its THD sibling
            // and emit a single `.thp`.
            if fileType == "thh" && thhStemsPaired.contains(entry.metadata.name),
               let thd = thdByStem[entry.metadata.name] {
                let thpName = entry.metadata.name + ".thp"
                let thpFile = targetFolder.file(thpName)
                do {
                    let thp = try THPFile(thh: entry.data, thd: thd.data, name: entry.metadata.name)
                    entries.append(.init(
                        metadata: entry.metadata,
                        file: thpFile,
                        thdMetadata: thd.metadata
                    ))
                    extractedFiles.append((file: thpFile, data: thp.combined))
                } catch {
                    // Fall back to extracting the THH raw if pairing failed.
                    let targetFile = targetFolder.file(entry.filename)
                    entries.append(.init(metadata: entry.metadata, file: targetFile))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
                continue
            }
            // THD half of a paired video — already emitted via its THH.
            if fileType == "thd" && thdStemsPaired.contains(entry.metadata.name) {
                continue
            }

            if fileType == "gtx" {
                let texMeta = textureDecoder.parseHeader(data: entry.data)
                if let image = textureDecoder.decode(data: entry.data),
                   let pngData = image.pngData() {
                    let pngFile = targetFolder.file(entry.filename.withoutExtensions + ".png")
                    entries.append(.init(metadata: entry.metadata, file: pngFile, textureMetadata: texMeta))
                    extractedFiles.append((file: pngFile, data: pngData))
                } else {
                    let targetFile = targetFolder.file(entry.filename)
                    entries.append(.init(metadata: entry.metadata, file: targetFile, textureMetadata: texMeta))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
            } else if fileType == "atx" {
                if let (image, atxMeta) = textureDecoder.decodeATX(data: entry.data),
                   let pngData = image.pngData() {
                    let pngFile = targetFolder.file(entry.filename.withoutExtensions + ".png")
                    entries.append(.init(metadata: entry.metadata, file: pngFile, atxMetadata: atxMeta))
                    extractedFiles.append((file: pngFile, data: pngData))
                } else {
                    let targetFile = targetFolder.file(entry.filename)
                    entries.append(.init(metadata: entry.metadata, file: targetFile))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
            } else {
                let targetFile = targetFolder.file(entry.filename)
                entries.append(.init(metadata: entry.metadata, file: targetFile))
                extractedFiles.append((file: targetFile, data: entry.data))
            }
        }

        let registry = FSYSRegistry(
            groupID: groupID,
            metaData: archive.metaData,
            entries: entries
        )
        let registryFile = gsEngine.data.fsys.archivesFolder.file(fileName + ".json")

        return FsysResult(
            registry: registry,
            registryFile: registryFile,
            discPath: discPath,
            extractedFiles: extractedFiles
        )
    }

    private static func dumpColosseumXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings,
        logger: Logger? = nil
    ) throws -> FileSystemTree {

        let projectFileSystem = InMemoryFST()

        // Folders are created on-demand when files are written,
        // avoiding empty directories for unused file types.
        let fsysConfig = gsEngine.data.fsys

        let gsfsysFile = rootFolder.file(gsEngine.data.fsys.GSfsysFile.path)
        guard let gsfsysData = fileSystem.readFile(at: gsfsysFile) else {
            throw ColoXDDumpErrors.missingToC(file: gsfsysFile, .init())
        }
        let toc = try FsysTOC(tocData: gsfsysData, engine: gsEngine)

        logger?.log(.info("Decoding Colosseum/XD File System"))
        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .started))

        // Phase 1: Collect file paths from the files/ subfolder only.
        // System files (boot.bin, main.dol, etc.) in sys/ are handled by the GameCube dump layer.
        let filesFolder = rootFolder.folder("files")

        // `discPath` is the file's path relative to `files/` (e.g.
        // `subdir/thing.bin`). The project groups extracted files by type,
        // which loses the disc's own directory layout, so the original
        // relative path travels with each entry and is what the rebuild
        // writes back.
        var fsysPaths = [(path: File, discPath: String, data: GoDData)]()
        var otherPaths = [(path: File, discPath: String, data: GoDData)]()

        func discRelativePath(_ path: File) -> String {
            guard path.path.startsWith(filesFolder.path + "/") else {
                return path.fileName
            }
            return String(path.path.dropFirst(filesFolder.path.count + 1))
        }

        func collectPaths(folder: Folder) throws {
            guard let folderData = fileSystem.inspectFolder(at: folder) else {
                return
            }
            for path in folderData.files {
                guard let data = fileSystem.readFile(at: path) else { continue }
                let entry = (path: path, discPath: discRelativePath(path), data: data)
                if path.fileType == "fsys" {
                    fsysPaths.append(entry)
                } else {
                    otherPaths.append(entry)
                }
            }
            for subFolder in folderData.subFolders {
                try collectPaths(folder: subFolder)
            }
        }

        try collectPaths(folder: filesFolder)

        let totalCount = fsysPaths.count + otherPaths.count
        var fstEntries = [FSTRegistry.Entry]()

        // Phase 2: Write non-FSYS game files, routing by file type
        let gsfsysFileName = gsEngine.data.fsys.GSfsysFile.fileName
        for other in otherPaths {
            // Skip the FSYS table of contents — it's not needed in the unpacked output
            if other.path.fileName == gsfsysFileName { continue }

            let targetFolder = gsEngine.resolveFolder(
                forFileType: other.path.fileType ?? "",
                entryFilename: other.path.fileName,
                archiveName: ""
            ).resolvedFolder
            let outputFile = targetFolder.file(other.path.fileName)
            try projectFileSystem.writeFile(other.data, at: outputFile, overwrite: true)
            fstEntries.append(.init(type: .binary, file: outputFile, discPath: other.discPath))
        }

        // Phase 3: Process all FSYS archives concurrently.
        //
        // Results are filled through an unsafe buffer pointer rather than by
        // subscripting the array directly. Writing `array[i]` from several
        // threads is a race even when every thread owns a distinct index:
        // `Array.subscript.set` runs `_makeMutableAndUnique()` first, which
        // touches the shared array struct and its storage refcount, so the
        // accesses overlap regardless of which element each one lands on.
        // (ThreadSanitizer reports both an exclusivity violation and a data
        // race on that form; the buffer-pointer form below is clean.)
        var fsysResults = [Result<FsysResult, Error>?](repeating: nil, count: fsysPaths.count)
        let progressLock = NSLock()
        var fsysProcessed = 0
        var lastReportedPercent = -1

        fsysResults.withUnsafeMutableBufferPointer { results in
            DispatchQueue.concurrentPerform(iterations: fsysPaths.count) { i in
                let source = fsysPaths[i]
                do {
                    results[i] = .success(try processFsys(
                        data: source.data,
                        fileName: source.path.fileName,
                        discPath: source.discPath,
                        toc: toc,
                        gsEngine: gsEngine
                    ))
                } catch {
                    results[i] = .failure(error)
                }

                if let logger {
                    progressLock.lock()
                    fsysProcessed += 1
                    let processed = otherPaths.count + fsysProcessed
                    let percent = Int(min(Double(processed) / Double(totalCount) * 100, 100))
                    if percent > lastReportedPercent {
                        lastReportedPercent = percent
                        logger.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
                    }
                    progressLock.unlock()
                }
            }
        }

        // Font deduplication: collect all .fnt files, deduplicate by content
        var uniqueFonts = [(data: GoDData, file: File)]()
        var fontFileMapping = [String: File]()
        let fontsFolder: Folder = fsysConfig.fileTypeFolders["fnt"] ?? "/Data/Text/Fonts"

        for case .success(let r) in fsysResults.compactMap({ $0 }) {
            for extracted in r.extractedFiles where extracted.file.fileType == "fnt" {
                if let existing = uniqueFonts.first(where: { $0.data == extracted.data }) {
                    fontFileMapping[extracted.file.path] = existing.file
                } else {
                    let canonical = fontsFolder.file("Font_Data_\(uniqueFonts.count + 1).fnt")
                    uniqueFonts.append((data: extracted.data, file: canonical))
                    fontFileMapping[extracted.file.path] = canonical
                }
            }
        }

        for font in uniqueFonts {
            try projectFileSystem.writeFile(font.data, at: font.file, overwrite: true)
        }

        // Merge results into the InMemoryFST, remapping font paths
        for result in fsysResults {
            guard let result else { continue }
            switch result {
            case .success(let fsysResult):
                for extracted in fsysResult.extractedFiles {
                    // Skip .fnt files — they were written above as deduplicated
                    if extracted.file.fileType == "fnt" { continue }
                    try projectFileSystem.writeFile(extracted.data, at: extracted.file, overwrite: true)
                }

                // Remap font entries in registry to deduplicated paths
                let remappedEntries = fsysResult.registry.entries.map { entry -> FSYSRegistry.Entry in
                    if entry.file.fileType == "fnt",
                       let mappedFile = fontFileMapping[entry.file.path] {
                        return FSYSRegistry.Entry(
                            metadata: entry.metadata,
                            file: mappedFile,
                            textureMetadata: entry.textureMetadata,
                            atxMetadata: entry.atxMetadata
                        )
                    }
                    return entry
                }
                let remappedRegistry = FSYSRegistry(
                    groupID: fsysResult.registry.groupID,
                    metaData: fsysResult.registry.metaData,
                    entries: remappedEntries
                )

                try projectFileSystem.writeFile(remappedRegistry, at: fsysResult.registryFile, overwrite: true)
                fstEntries.append(.init(
                    type: .fsys,
                    file: fsysResult.registryFile,
                    discPath: fsysResult.discPath
                ))
            case .failure(let error):
                throw error
            }
        }

        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .completed(true)))

        try projectFileSystem.writeFile(
            FSTRegistry(entries: fstEntries),
            at: Folder("/").file("FST.json"),
            overwrite: true
        )

        return projectFileSystem
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
