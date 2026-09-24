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

    /// FNV-1a over the whole payload, used only to bucket candidates for the
    /// path-collision pass. A match is always confirmed by comparing the
    /// bytes, so the hash never decides equality on its own.
    static func contentDigest(_ data: GoDData) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data.rawBytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The directory part of a disc-relative path, or nil when the file sits
    /// at the root of `files/`. `hb/HomeButton2/config.txt` → `hb/HomeButton2`.
    static func discDirectory(of discPath: String) -> String? {
        var parts = discPath.split(separator: "/")
        guard parts.count > 1 else { return nil }
        parts.removeLast()
        return parts.joined(separator: "/")
    }

    /// `agent_m_a2.dat` → `agent_m_a2 (2).dat`, for the second and later
    /// distinct files claiming one project path.
    static func disambiguated(_ file: File, ordinal: Int) -> File {
        let name = file.fileName
        let ext = File(name).fileType.map { "." + $0 } ?? ""
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count))
        let renamed = "\(stem) (\(ordinal))\(ext)"
        return file.parentFolder?.file(renamed) ?? File(renamed)
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
        // The table of contents is the only authority on an archive's group
        // ID: it is what the game looks archives up by, what the rebuilt table
        // is written from, and what goes back into the rebuilt header. The
        // header's own ID is discarded, because it disagrees on real discs —
        // 35 to 40 archives per XD disc carry one the table never lists, and
        // two more are listed under a value their header doesn't have — and a
        // rebuild corrects those rather than carrying them forward.
        let groupID = toc.fsysID(for: archiveName) ?? 0

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

        // An ISF sound is two entries — the `I_SF` header and the ADPCM
        // stream it describes — which the audio dump pairs by filename stem.
        // Nameless halves would otherwise be numbered separately and stop
        // looking like a pair, so an archive holding exactly one of each
        // gives both the header's index.
        //
        // Deliberately only that case: `stm_se_nakigoe_archive` holds 388
        // pairs whose halves interleave rather than running in step (its
        // first header's stream is the *second* stream entry), so numbering
        // those in parallel would pair them confidently and wrongly. They
        // keep their own indices and stay unpaired instead.
        let isfHeaders = archive.entries.enumerated().filter { $0.element.metadata.fileType == "ish" }
        let isfStreams = archive.entries.enumerated().filter { $0.element.metadata.fileType == "isd" }
        var pairedEntryIndex = [Int: Int]()
        if isfHeaders.count == 1, isfStreams.count == 1 {
            pairedEntryIndex[isfStreams[0].offset] = isfHeaders[0].offset
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
            // Colo/XD keep their derived pretty filename. Fonts take the
            // index either way: a stored font name is only unique inside its
            // own archive, and on the XD US disc three of them — `fight`,
            // `world_map` and `M2_enter_1F` — each name two different fonts.
            let projectName = self.projectFilename(
                forEntryNamed: entry.metadata.name,
                filename: entry.filename,
                index: pairedEntryIndex[entryIndex] ?? entryIndex,
                archiveName: archiveName,
                indexed: fileType == "fnt"
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

        /// Where a disc file's project artifact goes.
        ///
        /// A file at the root of `files/` keeps the folder its type routed it
        /// to. A file in a disc directory mirrors that directory underneath —
        /// disc paths are unique, so mirroring the directory makes the project
        /// path unique too. PBR ships the same `homeBtn.arc` and the same five
        /// loose files under both `hb/HomeButton2` and `hb/HomeButton3`, and a
        /// flat layout had each pair overwrite itself.
        ///
        /// A platform directory ignores `routed` entirely and mirrors its disc
        /// path under `/Platform` instead: that content belongs to the console,
        /// not the game, so it doesn't sort into the game's asset folders.
        func outputFolder(forDiscPath discPath: String, routedTo routed: Folder) -> Folder {
            guard let directory = Self.discDirectory(of: discPath) else { return routed }
            if fsysConfig.isPlatformDirectory(directory) {
                return fsysConfig.platformBaseFolderValue.folder(directory)
            }
            return routed.folder(directory)
        }

        /// Where an archive's unpacked artifacts go.
        func archiveFolder(forDiscPath discPath: String) -> Folder {
            outputFolder(forDiscPath: discPath, routedTo: fsysConfig.archivesFolder)
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
            // A loose file keeps the directory it sat in on the disc, the same
            // way an unpacked archive does — see `outputFolder`.
            let outputFile = outputFolder(forDiscPath: other.discPath, routedTo: targetFolder)
                .file(other.path.fileName)
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

        // Path collisions: two entries can resolve to one project path while
        // holding different bytes — a map archive's build of a character
        // against `people_archive`'s, two revisions of one message table, or
        // (in a few archives) two entries of one name inside a single archive,
        // which no folder rule can tell apart. Whatever writes second used to
        // win, and both registries then pointed at the survivor, so the
        // rebuild put its bytes into every archive that shared the name.
        //
        // Identical payloads still share one file — that is what lets a shared
        // asset be edited in one place, and on the XD US disc 310 of the 352
        // names appearing in more than one archive are byte-identical. Only a
        // genuinely different payload takes a name of its own.
        //
        // Walked in disc-path order rather than filesystem-enumeration order
        // so which copy keeps the plain name doesn't depend on how the host
        // listed the directory.
        var claimedPaths = [String: [(digest: UInt64, data: GoDData, file: File)]]()
        var resolvedExtracted = [[(file: File, data: GoDData)]](repeating: [], count: fsysResults.count)
        var resolvedEntries = [[FSYSRegistry.Entry]](repeating: [], count: fsysResults.count)
        var splitPaths = [String]()

        for index in fsysResults.indices.sorted(by: { fsysPaths[$0].discPath < fsysPaths[$1].discPath }) {
            guard case .success(let r)? = fsysResults[index] else { continue }
            var files = r.extractedFiles
            var entries = r.registry.entries
            // `processFsys` appends to both in lockstep; if that ever stops
            // being true, leave the paths alone rather than pair them wrongly.
            guard files.count == entries.count else {
                resolvedExtracted[index] = files
                resolvedEntries[index] = entries
                continue
            }
            for i in files.indices {
                let original = files[i].file
                let digest = Self.contentDigest(files[i].data)
                var claims = claimedPaths[original.path] ?? []
                if let shared = claims.first(where: { $0.digest == digest && $0.data == files[i].data }) {
                    files[i].file = shared.file
                    entries[i] = entries[i].pointing(at: shared.file)
                    continue
                }
                let assigned = claims.isEmpty
                    ? original
                    : Self.disambiguated(original, ordinal: claims.count + 1)
                if !claims.isEmpty { splitPaths.append(assigned.path) }
                claims.append((digest, files[i].data, assigned))
                claimedPaths[original.path] = claims
                files[i].file = assigned
                entries[i] = entries[i].pointing(at: assigned)
            }
            resolvedExtracted[index] = files
            resolvedEntries[index] = entries
        }

        if !splitPaths.isEmpty {
            logger?.log(.warning(
                "\(splitPaths.count) project path\(splitPaths.count == 1 ? "" : "s") held more than one "
                + "distinct file and were split: \(splitPaths.sorted().prefix(12).joined(separator: ", "))"
                + (splitPaths.count > 12 ? ", …" : "")
            ))
        }

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

        // Fonts are written like every other entry — see `projectFilename`.
        // They used to be pooled: one copy of each distinct font under a
        // serial `Font_Data_<n>`, shared by every archive carrying those
        // bytes. That name renumbered whenever the set of fonts changed and
        // took the atlas a user had been editing with it, and it could only
        // ever name one of the archives a font came from. What the pool
        // actually saved is small — the file 83 XD US archives share holds a
        // single glyph, a space, and the real fonts (`jis_1`, `fight`,
        // `world_map`) appear once or twice each — so a disc costs under a
        // megabyte more this way (XD US 919 KB in 26 files → 1738 KB in 165)
        // and every file is named for where it came from. Entries that agree
        // on a name *and* on their bytes still share one path through the
        // collision pass above, which is what keeps that 205 down to 165.
        var fsysFallbacks = 0
        for (index, (source, result)) in zip(fsysPaths, fsysResults).enumerated() {
            guard let result else { continue }
            switch result {
            case .success(let fsysResult):
                for extracted in resolvedExtracted[index] {
                    try projectFileSystem.writeFile(extracted.data, at: extracted.file, overwrite: true)
                }

                let registry = FSYSRegistry(
                    groupID: fsysResult.registry.groupID,
                    metaData: fsysResult.registry.metaData,
                    entries: resolvedEntries[index]
                )

                try projectFileSystem.writeJSON(registry, at: fsysResult.registryFile, overwrite: true)
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

        // The table of contents, entry for entry. The rebuild derives most of
        // it from the archives it finds, so without this the entries naming
        // archives the disc doesn't ship would be lost — 11 on the XD US disc.
        // Those get an empty `file`; the rebuild re-emits them from here.
        let registryByArchiveName = Dictionary(
            fstEntries
                .filter { $0.type == .fsys }
                .map { ($0.file.fileName.withoutExtensions, $0.file.path) },
            uniquingKeysWith: { first, _ in first }
        )
        try projectFileSystem.writeJSON(
            FsysTOCManifest(entries: toc.listedEntries.map { listed in
                .init(
                    name: listed.name,
                    groupID: listed.groupID,
                    file: registryByArchiveName[listed.name] ?? ""
                )
            }),
            at: Folder("/").file(FsysTOC.manifestFileName),
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
        //
        // A failure here has to stop this entry. These branches used to fall
        // through on a nil, which left `entryData` holding the *PNG's* bytes
        // and packed those into the archive as the texture — a silently
        // corrupt archive, reported as a clean build. The pack collects
        // failures and reports them all at the end, so throwing costs this
        // one member rather than the run.
        var entryData = data
        if filePath.fileType == "png" {
            let decoder = GXTextureDecoder()
            if let atxMeta = registryEntry.atxMetadata {
                guard let image = GoDImage.fromPNG(data) else {
                    throw FSYSPipelineError.unreadableTexturePNG(filePath, .init())
                }
                guard let atxData = decoder.encodeATX(image: image, metadata: atxMeta) else {
                    throw FSYSPipelineError.textureEncodeFailed(filePath, "ATX", .init())
                }
                entryData = atxData
            } else if let texMeta = registryEntry.textureMetadata {
                guard let image = GoDImage.fromPNG(data) else {
                    throw FSYSPipelineError.unreadableTexturePNG(filePath, .init())
                }
                guard let gtxData = decoder.encode(image: image, metadata: texMeta) else {
                    throw FSYSPipelineError.textureEncodeFailed(filePath, "GTX", .init())
                }
                entryData = gtxData
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
            // Group ID 0 means "the disc's table didn't list this archive",
            // which is the one thing that decides membership. It comes from
            // the table the dump read, never from the archive header — 17 to
            // 40 archives per disc carry a header ID they are not listed
            // under, and adding those back produces a table the game doesn't
            // expect.
            guard registry.groupID != 0 else { continue }
            let fsysName = registryPath.fileName.withoutExtensions
            fsysIDsByFilename[fsysName] = registry.groupID
        }

        // Entries the disc listed but shipped no archive for. They are real
        // entries with real group IDs, so deriving the table from the archives
        // alone drops them and shortens it; the dump records them with an
        // empty `file` and they go straight back in.
        let manifestFile = sourceFolder.file(FsysTOC.manifestFileName)
        if let manifest: FsysTOCManifest = try? fileSystem.decodeJSON(from: manifestFile) {
            for dangling in manifest.danglingEntries where fsysIDsByFilename[dangling.name] == nil {
                fsysIDsByFilename[dangling.name] = dangling.groupID
            }
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

        // One member failing shouldn't abandon the rest: a disc holds
        // thousands of them, and stopping at the first leaves `Contents`
        // half-rebuilt — part new, part whatever the last build left there,
        // which is worse than either a complete rebuild or none. Every
        // failure is recorded and reported together once the pass is done.
        var failures = [String]()
        func recordFailure(_ name: String, _ error: Error) {
            failures.append("\(name): \(error)")
            logger?.log(.warning("Couldn't pack \(name): \(error)"))
        }

        // Phase 1: Copy non-FSYS binary files to output
        for (i, entry) in binaryEntries.enumerated() {
            let sourcePath = sourceFolder.file(entry.file.path)
            // `rebuildPath` is the file's original location relative to
            // `files/`, so subdirectories on the disc are reproduced rather
            // than flattened into one folder (which also collided whenever
            // two directories held the same filename).
            let outputFile = outputFolder.folder("files").file(entry.rebuildPath)
            if let data = fileSystem.readFile(at: sourcePath)?.allData {
                do {
                    if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                        try fileSystem.writeFile(data, at: outputFile, overwrite: overwrite)
                    }
                } catch {
                    recordFailure(entry.rebuildPath, error)
                }
            } else {
                recordFailure(entry.rebuildPath, FSTErrors.fileNotFound(sourcePath, .init()))
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
        for (i, result) in fsysResults.enumerated() {
            guard let result else { continue }
            let name = fsysEntries[i].rebuildPath
            switch result {
            case .success(let packed):
                do {
                    let outputFile = outputFolder.folder("files").file(packed.file.path)
                    if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                        try fileSystem.writeFile(packed.data, at: outputFile, overwrite: overwrite)
                    }
                } catch {
                    recordFailure(name, error)
                }
            case .failure(let error):
                recordFailure(name, error)
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
                do {
                    let manifestFile = sourceFolder.file(entry.file.path)
                    let packed = try nintendoEngine.packArchive(
                        manifestFile: manifestFile,
                        fileSystem: fileSystem
                    )
                    let outputFile = outputFolder.folder("files").file(entry.rebuildPath)
                    if overwrite || fileSystem.inspectFile(at: outputFile) == nil {
                        try fileSystem.writeFile(packed, at: outputFile, overwrite: overwrite)
                    }
                } catch {
                    recordFailure(entry.rebuildPath, error)
                }
            }
        }

        // Phase 3: Rebuild GSfsys.toc from FSYS registries
        //
        // Built from the registries rather than from what phase 2 wrote, so
        // it still describes the disc correctly even when an archive failed.
        logger?.log(.info("Rebuilding GSfsys.toc"))
        let tocOutputFile = outputFolder.file("files/" + self.data.fsys.GSfsysFile.fileName)
        do {
            let tocData = try buildGSfsysTOC(
                fstRegistryFile: fstRegistryFile,
                sourceFolder: sourceFolder,
                            fileSystem: fileSystem
            )
            try fileSystem.writeFile(tocData, at: tocOutputFile, overwrite: true)
            logger?.log(.info("Wrote \(tocOutputFile.fileName) (\(tocData.length) bytes)"))
        } catch {
            recordFailure(tocOutputFile.fileName, error)
        }

        guard failures.isEmpty else {
            logger?.log(.taskStatus(taskName: "Build Colosseum/XD File System", status: .completed(false)))
            throw FSYSPipelineError.packFailures(failures, .init())
        }

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
    /// Members of the project that couldn't be packed. The build works
    /// through the whole file system and reports them together at the end,
    /// so one bad archive costs its own file rather than the rest of the
    /// disc, and one run names everything that needs fixing.
    case packFailures([String], ErrorTrace)
    /// A texture artifact that couldn't be read back as an image. The entry
    /// is not packed: writing the PNG's own bytes where the game expects a
    /// texture would produce an archive that builds cleanly and is wrong.
    case unreadableTexturePNG(File, ErrorTrace)
    /// A texture artifact read fine but wouldn't re-encode to the format the
    /// registry recorded for it — usually because its dimensions no longer
    /// match what that entry's metadata declares.
    case textureEncodeFailed(File, String, ErrorTrace)

    public var description: String {
        switch self {
        case let .missingTableOfContents(file, errorTrace):
            return "Error: Couldn't read the FSYS table of contents at \(file)\n\(errorTrace)"
        case let .missingStructDefinition(name, errorTrace):
            return "Error: No struct definition '\(name)' supplied to reassemble a data-table entry.\n\(errorTrace)"
        case let .unreadableTexturePNG(file, errorTrace):
            return "Error: Couldn't read \(file.path) as a PNG, so the texture it stands for can't be rebuilt.\n\(errorTrace)"
        case let .textureEncodeFailed(file, format, errorTrace):
            return "Error: Couldn't re-encode \(file.path) as \(format) — check its dimensions match the entry's metadata.\n\(errorTrace)"
        case let .packFailures(failures, errorTrace):
            let listed = failures.prefix(20).joined(separator: "\n  ")
            let rest = failures.count > 20 ? "\n  …and \(failures.count - 20) more" : ""
            return "Error: \(failures.count) file\(failures.count == 1 ? "" : "s") couldn't be packed. "
                + "Everything else was written.\n  \(listed)\(rest)\n\(errorTrace)"
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
        // The dump recorded what the packer puts in a record's gaps, because
        // the CSV can't: padding has no column, so a row rebuilt from one is
        // zero there and the table would differ from the disc in every entry
        // that has a gap (14 of Battle Revolution's 33 tables do).
        let rows = try StructTableCSV.decode(
            csvText, definition: entryDefinition, byteOrder: .big,
            paddingFills: dataTable.entryPaddingFills ?? []
        ).entries

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
