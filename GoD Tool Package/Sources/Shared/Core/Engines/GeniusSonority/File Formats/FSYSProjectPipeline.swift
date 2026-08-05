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

public extension GeniusSonorityEngine {
    /// Result of processing a single FSYS archive
    struct FsysResult {
        let registry: FSYSRegistry
        let registryFile: File
        /// The archive's path relative to the disc's `files/` folder, so the
        /// rebuild can put it back where it came from.
        let discPath: String
        let extractedFiles: [(file: File, data: GoDData)]
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
            extractedFiles: extractedFiles
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
                guard let data = fileSystem.readFile(at: path)?.allData else { continue }
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

                try projectFileSystem.writeJSON(remappedRegistry, at: fsysResult.registryFile, overwrite: true)
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
        fileSystem: FileSystemTree
    ) throws -> [FSYSArchive.Entry] {
        let filePath = sourceFolder.file(registryEntry.file.path)
        guard let data = fileSystem.readFile(at: filePath)?.allData else {
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
    func packFSYSFromRegistry(
        registryFile: File,
        sourceFolder: Folder,
        discPath: String? = nil,
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

    public var description: String {
        switch self {
        case let .missingTableOfContents(file, errorTrace):
            return "Error: Couldn't read the FSYS table of contents at \(file)\n\(errorTrace)"
        }
    }
}
