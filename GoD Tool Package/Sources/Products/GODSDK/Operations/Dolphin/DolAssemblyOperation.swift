import Foundation
import GoDFoundation
import Dolphin
import Disassembler
import Structs

enum DolAssembly {
    static func assemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)

        logger?.log(.info("Assembling DOL from \(config.codeFolder.path)"))
        logger?.log(.taskStatus(taskName: "Assemble DOL", status: .started))

        // Read sections.txt for layout info
        let sectionsFile = config.codeFolder.file("sections.txt")
        guard let sectionsData = fileSystem.readFile(at: sectionsFile) else {
            throw DolAssemblyErrors.sectionsFileNotFound(file: sectionsFile, .init())
        }
        let layoutParser = SectionLayoutParser()
        let layout = layoutParser.parse(sectionsData.string(format: .utf8))

        let assembler = PPCSectionAssembler()
        let manifestReader = ManifestReader()

        // Struct definitions for typed (.struct/.table) chunk import,
        // resolved from the type map's engine list — the same resolver
        // the dump side uses.
        var resolvedStructs = [String: StructDefinition]()
        if let typeMapPath = config.typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath) {
            if let typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData) {
                resolvedStructs = resolveStructTypes(
                    from: typeMap,
                    engineFolders: config.engines ?? [],
                    fileSystem: fileSystem,
                    logger: logger
                )
                logger?.log(.info("Resolved \(resolvedStructs.count) struct types for typed data import"))
            } else {
                logger?.log(.warning("Could not decode type map at \(typeMapPath.path) — typed chunks will use .bin sidecars"))
            }
        }

        // Pre-scan: collect all labels from all sections to build the
        // global symbol table. Typed chunks are rendered with an empty
        // label table here — pointer values may be wrong (auto lbl_
        // names still resolve intrinsically), but sizes and label
        // placement are definition-driven and already final, which is
        // all this pass needs.
        var globalSymbols = [String: UInt32]()
        let prescanLabelTable = LabelTable()

        var prescanDataFiles = [String: [(name: String, content: String)]]()
        for section in layout.dataSections {
            prescanDataFiles[section.name] = collectDataSectionFiles(
                section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader,
                structs: resolvedStructs,
                labelTable: prescanLabelTable,
                registry: registry,
                logger: nil
            )
        }

        for section in layout.textSections {
            let files = manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem
            )
            let labels = assembler.collectLabelsOnly(files: files, baseAddress: section.address)
            globalSymbols.merge(labels) { existing, _ in existing }
        }
        for section in layout.dataSections {
            let files = prescanDataFiles[section.name] ?? []
            let labels = assembler.collectLabelsOnly(files: files, baseAddress: section.address)
            globalSymbols.merge(labels) { existing, _ in existing }
        }

        // Scan all section files (text AND data) for lbl_XXXXXXXX
        // references that point to BSS or interior chunk offsets not
        // emitted as a chunk header. Pure address-derived labels
        // resolve to themselves, so we infer them from the literal name.
        func absorbLblReferences(_ files: [(name: String, content: String)]) {
            for (_, content) in files {
                for line in content.split(separator: "\n") {
                    let s = String(line)
                    var searchStart = s.startIndex
                    while let range = s.range(of: "lbl_", range: searchStart..<s.endIndex) {
                        let hexStart = range.upperBound
                        let hexEnd = s.index(hexStart, offsetBy: 8, limitedBy: s.endIndex) ?? s.endIndex
                        if s.distance(from: hexStart, to: hexEnd) == 8 {
                            let hexStr = String(s[hexStart..<hexEnd])
                            let label = "lbl_" + hexStr
                            if globalSymbols[label] == nil,
                               let addr = UInt32(hexStr, radix: 16) {
                                globalSymbols[label] = addr
                            }
                        }
                        searchStart = range.upperBound
                    }
                }
            }
        }
        for section in layout.textSections {
            absorbLblReferences(manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem
            ))
        }
        for section in layout.dataSections {
            absorbLblReferences(prescanDataFiles[section.name] ?? [])
        }

        // Load symbol map for external references (exception handlers, etc.)
        if let symbolMapPath = config.symbolMapPath,
           let mapData = fileSystem.readFile(at: symbolMapPath) {
            let parser = SymbolMapParser()
            let symbols = parser.parse(mapData.string(format: .utf8))
            for sym in symbols where globalSymbols[sym.name] == nil {
                globalSymbols[sym.name] = sym.address
            }
        }

        // Load BSS entry list and assign addresses
        if let bssPath = config.bssEntryListPath,
           let bssData = fileSystem.readFile(at: bssPath) {
            if let bssList = try? JSONDecoder().decode(BSSEntryList.self, from: bssData) {
                let assigned = bssList.assignAddresses(baseAddress: layout.bssAddress)
                for entry in assigned {
                    if globalSymbols[entry.label] == nil {
                        globalSymbols[entry.label] = entry.address
                    }
                }
                logger?.log(.info("Loaded \(assigned.count) BSS entries"))
            }
        }

        logger?.log(.info("Collected \(globalSymbols.count) global symbols"))

        // Final label table for typed chunk pointer resolution — now
        // that every section, symbol map, and BSS label has an address.
        let labelTable = LabelTable()
        labelTable.mergeLabels(globalSymbols)

        var textSections = [Dol.TextSection]()
        var dataSections = [Dol.DataSection]()

        let totalSections = layout.textSections.count + layout.dataSections.count
        var sectionsProcessed = 0

        // Assemble text sections
        for section in layout.textSections {
            let files = manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem
            )

            if !files.isEmpty {
                let assembled = try assembler.assemble(files: files, baseAddress: section.address, externalSymbols: globalSymbols)
                textSections.append(.init(RAMAddress: section.address, assembly: assembled))
            } else {
                textSections.append(.init(RAMAddress: section.address, assembly: .none))
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Assemble DOL", status: .progress(pct)))
            }
        }

        // Assemble data sections — re-render typed chunks with the
        // final label table so pointer fields carry real addresses.
        for section in layout.dataSections {
            let files = collectDataSectionFiles(
                section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader,
                structs: resolvedStructs,
                labelTable: labelTable,
                registry: registry,
                logger: logger
            )
            if !files.isEmpty {
                let assembled = try assembler.assemble(files: files, baseAddress: section.address, externalSymbols: globalSymbols)
                dataSections.append(.init(RAMAddress: section.address, data: assembled))
            } else {
                dataSections.append(.init(RAMAddress: section.address, data: .none))
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Assemble DOL", status: .progress(pct)))
            }
        }

        // Section overlap detection
        var assembledRanges = [(name: String, start: UInt32, end: UInt32)]()
        for (i, section) in textSections.enumerated() where section.assembly.length > 0 {
            let name = layout.textSections[i].name
            let start = layout.textSections[i].address
            let end = start + UInt32(section.assembly.length)
            assembledRanges.append((name: name, start: start, end: end))
        }
        for (i, section) in dataSections.enumerated() where section.data.length > 0 {
            let name = layout.dataSections[i].name
            let start = layout.dataSections[i].address
            let end = start + UInt32(section.data.length)
            assembledRanges.append((name: name, start: start, end: end))
        }
        for i in 0..<assembledRanges.count {
            for j in (i+1)..<assembledRanges.count {
                let a = assembledRanges[i]
                let b = assembledRanges[j]
                if a.start < b.end && b.start < a.end {
                    logger?.log(.warning("Section overlap detected: \(a.name) (0x\(String(a.start, radix: 16))-0x\(String(a.end, radix: 16))) overlaps with \(b.name) (0x\(String(b.start, radix: 16))-0x\(String(b.end, radix: 16)))"))
                }
            }
        }

        // SDA guard rail: r13/r2-relative accesses (small data area) use
        // fixed 16-bit displacements that never go through the label table.
        // If a section holding small data changes size, every access past
        // the change point silently reads/writes the wrong location.
        let sdaBases = resolveSDABases(config: config, assembledTextSections: textSections)
        if !sdaBases.isEmpty {
            for (i, section) in dataSections.enumerated() where section.data.length > 0 {
                let info = layout.dataSections[i]
                guard let recordedSize = info.size else { continue }
                let assembledSize = UInt32(section.data.length)
                guard assembledSize != recordedSize else { continue }

                let start = info.address
                let end = info.address &+ max(recordedSize, assembledSize)
                for (name, base) in sdaBases {
                    let windowStart = base &- 0x8000
                    let windowEnd = base &+ 0x7FFF
                    if start <= windowEnd && end > windowStart {
                        logger?.log(.warning("""
                        \(info.name) changed size (\(recordedSize) -> \(assembledSize) bytes) and lies in the \
                        \(name) small-data window (0x\(String(windowStart, radix: 16))-0x\(String(windowEnd, radix: 16))). \
                        r13/r2-relative accesses use fixed displacements that do NOT shift — \
                        this rebuild is almost certainly game-breaking. Revert the size change in this section.
                        """))
                    }
                }
            }
        }

        // Build DOL
        let dol = Dol(
            dolphinEngine: dolphinEngine,
            textSections: textSections,
            dataSections: dataSections,
            bssRAMAddress: layout.bssAddress,
            bssSize: layout.bssSize,
            entryPoint: layout.entryPoint
        )

        let dolData = try dol.data
        try fileSystem.writeFile(dolData, at: config.outputDolPath, overwrite: true)

        logger?.log(.taskStatus(taskName: "Assemble DOL", status: .completed(true)))
        logger?.log(.info("DOL written to \(config.outputDolPath.path) (\(dolData.length) bytes)"))
    }

    /// Collect assembly files for a data section.
    ///
    /// With a manifest, every chunk is walked in manifest order:
    /// - `.assembly` chunks pass their `.s` content through untouched.
    /// - `.binary` chunks re-emit their raw bytes as `.byte` directives
    ///   so the PPC assembler reproduces them in place.
    /// - `.file` chunks rebuild their binary through the format registry
    ///   when the dump routed them there (per-chunk artifact subfolder),
    ///   falling back to raw bytes otherwise, then re-emit as `.byte`
    ///   directives the same way.
    /// - `.struct` / `.table` chunks decode their human-editable JSON
    ///   via `StructData(definition:json:)`, resolve label fields to
    ///   addresses through `labelTable`, and re-emit the resulting
    ///   bytes the same way — so JSON edits land in the built DOL.
    ///   The JSON is the only source; a chunk whose JSON is missing
    ///   or undecodable is dropped with a warning.
    private static func collectDataSectionFiles(
        _ sectionName: String,
        codeFolder: Folder,
        fileSystem: FileSystemTree,
        manifestReader: ManifestReader,
        structs: [String: StructDefinition],
        labelTable: LabelTable,
        registry: FileFormatRegistry,
        logger: Logger?
    ) -> [(name: String, content: String)] {
        let sectionFolder = codeFolder.folder(sectionName)

        if let manifest = manifestReader.readDataManifest(from: sectionFolder, fileSystem: fileSystem) {
            var files = [(name: String, content: String)]()
            for chunk in manifest.chunks {
                let file = sectionFolder.file(chunk.file)
                switch chunk.type {
                case .assembly:
                    if let data = fileSystem.readFile(at: file) {
                        files.append((name: chunk.file, content: data.string(format: .utf8)))
                    } else {
                        logger?.log(.warning("Assembly chunk '\(chunk.label)' dropped: \(chunk.file) missing — section \(sectionName) will come out short"))
                    }
                case .binary:
                    if let data = fileSystem.readFile(at: file) {
                        files.append((
                            name: "\(chunk.label).synthesized.s",
                            content: renderByteBlocksAsAssembly(
                                sectionName: sectionName,
                                chunkLabel: chunk.label,
                                blocks: [(label: nil, bytes: data)]
                            )
                        ))
                    } else {
                        logger?.log(.warning("Binary chunk '\(chunk.label)' dropped: \(chunk.file) missing — section \(sectionName) will come out short"))
                    }
                case .file:
                    if let data = fileChunkBinary(
                        chunk: chunk,
                        sectionFolder: sectionFolder,
                        fileSystem: fileSystem,
                        registry: registry,
                        logger: logger
                    ) {
                        files.append((
                            name: "\(chunk.label).synthesized.s",
                            content: renderByteBlocksAsAssembly(
                                sectionName: sectionName,
                                chunkLabel: chunk.label,
                                blocks: [(label: nil, bytes: data)]
                            )
                        ))
                    } else {
                        logger?.log(.warning("File chunk '\(chunk.label)' dropped: no rebuildable artifacts for \(chunk.file) — section \(sectionName) will come out short"))
                    }
                case .struct, .table:
                    if let rendered = renderTypedChunkAssembly(
                        chunk: chunk,
                        sectionName: sectionName,
                        sectionFolder: sectionFolder,
                        fileSystem: fileSystem,
                        structs: structs,
                        labelTable: labelTable,
                        logger: logger
                    ) {
                        files.append(rendered)
                    } else {
                        logger?.log(.warning("Typed chunk '\(chunk.label)' dropped: JSON missing or undecodable — section \(sectionName) will come out short"))
                    }
                }
            }
            return files
        }

        // Fall back to folder with .s files
        if fileSystem.inspectFolder(at: sectionFolder) != nil {
            return collectAssemblyFiles(from: sectionFolder, fileSystem: fileSystem)
        }

        // Fall back to single file
        let sectionFile = codeFolder.file("\(sectionName).s")
        if let data = fileSystem.readFile(at: sectionFile) {
            return [(sectionName + ".s", data.string(format: .utf8))]
        }
        return []
    }

    /// Resolve the small-data-area base addresses (r13 = _SDA_BASE_,
    /// r2 = _SDA2_BASE_). Explicit config values win; otherwise scan the
    /// assembled text for the canonical __init_registers sequence —
    /// `lis r13/r2, hi` followed by `ori`/`addi` with the same register as
    /// source and destination. r2/r13 are ABI-reserved, so the pattern is
    /// unambiguous.
    private static func resolveSDABases(
        config: Config,
        assembledTextSections: [Dol.TextSection]
    ) -> [(name: String, address: UInt32)] {
        var bases = [(name: String, address: UInt32)]()
        if let r13 = config.sdaBase { bases.append((name: "_SDA_BASE_ (r13)", address: r13)) }
        if let r2 = config.sda2Base { bases.append((name: "_SDA2_BASE_ (r2)", address: r2)) }
        if !bases.isEmpty { return bases }

        var pendingHi = [UInt8: UInt32]()   // register → high immediate
        var found = [UInt8: UInt32]()       // register → full base address

        for section in assembledTextSections where section.assembly.length > 0 {
            let bytes = section.assembly.rawBytes
            var offset = 0
            while offset + 3 < bytes.count, found.count < 2 {
                let word = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                         | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
                let opcode = word >> 26
                let rd = UInt8((word >> 21) & 0x1F)
                let ra = UInt8((word >> 16) & 0x1F)
                let imm = word & 0xFFFF

                if opcode == 15, ra == 0, rd == 2 || rd == 13 {
                    // lis r2/r13, hi
                    pendingHi[rd] = imm
                } else if opcode == 24, rd == ra, let hi = pendingHi[rd], found[rd] == nil {
                    // ori rX, rX, lo — unsigned lower half
                    found[rd] = (hi << 16) | imm
                } else if opcode == 14, rd == ra, let hi = pendingHi[rd], found[rd] == nil {
                    // addi rX, rX, lo — sign-extended lower half
                    let lo = Int32(Int16(bitPattern: UInt16(imm)))
                    found[rd] = UInt32(truncatingIfNeeded: Int(hi << 16) + Int(lo))
                }
                offset += 4
            }
            if found.count == 2 { break }
        }

        if let r13 = found[13] { bases.append((name: "_SDA_BASE_ (r13)", address: r13)) }
        if let r2 = found[2] { bases.append((name: "_SDA2_BASE_ (r2)", address: r2)) }
        return bases
    }

    /// Produce the raw binary for a `.file` chunk. Registry-dumped
    /// chunks live as structured artifacts (JSON / PNG / …) in a
    /// per-chunk subfolder named after the chunk label — rebuild the
    /// original bytes through the format handler so artifact edits land
    /// in the built DOL. Chunks dumped as raw bytes (unregistered
    /// extension, or a dump-time registry failure) read straight from
    /// the manifest's file.
    private static func fileChunkBinary(
        chunk: DataSectionManifest.Chunk,
        sectionFolder: Folder,
        fileSystem: FileSystemTree,
        registry: FileFormatRegistry,
        logger: Logger?
    ) -> GoDData? {
        if let ext = chunk.fileExtension, registry.isRegistered(ext) {
            let chunkFolder = sectionFolder.folder(chunk.label)
            if fileSystem.inspectFolder(at: chunkFolder) != nil {
                do {
                    return try registry.buildSingle(extension: ext, from: chunkFolder, fileSystem: fileSystem)
                } catch {
                    logger?.log(.warning("Registry build failed for file chunk '\(chunk.label)' (.\(ext)): \(error). Falling back to raw bytes."))
                }
            }
        }
        return fileSystem.readFile(at: sectionFolder.file(chunk.file))
    }

    /// Decode a `.struct` or `.table` chunk's JSON and render the
    /// imported bytes as synthetic assembly. Returns nil when the JSON
    /// is missing, its struct type is unresolved, or decoding fails —
    /// the caller drops the chunk with a warning.
    private static func renderTypedChunkAssembly(
        chunk: DataSectionManifest.Chunk,
        sectionName: String,
        sectionFolder: Folder,
        fileSystem: FileSystemTree,
        structs: [String: StructDefinition],
        labelTable: LabelTable,
        logger: Logger?
    ) -> (name: String, content: String)? {
        guard let structType = chunk.structType else {
            logger?.log(.warning("Typed chunk '\(chunk.label)' has no structType in the manifest"))
            return nil
        }
        guard let definition = structs[structType] else {
            logger?.log(.warning("Struct type '\(structType)' for chunk '\(chunk.label)' not resolved — is typeMapPath set in the config?"))
            return nil
        }
        guard let jsonData = fileSystem.readFile(at: sectionFolder.file(chunk.file)) else {
            return nil
        }
        let importer = TypedDataImporter()

        switch chunk.type {
        case .struct:
            do {
                let structData = try StructData(definition: definition, json: jsonData, byteOrder: .big)
                let bytes = importer.importStruct(structData: structData, labelTable: labelTable, byteOrder: .big)
                return (
                    name: "\(chunk.label).synthesized.s",
                    content: renderByteBlocksAsAssembly(
                        sectionName: sectionName,
                        chunkLabel: chunk.label,
                        blocks: [(label: nil, bytes: bytes)]
                    )
                )
            } catch {
                logger?.log(.warning("Struct chunk '\(chunk.label)' JSON failed to decode: \(error)"))
                return nil
            }

        case .table:
            guard let root = try? JSONSerialization.jsonObject(with: jsonData.data) as? [String: Any],
                  let entryDicts = root["entries"] as? [[String: Any]] else {
                logger?.log(.warning("Table chunk '\(chunk.label)' JSON is not in the expected {structType, entries} shape"))
                return nil
            }
            // Pad-or-truncate to the manifest's declared count so the
            // section layout stays stable even if the JSON was
            // hand-edited to add/remove rows.
            let count = chunk.count ?? entryDicts.count
            if entryDicts.count > count {
                logger?.log(.warning("Table '\(chunk.label)': \(entryDicts.count - count) surplus entries dropped (manifest count is \(count))"))
            } else if entryDicts.count < count {
                logger?.log(.warning("Table '\(chunk.label)': \(count - entryDicts.count) missing entries zero-filled (manifest count is \(count))"))
            }

            var blocks = [(label: String?, bytes: GoDData)]()
            for i in 0..<count {
                guard i < entryDicts.count else {
                    blocks.append((label: nil, bytes: GoDData(length: definition.length, byteOrder: .big)))
                    continue
                }
                var fields = entryDicts[i]
                let entryLabel = fields.removeValue(forKey: "_label") as? String
                do {
                    // Wrap the flat entry into the {type, data} shape
                    // StructData's schema-aware decoder expects.
                    let wrapped: [String: Any] = ["type": definition.name, "data": fields]
                    let wrappedBytes = try JSONSerialization.data(withJSONObject: wrapped)
                    let structData = try StructData(
                        definition: definition,
                        json: GoDData(byteStream: [UInt8](wrappedBytes), byteOrder: .big),
                        byteOrder: .big
                    )
                    let bytes = importer.importStruct(structData: structData, labelTable: labelTable, byteOrder: .big)
                    blocks.append((label: entryLabel, bytes: bytes))
                } catch {
                    logger?.log(.warning("Table '\(chunk.label)' entry \(i) failed to decode: \(error)"))
                    return nil
                }
            }
            return (
                name: "\(chunk.label).synthesized.s",
                content: renderByteBlocksAsAssembly(
                    sectionName: sectionName,
                    chunkLabel: chunk.label,
                    blocks: blocks
                )
            )

        case .assembly, .binary, .file:
            return nil
        }
    }

    // MARK: - Collect .s files recursively (backwards compat)

    private static func collectAssemblyFiles(
        from folder: Folder,
        fileSystem: FileSystemTree
    ) -> [(name: String, content: String)] {
        guard let contents = fileSystem.inspectFolder(at: folder) else { return [] }

        var files = [(name: String, content: String)]()

        for file in contents.files where file.fileType == "s" {
            if let data = fileSystem.readFile(at: file) {
                files.append((name: file.fileName, content: data.string(format: .utf8)))
            }
        }

        for subFolder in contents.subFolders {
            files.append(contentsOf: collectAssemblyFiles(from: subFolder, fileSystem: fileSystem))
        }

        return files
    }
}

/// Wraps one or more labelled byte blocks in a `.section` + label +
/// `.byte` directive block that the PPC assembler can ingest. Interior
/// block labels (e.g. table entry labels) are emitted between byte
/// runs so they land at the right addresses during label collection.
private func renderByteBlocksAsAssembly(
    sectionName: String,
    chunkLabel: String,
    blocks: [(label: String?, bytes: GoDData)]
) -> String {
    // The PPC assembler's `.byte` directive consumes exactly one byte
    // per line (PPCAssemblyParser.swift:81-89) — comma-separated forms
    // are silently parsed as `.empty`. Emit one directive per byte to
    // match.
    var lines: [String] = []
    lines.append(".section .\(sectionName)")
    lines.append("")
    lines.append(".global \(chunkLabel)")
    lines.append("\(chunkLabel):")
    for block in blocks {
        if let label = block.label, label != chunkLabel {
            lines.append("\(label):")
        }
        for b in block.bytes.byteStream {
            lines.append(String(format: "    .byte 0x%02X", b))
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}

enum DolAssemblyErrors: Error, CustomStringConvertible {
    case sectionsFileNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .sectionsFileNotFound(file, trace):
            return "sections.txt not found: \(file)\n\(trace)"
        }
    }
}
