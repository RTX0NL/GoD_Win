import GoDFoundation
import Dolphin
import Disassembler
import Structs
import XD
import Colosseum
import GeniusSonority

extension DolDisassembly {
    static func disassemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)

        guard let dolData = fileSystem.readFile(at: config.dolPath) else {
            throw DolDisassemblyErrors.dolNotFound(file: config.dolPath, .init())
        }

        let dol = try Dol(data: dolData, dolphinEngine: dolphinEngine)
        let decoder = PPCDecoder()
        let formatter = PPCFormatter()

        // Load symbol map if available
        var allSymbols = [PPCSymbol]()
        var symbolLookup = [UInt32: String]()
        if let symbolMapPath = config.symbolMapPath,
           let symbolData = fileSystem.readFile(at: symbolMapPath) {
            let text = symbolData.string(format: .utf8)
            let parser = SymbolMapParser()
            allSymbols = parser.parse(text)
            symbolLookup = parser.buildLookup(allSymbols)
            logger?.log(.info("Loaded \(allSymbols.count) symbols from \(symbolMapPath.fileName)"))
        }

        let hasSymbols = !allSymbols.isEmpty
        let outputFolder = Folder("/")

        // Build section address ranges for relocation analysis (including BSS)
        var sectionRanges: [(start: UInt32, end: UInt32)] =
            dol.textSections.filter { $0.assembly.length > 0 }.map {
                (start: $0.RAMAddress, end: $0.RAMAddress + UInt32($0.assembly.length))
            } +
            dol.dataSections.filter { $0.data.length > 0 }.map {
                (start: $0.RAMAddress, end: $0.RAMAddress + UInt32($0.data.length))
            }
        if dol.bssSize > 0 {
            sectionRanges.append((start: dol.bssRAMAddress, end: dol.bssRAMAddress + dol.bssSize))
        }

        // Always shiftable — relocation analysis runs regardless of symbol map
        logger?.log(.info("Disassembling DOL (always-shiftable mode\(hasSymbols ? ", with symbols" : ""))"))
        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .started))

        // Build everything in memory first
        let output = InMemoryFST()
        let relocAnalyzer = PPCRelocAnalyzer()

        let textSections = dol.textSections.enumerated().filter { $0.element.assembly.length > 0 }
        let dataSections = dol.dataSections.enumerated().filter { $0.element.data.length > 0 }
        let totalSections = textSections.count + dataSections.count
        var sectionsProcessed = 0

        // Collect all relocation targets from text sections (for data pointer scanning)
        var confirmedTargets = Set<UInt32>()

        // Pass 1: decode + analyze every text section so branch targets in
        // OTHER text sections (e.g. _savegpr_/_restgpr_ millicode in text0
        // called from text1) can be named and resolved through the label
        // table instead of freezing to literal addresses on reassembly.
        var decodedTextSections = [(index: Int, section: Dol.TextSection, instructions: [PPCInstruction], relocations: [UInt32: PPCRelocation])]()
        var allBranchTargets = Set<UInt32>()
        let textRanges: [(start: UInt32, end: UInt32)] = textSections.map {
            (start: $0.element.RAMAddress, end: $0.element.RAMAddress + UInt32($0.element.assembly.length))
        }

        for (index, section) in textSections {
            let bytes = section.assembly.rawBytes
            let instructions = decoder.decodeAll(bytes, baseAddress: section.RAMAddress)

            // Always run relocation analysis for shiftable output
            let relocations = relocAnalyzer.analyze(
                instructions,
                symbols: symbolLookup,
                sectionRanges: sectionRanges
            )

            // Collect confirmed relocation targets for data pointer scanning
            for (_, reloc) in relocations {
                confirmedTargets.insert(reloc.targetAddress)
            }

            allBranchTargets.formUnion(formatter.collectBranchTargets(instructions))
            decodedTextSections.append((index: index, section: section, instructions: instructions, relocations: relocations))
        }

        // Shared label names for every branch target that lands in any text
        // section: map name when known, else an auto label. Passed to the
        // formatter both to render cross-section targets symbolically and to
        // emit definitions at externally-referenced addresses.
        var textBranchLabels = [UInt32: String]()
        for target in allBranchTargets where target % 4 == 0 {
            if textRanges.contains(where: { target >= $0.start && target < $0.end }) {
                textBranchLabels[target] = symbolLookup[target] ?? "lbl_\(String(format: "%08X", target))"
            }
        }

        // Pass 2: format and write each text section
        for (index, section, instructions, relocations) in decodedTextSections {
            let sectionName = "text\(index)"
            let sectionEnd = section.RAMAddress + UInt32(section.assembly.length)

            if hasSymbols {
                let sectionSymbols = allSymbols.filter {
                    $0.address >= section.RAMAddress && $0.address < sectionEnd
                }

                if !sectionSymbols.isEmpty {
                    // Split into per-function files organized by source object file
                    let sectionFolder = outputFolder.folder(sectionName)
                    let functions = formatter.splitByFunction(instructions, symbols: sectionSymbols, relocations: relocations, sectionName: ".\(sectionName)", extraLabels: textBranchLabels)

                    let symbolFileMap = Dictionary(
                        sectionSymbols.compactMap { sym -> (String, String)? in
                            guard let objFile = sym.objectFileName else { return nil }
                            return (sym.name, objFile)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )

                    // Track file paths for manifest
                    var manifestFiles = [String]()

                    for function in functions {
                        let subfolder: Folder
                        let relativePath: String
                        if let objFile = symbolFileMap[function.name] {
                            subfolder = sectionFolder.folder(objFile)
                            relativePath = "\(objFile)/\(function.name).s"
                        } else {
                            subfolder = sectionFolder
                            relativePath = "\(function.name).s"
                        }
                        let file = subfolder.file("\(function.name).s")
                        try output.writeFile(GoDData(string: function.text, format: .utf8), at: file, overwrite: true)
                        manifestFiles.append(relativePath)
                    }

                    // Write text section manifest for ordering
                    let manifest = TextSectionManifest(section: sectionName, files: manifestFiles)
                    if let manifestJSON: GoDData = try? JSONEncoder().encode(manifest) {
                        try output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
                    }
                } else {
                    // Symbols exist but none in this section — single file with relocations
                    let text = formatter.formatAssembly(instructions, relocations: relocations, sectionName: ".\(sectionName)", extraLabels: textBranchLabels)
                    let file = outputFolder.file("\(sectionName).s")
                    try output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
                }
            } else {
                // No symbol map — single file with auto-generated labels + relocations
                let text = formatter.formatAssembly(instructions, relocations: relocations, sectionName: ".\(sectionName)", extraLabels: textBranchLabels)
                let file = outputFolder.file("\(sectionName).s")
                try output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Run data pointer scanning across all data sections
        let dataPointerScanner = DataPointerScanner()
        let dataSectionInputs = dataSections.map { (_, section) in
            (baseAddress: section.RAMAddress, data: section.data.rawBytes)
        }
        let dataPointerResults = dataPointerScanner.scanAllSections(
            dataSections: dataSectionInputs,
            initialConfirmedTargets: confirmedTargets,
            sectionRanges: sectionRanges
        )

        // Build combined address → label lookup (symbols + auto-generated)
        var addressToLabel = symbolLookup
        // Add confirmed targets as auto-labels if not already named
        for target in confirmedTargets where addressToLabel[target] == nil {
            addressToLabel[target] = "lbl_\(String(format: "%08X", target))"
        }
        // Add data pointer targets. Misaligned targets are overwhelmingly
        // garbage words inside binary blobs that happen to look like
        // pointers — minting labels for them splits chunks at nonsense
        // boundaries and scrambles the word grid of everything after. Only
        // aligned targets earn a label; code-referenced targets (reloc
        // analysis above) are exempt since odd string addresses are real.
        var skippedMisalignedTargets = Set<UInt32>()
        for sectionPointers in dataPointerResults {
            for (_, target) in sectionPointers where addressToLabel[target] == nil {
                if target % 4 == 0 {
                    addressToLabel[target] = "lbl_\(String(format: "%08X", target))"
                } else {
                    skippedMisalignedTargets.insert(target)
                }
            }
        }
        if !skippedMisalignedTargets.isEmpty {
            logger?.log(.info("Skipped \(skippedMisalignedTargets.count) misaligned data-pointer targets (likely blob false positives)"))
        }

        // Load type map if provided
        var typeMap: TypeMap?
        var resolvedStructs = [String: StructDefinition]()
        if let typeMapPath = config.typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath) {
            typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData)
            if let tm = typeMap {
                logger?.log(.info("Loaded type map with \(tm.chunks.count) chunks"))
                // Build a simple struct resolver from XD engine structs
                // The type map references struct names which we look up
                resolvedStructs = resolveStructTypes(from: tm, engineFolders: config.engines ?? [], fileSystem: fileSystem, logger: logger)
            }
        }

        // Data sections — always shiftable with pointer labels
        let assemblyExporter = AssemblyTextExporter()

        for (sectionIndex, (index, section)) in dataSections.enumerated() {
            let sectionName = "data\(index)"
            let bytes = section.data.rawBytes
            let baseAddress = section.RAMAddress
            let sectionEnd = baseAddress + UInt32(bytes.count)

            // Build label map for this section (offset → label name).
            // Misaligned labels (odd string addresses, byte globals) are NOT
            // used as chunk boundaries: a chunk starting off the 4-byte grid
            // renders every following word misaligned, hiding real pointers
            // from symbolization. Such labels stay inside their covering
            // chunk; references to them resolve via the literal-hex
            // fallback (byte-correct, not shiftable).
            var sectionLabels = [Int: String]()
            var misalignedLabels = [String]()
            for (addr, name) in addressToLabel {
                if addr >= baseAddress && addr < sectionEnd {
                    if addr % 4 == 0 {
                        sectionLabels[Int(addr - baseAddress)] = name
                    } else {
                        misalignedLabels.append(name)
                    }
                }
            }
            if !misalignedLabels.isEmpty {
                let preview = misalignedLabels.sorted().prefix(5).joined(separator: ", ")
                logger?.log(.warning("\(sectionName): \(misalignedLabels.count) misaligned labels kept out of chunk boundaries (not shiftable): \(preview)\(misalignedLabels.count > 5 ? ", …" : "")"))
            }

            // Get pointer results for this section
            let sectionPointers = sectionIndex < dataPointerResults.count
                ? dataPointerResults[sectionIndex].reduce(into: [Int: UInt32]()) { result, pair in
                    result[Int(pair.key)] = pair.value
                }
                : [Int: UInt32]()

            // Build type map lookup for this section.
            // Map from the ACTUAL label name (from symbol map) to the TypeMap.Chunk.
            // The type map uses lbl_XXXXXXXX but the symbol map may have given a different name.
            var typeChunkByLabel = [String: TypeMap.Chunk]()
            if let tm = typeMap {
                for chunk in tm.chunks {
                    if let addr = chunkAddress(chunk, addressToLabel: addressToLabel),
                       addr >= baseAddress && addr < sectionEnd {
                        let offset = Int(addr - baseAddress)
                        // Use the actual label name at this offset (from symbol map)
                        if let actualLabel = sectionLabels[offset] {
                            typeChunkByLabel[actualLabel] = chunk
                        }
                    }
                }
            }

            // Split data section into chunks at every label boundary
            let sortedLabelOffsets = sectionLabels.keys.sorted()
            let sectionFolder = outputFolder.folder(sectionName)
            var manifest = DataSectionManifest(section: sectionName)

            let typedExporter = TypedDataExporter()
            var consumedUpTo = 0  // tracks how far we've consumed (for skipping inside tables)

            // Emit an untyped chunk covering [startOffset, endOffset):
            // .4byte assembly when the range contains confirmed pointers
            // (so they stay symbolic and shift with layout changes), raw
            // .bin otherwise. Shared by regular untyped chunks, the
            // pre-first-label region, typed-chunk fallbacks, and gap
            // bytes after typed chunks.
            func emitUntypedChunk(from startOffset: Int, to endOffset: Int, label labelName: String) {
                guard endOffset > startOffset else { return }
                let chunkBytes = Array(bytes[startOffset..<endOffset])
                let chunkPointers = sectionPointers
                    .filter { $0.key >= startOffset && $0.key < endOffset }
                    .reduce(into: [Int: UInt32]()) { $0[$1.key - startOffset] = $1.value }

                if !chunkPointers.isEmpty {
                    let fileName = "\(labelName).s"
                    let text = assemblyExporter.format(
                        data: chunkBytes,
                        baseAddress: baseAddress + UInt32(startOffset),
                        labels: [0: labelName],
                        pointers: chunkPointers,
                        addressToLabel: addressToLabel,
                        sectionName: ".\(sectionName)"
                    )
                    try? output.writeFile(GoDData(string: text, format: .utf8), at: sectionFolder.file(fileName), overwrite: true)
                    manifest.chunks.append(.init(label: labelName, type: .assembly, file: fileName))
                } else {
                    let fileName = "\(labelName).bin"
                    try? output.writeFile(GoDData(byteStream: chunkBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                    manifest.chunks.append(.init(label: labelName, type: .binary, file: fileName, size: chunkBytes.count))
                }
            }

            // Data before the first label (or the whole section when it
            // has no labels) goes through the same emission path so any
            // confirmed pointers in it stay symbolic.
            let firstLabelOffset = sortedLabelOffsets.first ?? bytes.count
            if firstLabelOffset > 0 {
                emitUntypedChunk(from: 0, to: firstLabelOffset, label: "lbl_\(String(format: "%08X", baseAddress))")
            }

            for (labelIdx, labelOffset) in sortedLabelOffsets.enumerated() {
                // Skip labels that fall inside a previously emitted table/file/struct
                guard labelOffset >= consumedUpTo else { continue }

                let labelName = sectionLabels[labelOffset]!
                let nextOffset = labelIdx + 1 < sortedLabelOffsets.count
                    ? sortedLabelOffsets[labelIdx + 1]
                    : bytes.count
                let chunkSize = nextOffset - labelOffset
                guard chunkSize > 0 else { continue }

                // Check if this label has a type map entry
                if let typeChunk = typeChunkByLabel[labelName] {
                    switch typeChunk {
                    case .table(let table):
                        let count = table.count ?? 0
                        guard let definition = resolvedStructs[table.entryType] else {
                            logger?.log(.warning("Unknown struct type '\(table.entryType)' for table '\(table.name)' — emitting as untyped chunk"))
                            emitUntypedChunk(from: labelOffset, to: nextOffset, label: labelName)
                            consumedUpTo = nextOffset
                            continue
                        }
                        let tableSize = min(definition.length * count, bytes.count - labelOffset)
                        let tableBytes = Array(bytes[labelOffset..<(labelOffset + tableSize)])
                        let tableData = GoDData(byteStream: tableBytes, byteOrder: .big)

                        let entryLabels = sectionLabels
                            .filter { $0.key >= labelOffset && $0.key < labelOffset + tableSize }
                            .map { (offset: $0.key - labelOffset, name: $0.value) }
                            .sorted(by: { $0.offset < $1.offset })

                        let entries = typedExporter.exportTable(
                            data: tableData,
                            definition: definition,
                            count: count,
                            entryLabels: entryLabels,
                            addressToLabel: addressToLabel
                        )

                        // JSON is the only artifact for typed chunks —
                        // no byte-identical sidecar. If encoding ever
                        // fails, demote the chunk to raw binary so the
                        // dump still rebuilds losslessly.
                        do {
                            let fileName = "\(table.name).json"
                            let json = try encodeBulkTableJSON(structType: table.entryType, entries: entries)
                            try output.writeFile(json, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: table.start, type: .table, file: fileName,
                                structType: table.entryType, count: count
                            ))
                        } catch {
                            logger?.log(.warning("Failed to encode table '\(table.name)' as JSON: \(error). Emitting as raw binary chunk."))
                            let binName = "\(table.name).bin"
                            try output.writeFile(tableData, at: sectionFolder.file(binName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: table.start, type: .binary, file: binName, size: tableSize
                            ))
                        }
                        consumedUpTo = labelOffset + tableSize

                    case .single(let single):
                        guard let definition = resolvedStructs[single.type] else {
                            logger?.log(.warning("Unknown struct type '\(single.type)' for '\(single.label)' — emitting as untyped chunk"))
                            emitUntypedChunk(from: labelOffset, to: nextOffset, label: labelName)
                            consumedUpTo = nextOffset
                            continue
                        }
                        let structSize = min(definition.length, bytes.count - labelOffset)
                        let structBytes = Array(bytes[labelOffset..<(labelOffset + structSize)])
                        let structData = typedExporter.exportStruct(
                            data: GoDData(byteStream: structBytes, byteOrder: .big),
                            definition: definition,
                            addressToLabel: addressToLabel
                        )

                        // Same policy as tables: JSON only, demote to a
                        // raw binary chunk if encoding fails.
                        do {
                            let fileName = "\(single.label).json"
                            let json: GoDData = try JSONEncoder.prettyPrinted.encode(structData)
                            try output.writeFile(json, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: single.label, type: .struct, file: fileName,
                                structType: single.type
                            ))
                        } catch {
                            logger?.log(.warning("Failed to encode struct '\(single.label)' as JSON: \(error). Emitting as raw binary chunk."))
                            let binName = "\(single.label).bin"
                            try output.writeFile(
                                GoDData(byteStream: structBytes, byteOrder: .big),
                                at: sectionFolder.file(binName),
                                overwrite: true
                            )
                            manifest.chunks.append(.init(
                                label: single.label, type: .binary, file: binName, size: structSize
                            ))
                        }
                        consumedUpTo = labelOffset + structSize

                    case .file(let embeddedFile):
                        let fileSize = min(embeddedFile.size, bytes.count - labelOffset)
                        let fileBytes = Array(bytes[labelOffset..<(labelOffset + fileSize)])
                        let fileData = GoDData(byteStream: fileBytes, byteOrder: .big)
                        let ext = embeddedFile.extension

                        if registry.isRegistered(ext) {
                            // Route through the file-format registry: dumps structured
                            // artifacts (JSON / PNG / atlas / etc.) instead of raw bytes.
                            // Each chunk gets its own subfolder so sibling chunks
                            // using the same format don't collide on filenames.
                            let chunkFolder = sectionFolder.folder(embeddedFile.label)
                            do {
                                let written = try registry.dump(
                                    bytes: fileData,
                                    extension: ext,
                                    into: chunkFolder,
                                    fileSystem: output,
                                    overwrite: true
                                )
                                let primary = written.first?.fileName
                                    ?? "\(embeddedFile.label).\(ext)"
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: primary,
                                    size: embeddedFile.size, fileExtension: ext
                                ))
                            } catch {
                                logger?.log(.warning("Registry dump failed for '\(embeddedFile.label)' (.\(ext)): \(error). Falling back to raw bytes."))
                                let fileName = "\(embeddedFile.label).\(ext)"
                                try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: fileName,
                                    size: embeddedFile.size, fileExtension: ext
                                ))
                            }
                        } else {
                            let fileName = "\(embeddedFile.label).\(ext)"
                            try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: embeddedFile.label, type: .file, file: fileName,
                                size: embeddedFile.size, fileExtension: ext
                            ))
                        }
                        consumedUpTo = labelOffset + fileSize
                    }

                    // Typed chunks consume their declared size, which
                    // may stop short of the next label (alignment
                    // padding, undocumented trailing bytes). Preserve
                    // the remainder so the rebuilt section isn't
                    // silently shortened.
                    let nextChunkOffset = sortedLabelOffsets.first(where: { $0 >= consumedUpTo && $0 > labelOffset }) ?? bytes.count
                    if consumedUpTo < nextChunkOffset {
                        let gapLabel = "lbl_\(String(format: "%08X", baseAddress + UInt32(consumedUpTo)))"
                        emitUntypedChunk(from: consumedUpTo, to: nextChunkOffset, label: gapLabel)
                    }
                } else {
                    // Untyped chunk — assembly if it has pointers, raw .bin otherwise
                    emitUntypedChunk(from: labelOffset, to: nextOffset, label: labelName)
                }
            }

            // Write manifest
            if let manifestJSON: GoDData = try? JSONEncoder.prettyPrinted.encode(manifest) {
                try output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Section layout summary
        let layoutWriter = SectionLayoutWriter()
        let layout = SectionLayout(
            entryPoint: dol.entryPoint,
            bssAddress: dol.bssRAMAddress,
            bssSize: dol.bssSize,
            textSections: textSections.map { (i, s) in
                .init(name: "text\(i)", address: s.RAMAddress, size: UInt32(s.assembly.length))
            },
            dataSections: dataSections.map { (i, s) in
                .init(name: "data\(i)", address: s.RAMAddress, size: UInt32(s.data.length))
            }
        )
        let summaryText = layoutWriter.write(layout, symbolCount: hasSymbols ? allSymbols.count : nil)
        try output.writeFile(GoDData(string: summaryText, format: .utf8), at: outputFolder.file("sections.txt"), overwrite: true)

        // Write everything to disk at once
        // Write into a subfolder named after the DOL file (e.g. "main" for "main.dol")
        let dolName = config.dolPath.fileName.components(separatedBy: ".").first ?? config.dolPath.fileName
        let targetFolder = config.outputFolder.folder(dolName)
        try fileSystem.importFST(output, from: outputFolder, to: targetFolder, overwrite: true)

        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .completed(true)))
    }
}

