import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import GTX

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
                    fileSystem.writeFile(tocData, at: outputFile, overwrite: overwrite)
                    logger?.log(.info("Wrote \(outputFile.fileName) (\(tocData.length) bytes)"))
                }

            case let .buildFST(contentsFolder, outputFile, overwrite, dolphinEnginePath):
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)

                logger?.log(.info("Building fst.bin from \(contentsFolder.path)"))
                let fst = DolphinFST(fileSystem: fileSystem, root: contentsFolder)
                let fstData = try fst.tocData(userOffset: 0, dolphinEngine: dolphinEngine)

                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(fstData, at: outputFile, overwrite: overwrite)
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
                    fileSystem.writeFile(archiveData.data, at: outputFile, overwrite: overwrite)
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

            case let .buildATXs(projectsFolder, outputFolder, overwrite):
                // Each ATX lives in its own subfolder (<name>/) containing
                // <name>.atx.json plus its frame PNGs.
                guard let meta = fileSystem.inspectFolder(at: projectsFolder) else {
                    logger?.log(.warning("ATX projects folder not found: \(projectsFolder.path)"))
                    break
                }
                logger?.log(.info("Building \(meta.subFolders.count) ATX projects"))
                for project in meta.subFolders {
                    let name = project.folderName
                    let outputFile = outputFolder.file("\(name).atx")
                    try buildATX(
                        projectFolder: project,
                        outputFile: outputFile,
                        overwrite: overwrite,
                        fileSystem: fileSystem,
                        logger: logger
                    )
                }

            case let .buildATX(projectFolder, outputFile, overwrite):
                try buildATX(
                    projectFolder: projectFolder,
                    outputFile: outputFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
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
        let file = try MSGFile(outputs: [File("\(stem).msg.json"): json])
        let binary = try file.binaryData
        fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(jsonFile.fileName): \(file.entries.count) entries → \(outputFile.fileName)"))
    }

    /// Reads every file in `projectFolder` into an outputs dict and feeds it
    /// through `ATXFile.init(outputs:).binaryData`.
    private static func buildATX(
        projectFolder: Folder,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        guard let meta = fileSystem.inspectFolder(at: projectFolder) else {
            throw FSTErrors.fileNotFound(projectFolder.file("."), .init())
        }
        var outputs: [File: GoDData] = [:]
        for file in meta.files {
            guard let data = fileSystem.readFile(at: file) else { continue }
            outputs[File(file.fileName)] = data
        }
        let atx = try ATXFile(outputs: outputs)
        let binary = try atx.binaryData
        fileSystem.writeFile(binary, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(atx.name): \(atx.framePixels.count) frames → \(outputFile.fileName)"))
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
        guard fileSystem.inspectFile(at: metadataFile) != nil else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }
        let file: GSWFile = try fileSystem.decodeJSON(from: metadataFile)

        guard let baseFolder = metadataFile.parentFolder else {
            throw FSTErrors.fileNotFound(metadataFile, .init())
        }

        let allRefs = file.allTextureRefs
        var images = [GoDImage]()
        images.reserveCapacity(allRefs.count)
        for ref in allRefs {
            let pngFile = ColoXD.resolveRelativeFile(ref.pngPath, in: baseFolder)
            guard let pngData = fileSystem.readFile(at: pngFile) else {
                throw FSTErrors.fileNotFound(pngFile, .init())
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw FSTErrors.fileNotFound(pngFile, .init())
            }
            images.append(image)
        }

        let gswData = try GSWParser.serialize(file: file, images: images)
        if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
            fileSystem.writeFile(gswData, at: outputFile, overwrite: overwrite)
            logger?.log(.info("Built flash menu \(outputFile.fileName) (\(file.tags.count) tags, \(allRefs.count) textures, \(gswData.length) bytes)"))
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
            fileSystem.writeFile(fontData, at: outputFile, overwrite: overwrite)
            logger?.log(.info("Built font \(outputFile.fileName) (\(font.visibleGlyphs.count) glyphs, \(fontData.length) bytes)"))
        }
    }

    // MARK: - Core FSYS packing

    /// Packs a single FSYS archive from its registry and resolved entry file data.
    private static func packFSYS(
        registry: FSYSRegistry,
        entryFiles: [FileData],
        gsEngine: GeniusSonorityEngine
    ) throws -> FSYSArchive {
        let entries = zip(registry.entries, entryFiles).map { registryEntry, fileData in
            FSYSArchive.Entry(
                metadata: registryEntry.metadata,
                filename: fileData.fileName,
                data: fileData.data
            )
        }

        return FSYSArchive(metadata: registry.metaData, entries: entries)
    }

    /// Reads a registry JSON and its entry files from the filesystem, packs into an FSYS archive.
    /// Pure function safe for concurrent use.
    private static func packFSYSFromRegistry(
        registryFile: File,
        sourceFolder: Folder,
        gsEngine: GeniusSonorityEngine,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryFile)

        let entryFiles = try registry.entries.map { registryEntry -> FileData in
            let filePath = sourceFolder.file(registryEntry.file.path)
            guard let data = fileSystem.readFile(at: filePath) else {
                throw FSTErrors.fileNotFound(filePath, .init())
            }
            var entryData = data
            // Re-encode PNG back to GTX/ATX if texture metadata is present
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
            return FileData(fileName: filename, data: entryData)
        }

        let archiveData = try packFSYS(registry: registry, entryFiles: entryFiles, gsEngine: gsEngine)
        let fsysFileName = registryFile.fileName.withoutExtension
        return FileData(fileName: fsysFileName, data: try archiveData.data(groupID: registry.groupID, engine: gsEngine))
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
            let outputFile = outputFolder.file("files/" + entry.file.fileName)
            if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                fileSystem.writeFile(data, at: outputFile, overwrite: overwrite)
            }

            let percent = Int(Double(i + 1) / Double(totalCount) * 100)
            if percent > 0 {
                logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .progress(Percentage(Double(percent)))))
            }
        }

        // Phase 2: Pack FSYS archives concurrently
        var fsysResults = [Result<FileData, Error>?](repeating: nil, count: fsysEntries.count)
        let progressLock = NSLock()
        var fsysProcessed = 0
        var lastReportedPercent = Int(Double(binaryEntries.count) / Double(totalCount) * 100)

        DispatchQueue.concurrentPerform(iterations: fsysEntries.count) { i in
            let entry = fsysEntries[i]
            let registryFile = sourceFolder.file(entry.file.path)

            do {
                fsysResults[i] = .success(try packFSYSFromRegistry(
                    registryFile: registryFile,
                    sourceFolder: sourceFolder,
                    gsEngine: gsEngine,
                    fileSystem: fileSystem
                ))
            } catch {
                fsysResults[i] = .failure(error)
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

        // Write packed archives to output
        for result in fsysResults {
            guard let result else { continue }
            switch result {
            case .success(let packed):
                let outputFile = outputFolder.file("files/" + packed.fileName)
                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    fileSystem.writeFile(packed.data, at: outputFile, overwrite: overwrite)
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
        fileSystem.writeFile(tocData, at: tocOutputFile, overwrite: true)
        logger?.log(.info("Wrote \(tocOutputFile.fileName) (\(tocData.length) bytes)"))

        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .completed(true)))
    }
}
