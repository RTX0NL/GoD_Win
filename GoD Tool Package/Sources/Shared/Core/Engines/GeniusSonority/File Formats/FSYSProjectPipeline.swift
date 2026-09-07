//
//  FSYSProjectPipeline.swift
//  GeniusSonority
//
//  Unpacking a disc's FSYS archives into a project tree, and packing that
//  tree back into archives.
//
//  This lived in the ColoXD dump and build *operations*, which put the
//  domain work — archive parsing, THH/THD video pairing, texture decode and
//  re-encode, font de-duplication, registry construction, TOC rebuilding — in
//  the CLI product target. That contradicts the rule that operations map
//  config values to engine calls and nothing more, and it had three concrete
//  costs: the logic wasn't reachable from the planned GUI, randomizer or map
//  editor; it could only be tested by building a config and routing through
//  dispatch; and `DataSectionImporter`-style seams sat unused beside
//  reimplementations of themselves.
//
//  Nothing here needs the Dolphin engine — the operations passed one in and
//  never used it — so this is pure Genius Sonority and lives with the format.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GTX
import Nintendo

public extension GeniusSonorityEngine {
    /// Result of processing a single FSYS archive
    struct FsysResult {
        let registry: FSYSRegistry
        let registryFile: File
        /// The archive's path relative to the disc's `files/` folder, so the
        /// rebuild can put it back where it came from.
        let discPath: String
        let extractedFiles: [(file: File, data: GoDData)]
        /// Entries whose declared file type didn't parse, so they were
        /// extracted as raw bytes instead. Carried out rather than logged
        /// in place because `processFsys` runs concurrently and stays pure;
        /// `unpackProject` emits them once the parallel pass has joined.
        let warnings: [String]
    }