// MARK: - Type map helpers

private func resolveAutoLabel(_ name: String) -> UInt32? {
    if name.hasPrefix("lbl_"), name.count == 12 {
        return UInt32(String(name.dropFirst(4)), radix: 16)
    }
    return nil
}

private func chunkAddress(_ chunk: TypeMap.Chunk, addressToLabel: [UInt32: String]) -> UInt32? {
    let label: String
    switch chunk {
    case .table(let t): label = t.start
    case .single(let s): label = s.label
    case .file(let f): label = f.label
    }
    // Try exact lookup in reverse (label → address)
    if let entry = addressToLabel.first(where: { $0.value == label }) {
        return entry.key
    }
    // Try auto-label resolution
    return resolveAutoLabel(label)
}

/// Resolve the struct type names referenced by a type map into concrete
/// `StructDefinition`s, loading struct definitions from the given engine
/// folders (`<engine>/Structs/*.json`). The engine list is supplied by the
/// operation config rather than the type map. Falls back to the built-in XD
/// struct set when no engine folder yields any structs.
func resolveStructTypes(
    from typeMap: TypeMap,
    engineFolders: [Folder],
    fileSystem: FileSystemTree,
    logger: Logger?
) -> [String: StructDefinition] {
    // Collect all type names referenced in the type map
    var typeNames = Set<String>()
    for chunk in typeMap.chunks {
        switch chunk {
        case .table(let t): typeNames.insert(t.entryType)
        case .single(let s): typeNames.insert(s.type)
        case .file: break
        }
    }

    // Collect struct definitions from the config-supplied engine folders
    var allStructs = [StructMap]()
    for engineFolder in engineFolders {
        if let structs = loadEngineStructs(from: engineFolder, in: fileSystem) {
            allStructs.append(contentsOf: structs)
            logger?.log(.info("Loaded \(structs.count) structs from \(engineFolder.path)"))
        } else {
            logger?.log(.warning("Could not load engine at \(engineFolder.path)"))
        }
    }

    // Fall back to XD defaults if no engines loaded from filesystem
    if allStructs.isEmpty {
        allStructs = XDEngine.Structs.allItems
    }

    var resolved = [String: StructDefinition]()

    for typeName in typeNames {
        guard let structMap = allStructs.first(where: { $0.name == typeName }) else {
            logger?.log(.warning("Struct type '\(typeName)' not found in engines"))
            continue
        }
        do {
            let definition = try resolveStructMap(structMap, allStructs: allStructs)
            resolved[typeName] = definition
        } catch {
            logger?.log(.warning("Failed to resolve struct '\(typeName)': \(error)"))
        }
    }

    return resolved
}