    /// Processes a single FSYS archive (parsing + LZSS decompression).
    /// Pure function with no side effects — safe to call from any thread.
    func processFsys(
        data: GoDData,
        fileName: String,
        discPath: String,
        toc: FsysTOC
            ) throws -> FsysResult {
        let archive = try FSYSArchive(data: data, engine: self)
        let archiveName = fileName.withoutExtensions
        let groupID = archive.groupID != 0 ? archive.groupID : (toc.fsysID(for: archiveName) ?? 0)

        var entries = [FSYSRegistry.Entry]()
        var extractedFiles = [(file: File, data: GoDData)]()
        var warnings = [String]()

        /// An entry whose declared type didn't parse falls back to raw bytes.
        /// The archive says what the entry *is*; when the decoder disagrees
        /// the honest artifact is the bytes, not a silently-missing file.
        func noteFallback(_ entry: FSYSArchive.Entry, _ reason: String) {
            warnings.append(
                "\(archiveName): entry '\(entry.metadata.name).\(entry.metadata.fileType)' "
                + "\(reason) — extracted as raw bytes."
            )
        }

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

        for (entryIndex, entry) in archive.entries.enumerated() {
            let fileType = entry.metadata.fileType

            var targetFolder = self.resolveFolder(
                forFileType: fileType,
                entryFilename: entry.filename,
                archiveName: archiveName
            ).resolvedFolder

            // PBR sorts messages into per-language folders read from the MESG
            // binary itself; nil (Colo/XD) keeps the category routing above.
            if fileType == "msg", let langFolder = self.messageLanguageFolder(forMessageData: entry.data) {
                targetFolder = langFolder
            }
            // Unnamed (PBR `(null)`) entries are named by archive + index;
            // Colo/XD keep their derived pretty filename.
            let projectName = self.projectFilename(
                forEntryNamed: entry.metadata.name,
                filename: entry.filename,
                index: entryIndex,
                archiveName: archiveName
            )

            // THH half of a paired video — combine with its THD sibling
            // and emit a single `.thp`.
            if fileType == "thh" && thhStemsPaired.contains(entry.metadata.name),
               let thd = thdByStem[entry.metadata.name] {
                let thpFile = targetFolder.file(projectName.withoutExtensions + ".thp")
                do {
                    let thp = try THPFile(thh: entry.data, thd: thd.data, name: projectName.withoutExtensions)
                    entries.append(.init(
                        metadata: entry.metadata,
                        file: thpFile,
                        thdMetadata: thd.metadata
                    ))
                    extractedFiles.append((file: thpFile, data: thp.combined))
                } catch {
                    // Fall back to extracting the THH raw if pairing failed.
                    noteFallback(entry, "failed to pair with its THD half (\(error))")
                    let targetFile = targetFolder.file(projectName)
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
                    let pngFile = targetFolder.file(projectName.withoutExtensions + ".png")
                    entries.append(.init(metadata: entry.metadata, file: pngFile, textureMetadata: texMeta))
                    extractedFiles.append((file: pngFile, data: pngData))
                } else {
                    noteFallback(entry, texMeta == nil
                        ? "has no readable GTX header"
                        : "has a GTX header but its pixels didn't decode")
                    let targetFile = targetFolder.file(projectName)
                    entries.append(.init(metadata: entry.metadata, file: targetFile, textureMetadata: texMeta))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
            } else if fileType == "atx" {
                if let (image, atxMeta) = textureDecoder.decodeATX(data: entry.data),
                   let pngData = image.pngData() {
                    let pngFile = targetFolder.file(projectName.withoutExtensions + ".png")
                    entries.append(.init(metadata: entry.metadata, file: pngFile, atxMetadata: atxMeta))
                    extractedFiles.append((file: pngFile, data: pngData))
                } else {
                    noteFallback(entry, "didn't decode as ATX")
                    let targetFile = targetFolder.file(projectName)
                    entries.append(.init(metadata: entry.metadata, file: targetFile))
                    extractedFiles.append((file: targetFile, data: entry.data))
                }
            } else {
                let targetFile = targetFolder.file(projectName)
                entries.append(.init(metadata: entry.metadata, file: targetFile))
                extractedFiles.append((file: targetFile, data: entry.data))
            }
        }

        let registry = FSYSRegistry(
            groupID: groupID,
            metaData: archive.metaData,
            entries: entries
        )
        let registryFile = self.data.fsys.archivesFolder.file(fileName + ".json")

        return FsysResult(
            registry: registry,
            registryFile: registryFile,
            discPath: discPath,
            extractedFiles: extractedFiles,
            warnings: warnings
        )
    }

    func unpackProject(
        from rootFolder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws -> FileSystemTree {

        let projectFileSystem = InMemoryFST()

        // Folders are created on-demand when files are written,
        // avoiding empty directories for unused file types.
        let fsysConfig = self.data.fsys

        let gsfsysFile = rootFolder.file(self.data.fsys.GSfsysFile.path)
        guard let gsfsysData = fileSystem.readFile(at: gsfsysFile)?.allData else {
            throw FSYSPipelineError.missingTableOfContents(gsfsysFile, .init())
        }
        let toc = try FsysTOC(tocData: gsfsysData, engine: self)

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
        var archivePaths = [(path: File, discPath: String, data: GoDData)]()
        var otherPaths = [(path: File, discPath: String, data: GoDData)]()

        // Nintendo containers are picked out by extension, not by sniffing
        // every file's magic: the discs name these consistently, so an
        // extension check avoids probing files that are neither. Which of
        // the two formats it is — and which way round its scalars read —
        // still comes from the magic, inside the parser.
        let archiveExtensions = Set(NintendoArchiveFormat.allCases.map(\.fileExtension))

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
                guard let data = fileSystem.readFile(at: path)?.allData else { continue }
                let entry = (path: path, discPath: discRelativePath(path), data: data)
                if path.fileType == "fsys" {
                    fsysPaths.append(entry)
                } else if let fileType = path.fileType, archiveExtensions.contains(fileType) {
                    archivePaths.append(entry)
                } else {
                    otherPaths.append(entry)
                }
            }
            for subFolder in folderData.subFolders {
                try collectPaths(folder: subFolder)
            }
        }

        try collectPaths(folder: filesFolder)

        let totalCount = fsysPaths.count + archivePaths.count + otherPaths.count
        var fstEntries = [FSTRegistry.Entry]()

        /// Where an archive's unpacked artifacts go: under the archives
        /// folder, mirroring the directory it sat in on the disc. PBR ships
        /// the same `homeBtn.arc` under both `hb/HomeButton2` and
        /// `hb/HomeButton3`, so a flat layout would have them overwrite
        /// each other.
        func archiveFolder(forDiscPath discPath: String) -> Folder {
            var parts = discPath.split(separator: "/")
            guard parts.count > 1 else { return fsysConfig.archivesFolder }
            parts.removeLast()
            return fsysConfig.archivesFolder.folder(parts.joined(separator: "/"))
        }

        /// Falls an archive back to its raw bytes.
        ///
        /// An archive the tool can't read is still a file the disc needs, so
        /// it is extracted verbatim and its FST entry becomes `.binary` —
        /// the rebuild writes those bytes straight back. Losing the ability
        /// to edit one archive is a much smaller failure than refusing to
        /// dump the disc. It lands beside where its unpacked form would
        /// have, so two failures that share a filename can't collide.
        func extractRaw(
            _ item: (path: File, discPath: String, data: GoDData)
        ) throws -> FSTRegistry.Entry {
            let outputFile = archiveFolder(forDiscPath: item.discPath).file(item.path.fileName)
            try projectFileSystem.writeFile(item.data, at: outputFile, overwrite: true)
            return .init(type: .binary, file: outputFile, discPath: item.discPath)
        }

        // Phase 2: Write non-FSYS game files, routing by file type
        let gsfsysFileName = self.data.fsys.GSfsysFile.fileName
        for other in otherPaths {
            // Skip the FSYS table of contents — it's not needed in the unpacked output
            if other.path.fileName == gsfsysFileName { continue }

            let targetFolder = self.resolveFolder(
                forFileType: other.path.fileType ?? "",
                entryFilename: other.path.fileName,
                archiveName: ""
            ).resolvedFolder
            let outputFile = targetFolder.file(other.path.fileName)
            try projectFileSystem.writeFile(other.data, at: outputFile, overwrite: true)
            fstEntries.append(.init(type: .binary, file: outputFile, discPath: other.discPath))
        }

        // Phase 2b: Unpack Nintendo containers (U8 `.arc`, NARC `.narc`).
        //
        // Serial rather than folded into the concurrent FSYS pass below: a
        // disc holds a handful of these against hundreds of FSYS archives,
        // so the parallelism would buy nothing.
        var archiveFallbacks = 0
        if !archivePaths.isEmpty {
            let nintendoEngine = try NintendoEngine.defaults()
            for archive in archivePaths {
                do {
                    let unpacked = try nintendoEngine.unpackArchive(
                        data: archive.data,
                        archiveName: archive.path.fileName,
                        into: archiveFolder(forDiscPath: archive.discPath),
                        fileSystem: projectFileSystem,
                        overwrite: true
                    )
                    fstEntries.append(.init(
                        type: .nintendoArchive,
                        file: unpacked.manifestFile,
                        discPath: archive.discPath
                    ))
                } catch {
                    archiveFallbacks += 1
                    logger?.log(.warning(
                        "\(archive.discPath) didn't unpack as an archive (\(error)) "
                        + "— extracted as raw bytes."
                    ))
                    fstEntries.append(try extractRaw(archive))
                }
            }
            logger?.log(.info(
                "Unpacked \(archivePaths.count - archiveFallbacks)/\(archivePaths.count) Nintendo containers"
            ))
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
                        toc: toc
                        
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

        // Entries whose declared type didn't parse were extracted raw. Report
        // them once here rather than from inside the concurrent pass.
        var fallbackCount = 0
        for case .success(let r) in fsysResults.compactMap({ $0 }) {
            for warning in r.warnings {
                logger?.log(.warning(warning))
                fallbackCount += 1
            }
        }
        if fallbackCount > 0 {
            logger?.log(.warning(
                "\(fallbackCount) FSYS entr\(fallbackCount == 1 ? "y" : "ies") didn't parse as "
                + "their declared file type and were extracted as raw bytes."
            ))
        }

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
        var fsysFallbacks = 0
        for (source, result) in zip(fsysPaths, fsysResults) {
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

                try projectFileSystem.writeJSON(remappedRegistry, at: fsysResult.registryFile, overwrite: true)
                fstEntries.append(.init(
                    type: .fsys,
                    file: fsysResult.registryFile,
                    discPath: fsysResult.discPath
                ))
            case .failure(let error):
                // Same policy as an unreadable Nintendo container: keep the
                // bytes and mark the entry `.binary` so the rebuild puts
                // them back, rather than failing the whole dump over one
                // archive.
                fsysFallbacks += 1
                logger?.log(.warning(
                    "\(source.discPath) didn't unpack as FSYS (\(error)) — extracted as raw bytes."
                ))
                fstEntries.append(try extractRaw(source))
            }
        }

        if fsysFallbacks > 0 {
            logger?.log(.warning(
                "\(fsysFallbacks) FSYS archive\(fsysFallbacks == 1 ? "" : "s") didn't unpack "
                + "and \(fsysFallbacks == 1 ? "was" : "were") extracted as raw bytes."
            ))
        }

        logger?.log(.taskStatus(taskName: "Decode Colosseum/XD File System", status: .completed(true)))

        try projectFileSystem.writeJSON(
            FSTRegistry(entries: fstEntries),
            at: Folder("/").file("FST.json"),
            overwrite: true
        )

        return projectFileSystem
    }

    /// Resolves one `FSYSRegistry.Entry` to the list of archive entries
    /// it expands to. Most registry entries map 1:1 to an archive entry;
    /// THP-pair entries expand into the two THH + THD entries the
    /// archive originally held.
    func resolveArchiveEntries(
        registryEntry: FSYSRegistry.Entry,
        sourceFolder: Folder,
        fileSystem: FileSystemTree,
        structDefinitions: [String: StructDefinition] = [:]
    ) throws -> [FSYSArchive.Entry] {
        let filePath = sourceFolder.file(registryEntry.file.path)
        guard let data = fileSystem.readFile(at: filePath)?.allData else {
            throw FSTErrors.fileNotFound(filePath, .init())
        }

        // Struct-typed data table: reassemble the table binary from its
        // header JSON, row CSV, and raw string-pool/name-table extras. The
        // struct definitions come from the caller's game engine.
        if let dataTable = registryEntry.dataTable {
            let bytes = try reassembleDataTable(
                registryEntry: registryEntry, dataTable: dataTable, csv: data,
                sourceFolder: sourceFolder, fileSystem: fileSystem, structDefinitions: structDefinitions
            )
            return [FSYSArchive.Entry(
                metadata: registryEntry.metadata,
                filename: registryEntry.metadata.name + "." + registryEntry.metadata.fileType,
                data: bytes
            )]
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
    func packFSYSFromRegistry(
        registryFile: File,
        sourceFolder: Folder,
        discPath: String? = nil,
                fileSystem: FileSystemTree,
        structDefinitions: [String: StructDefinition] = [:]
    ) throws -> FileData {
        let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryFile)

        var archiveEntries: [FSYSArchive.Entry] = []
        for registryEntry in registry.entries {
            archiveEntries.append(contentsOf: try resolveArchiveEntries(
                registryEntry: registryEntry,
                sourceFolder: sourceFolder,
                fileSystem: fileSystem,
                structDefinitions: structDefinitions
            ))
        }

        let archive = FSYSArchive(metadata: registry.metaData, entries: archiveEntries)
        // `discPath` is the archive's original location relative to `files/`;
        // fall back to the registry-derived filename for callers (and older
        // registries) that don't carry one.
        let outputPath = discPath ?? registryFile.fileName.withoutExtension
        return FileData(
            file: File(outputPath),
            data: try archive.data(groupID: registry.groupID, engine: self)
        )
    }

    /// Builds GSfsys.toc from the FSYS entries in an FSTRegistry.
    /// Reads each FSYSRegistry JSON to get the groupID, then serializes a FsysTOC.
    func buildGSfsysTOC(
        fstRegistryFile: File,
        sourceFolder: Folder,
                fileSystem: FileSystemTree
    ) throws -> GoDData {
        let fstRegistry: FSTRegistry = try fileSystem.decodeJSON(from: fstRegistryFile)
        var fsysIDsByFilename = [String: Int]()

        for entry in fstRegistry.entries where entry.type == .fsys {
            let registryPath = sourceFolder.file(entry.file.path)
            let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryPath)
            // Registry filename is e.g. "D1_out.fsys.json" → FSYS name is "D1_out"
            //
            // Group ID 0 means "not a TOC member", not "unknown": the games
            // ship archives that deliberately have no GSfsys.toc entry, and
            // re-adding them would produce a TOC the game doesn't expect.
            // Skipping them is correct — don't "fix" this into a lookup.
            guard registry.groupID != 0 else { continue }
            let fsysName = registryPath.fileName.withoutExtensions
            fsysIDsByFilename[fsysName] = registry.groupID
        }

        let toc = FsysTOC(fsysIDsByFilename: fsysIDsByFilename, unknown: self.data.toc.unknown)
        toc.padding = self.data.toc.padding
        toc.junk1 = self.data.toc.junk1
        toc.junk2 = self.data.toc.junk2
        toc.junk3 = self.data.toc.junk3
        return try toc.tocData(with: self)
    }