private func loadEngineStructs(from folder: Folder, in fileSystem: FileSystemTree) -> [StructMap]? {
    let structsFolder = folder.folder("Structs")
    guard let contents = fileSystem.inspectFolder(at: structsFolder) else { return nil }
    var structs = [StructMap]()
    for file in contents.files where file.fileType == "json" {
        guard let data = fileSystem.readFile(at: file) else { continue }
        if let structMap = try? JSONDecoder().decode(StructMap.self, from: data) {
            structs.append(structMap)
        }
    }
    return structs.isEmpty ? nil : structs
}

private func resolveStructMap(_ map: StructMap, allStructs: [StructMap]) throws -> StructDefinition {
    func resolveField(_ field: StructField) throws -> StructProperty {
        switch field {
        case .primitive(let p): return .primitive(p)
        case .label: return .label
        case .padding(let n): return .padding(length: n)
        case .array(let f, let c): return .array(try resolveField(f), count: c)
        case .enumeration(let name):
            // For now, treat unknown enums as uint8
            return .primitive(.integer(.uint8))
        case .subStruct(let name):
            guard let sub = allStructs.first(where: { $0.name == name }) else {
                throw DolDisassemblyErrors.structNotFound(name: name, .init())
            }
            return .subStruct(try resolveStructMap(sub, allStructs: allStructs))
        }
    }

    return StructDefinition(
        name: map.name,
        wordSize: map.wordSize,
        alignmentStyle: map.alignmentStyle,
        properties: try map.properties.map { prop in
            .init(name: prop.name, type: try resolveField(prop.type), description: prop.description)
        },
        description: map.description
    )
}