    func packProject(
        fstRegistryFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        structDefinitions: [String: StructDefinition] = [:],
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
        let archiveEntries = fstRegistry.entries.filter { $0.type == .nintendoArchive }
        // `max(1, …)` because this divides: a disc whose FST holds only
        // Nintendo containers has no FSYS and no binary entries, and 0/0 is
        // a NaN that traps on the way to Int.
        let totalCount = max(1, fsysEntries.count + binaryEntries.count + archiveEntries.count)

        // Phase 1: Copy non-FSYS binary files to output
        for (i, entry) in binaryEntries.enumerated() {
            let sourcePath = sourceFolder.file(entry.file.path)
            guard let data = fileSystem.readFile(at: sourcePath)?.allData else {
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
                                                fileSystem: fileSystem,
                        structDefinitions: structDefinitions
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

        // Phase 2b: Repack Nintendo containers (U8 / NARC) from their
        // manifests. Kept serial rather than folded into the concurrent
        // FSYS pass above: a disc holds a handful of these against
        // hundreds of archives, so the parallelism would buy nothing and
        // the loop stays readable.
        if !archiveEntries.isEmpty {
            logger?.log(.info("Repacking \(archiveEntries.count) Nintendo containers"))
            let nintendoEngine = try NintendoEngine.defaults()
            for entry in archiveEntries {
                let manifestFile = sourceFolder.file(entry.file.path)
                let packed = try nintendoEngine.packArchive(
                    manifestFile: manifestFile,
                    fileSystem: fileSystem
                )
                let outputFile = outputFolder.folder("files").file(entry.rebuildPath)
                if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                    try fileSystem.writeFile(packed, at: outputFile, overwrite: overwrite)
                }
            }
        }

        // Phase 3: Rebuild GSfsys.toc from FSYS registries
        logger?.log(.info("Rebuilding GSfsys.toc"))
        let tocData = try buildGSfsysTOC(
            fstRegistryFile: fstRegistryFile,
            sourceFolder: sourceFolder,
                        fileSystem: fileSystem
        )
        let tocOutputFile = outputFolder.file("files/" + self.data.fsys.GSfsysFile.fileName)
        try fileSystem.writeFile(tocData, at: tocOutputFile, overwrite: true)
        logger?.log(.info("Wrote \(tocOutputFile.fileName) (\(tocData.length) bytes)"))

        logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .completed(true)))
    }
}

public enum FSYSPipelineError: GoDError {
    /// The disc's FSYS table of contents is missing, so nothing can be
    /// matched to a group ID.
    case missingTableOfContents(File, ErrorTrace)
    /// A data-table entry names a struct the pack wasn't given a definition
    /// for. The caller has to supply the game engine's struct definitions.
    case missingStructDefinition(String, ErrorTrace)

    public var description: String {
        switch self {
        case let .missingTableOfContents(file, errorTrace):
            return "Error: Couldn't read the FSYS table of contents at \(file)\n\(errorTrace)"
        case let .missingStructDefinition(name, errorTrace):
            return "Error: No struct definition '\(name)' supplied to reassemble a data-table entry.\n\(errorTrace)"
        }
    }
}

public extension GeniusSonorityEngine {
    /// Reassemble a typed data-table binary from its dumped header JSON, row
    /// CSV, and raw string-pool/name-table extras. Header + string pool +
    /// entries + (0x10 pad) + name/relocation tables, matching the layout the
    /// dump split apart.
    func reassembleDataTable(
        registryEntry: FSYSRegistry.Entry,
        dataTable: FSYSRegistry.DataTableMetadata,
        csv: GoDData,
        sourceFolder: Folder,
        fileSystem: FileSystemTree,
        structDefinitions: [String: StructDefinition]
    ) throws -> GoDData {
        guard let entryDefinition = structDefinitions[dataTable.entryStructName] else {
            throw FSYSPipelineError.missingStructDefinition(dataTable.entryStructName, .init())
        }
        guard let headerDefinition = structDefinitions[dataTable.headerStructName] else {
            throw FSYSPipelineError.missingStructDefinition(dataTable.headerStructName, .init())
        }

        let csvText = String(decoding: csv.rawBytes, as: UTF8.self)
        let rows = try StructTableCSV.decode(csvText, definition: entryDefinition, byteOrder: .big).entries

        let headerFile = sourceFolder.file(dataTable.headerFile.path)
        guard let headerJSON = fileSystem.readFile(at: headerFile)?.allData else {
            throw FSTErrors.fileNotFound(headerFile, .init())
        }
        let header = try StructData(definition: headerDefinition, json: headerJSON, byteOrder: .big)

        func extra(_ file: File?) throws -> GoDData? {
            guard let file else { return nil }
            let path = sourceFolder.file(file.path)
            guard let bytes = fileSystem.readFile(at: path)?.allData else {
                throw FSTErrors.fileNotFound(path, .init())
            }
            return bytes
        }

        let result = GoDData(byteOrder: .big)
        result.append(header.data)
        if let leading = try extra(dataTable.leadingExtraFile) { result.append(leading) }
        for row in rows { result.append(row.data) }
        result.align(to: data.fsys.dataTableRegionAlignmentValue)
        if let trailing = try extra(dataTable.trailingExtraFile) { result.append(trailing) }
        return result
    }
}