/// Encode a table dump as `{"structType", "count", "entries": [...]}`.
///
/// Each entry reuses `StructData`'s own JSON field encoding — the same
/// shape `StructData(definition:json:)` decodes on the build side —
/// so arrays, sub-structs, char strings, enum case names, and
/// `padding_<i>` keys all round-trip. The entry's optional `_label`
/// is spliced into the field object.
///
/// Built via JSONSerialization because the entries are re-shaped
/// dictionaries; non-finite floats are already string sentinels
/// ("NaN"/"Infinity"/"-Infinity") from the per-entry JSONEncoder pass.
func encodeBulkTableJSON(structType: String, entries: [LabeledData]) throws -> GoDData {
    var entryDicts = [[String: Any]]()
    for entry in entries {
        let encoded: Data = try JSONEncoder.prettyPrinted.encode(entry.data)
        guard let obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var fields = obj["data"] as? [String: Any] else { continue }
        if let label = entry.label {
            fields["_label"] = label
        }
        entryDicts.append(fields)
    }
    let root: [String: Any] = [
        "structType": structType,
        "count": entryDicts.count,
        "entries": entryDicts,
    ]
    let bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    return GoDData(byteStream: [UInt8](bytes), byteOrder: .big)
}

private extension JSONEncoder {
    static let prettyPrinted: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return e
    }()
}

enum DolDisassemblyErrors: Error, CustomStringConvertible {
    case dolNotFound(file: File, ErrorTrace)
    case structNotFound(name: String, ErrorTrace)

    var description: String {
        switch self {
        case let .dolNotFound(file, trace):
            return "DOL file not found: \(file)\n\(trace)"
        case let .structNotFound(name, trace):
            return "Sub-struct '\(name)' not found\n\(trace)"
        }
    }
}
