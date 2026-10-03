//
//  DolDisassembler.swift
//  Dolphin
//
//  Turning a `.dol` into an editable source tree: instruction decode,
//  relocation analysis, function splitting, typed-data export and the section
//  layout summary.
//
//  This lived in `DolDisassemblyOperation` — the whole pipeline, in the CLI
//  product target. That put it out of reach of the planned GUI, randomizer and
//  map editor, and meant it could only be exercised by building a config and
//  routing through dispatch. It belongs beside the format it reads.
//
//  It lives in `Dolphin` rather than `Disassembler` because it needs both this
//  module's PowerPC types and that module's section/type-map machinery, and
//  `Disassembler` is deliberately ISA-agnostic — its assembly step is a
//  caller-supplied callback for exactly that reason.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Disassembler

public struct DolDisassembler {

    private let dolphinEngine: DolphinEngine
    private let registry: FileFormatRegistry

    /// - Parameter registry: file formats that embedded `.file` chunks are
    ///   routed through. Supplied by the caller because the set spans engines
    ///   and no single engine module can name all of them.
    public init(dolphinEngine: DolphinEngine, registry: FileFormatRegistry) {
        self.dolphinEngine = dolphinEngine
        self.registry = registry
    }

    /// Subfolder a DOL's disassembly belongs in: the filename without its
    /// extension, so `main.dol` becomes `main/`.
    public static func outputFolderName(for dolPath: File) -> String {
        dolPath.fileName.components(separatedBy: ".").first ?? dolPath.fileName
    }

    /// Disassembles `dolPath` into `destination`, which is returned for the
    /// caller to place wherever it wants — see `outputFolderName(for:)` for
    /// the subfolder convention the assembler expects to read back.
    @discardableResult
    public func disassemble(
        dolPath: File,
        symbolMapPath: File?,
        typeMapPath: File?,
        engineFolders: [Folder],
        from fileSystem: FileSystemTree,
        into destination: FileSystemTree = InMemoryFST(),
        logger: Logger? = nil
    ) throws -> FileSystemTree {
        guard let dolData = fileSystem.readFile(at: dolPath)?.allData else {
            throw DolDisassemblyErrors.dolNotFound(file: dolPath, .init())
        }

        let dol = try Dol(data: dolData, dolphinEngine: dolphinEngine)
        let decoder = PPCDecoder()
        let formatter = PPCFormatter()

        var allSymbols = [PPCSymbol]()
        var symbolLookup = [UInt32: String]()
        if let symbolMapPath = symbolMapPath,
           let symbolData = fileSystem.readFile(at: symbolMapPath)?.allData {
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

        // The caller supplies the tree, so a large DOL can be disassembled
        // into a disk-backed one instead of holding every section, chunk and
        // rendered listing in memory.
        let output = destination
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

        var typeMap: TypeMap?
        var resolvedStructs = [String: StructDefinition]()
        if let typeMapPath = typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath)?.allData {
            typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData)
            if let tm = typeMap {
                try tm.validate()
                logger?.log(.info("Loaded type map with \(tm.chunks.count) chunks"))
                resolvedStructs = resolveStructTypes(from: tm, engineFolders: engineFolders, fileSystem: fileSystem, logger: logger)
            }
        }

        // Data sections — always shiftable with pointer labels
        let assemblyExporter = AssemblyTextExporter()

        // Counts written as `count` chunks, checked against their tables once
        // every section's manifest exists — a count in .sdata usually counts
        // a table in .data.
        var pendingCounts = [(folder: Folder, count: TypeMap.Chunk.Count, stored: [UInt8])]()
        var dataManifestFolders = [Folder]()

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
            // A count is read through a small-data offset, not a pointer, so
            // nothing mints a label for it, and the symbol map's names for
            // these words can't be trusted (XD's are 0xE195E out). The type
            // map's address is the only thing that places one, so a count
            // becomes a chunk boundary there. Safe for a count and nothing
            // else: the dump keeps it only if the stored value equals its
            // table's entry count, so a wrong address falls back to raw bytes.
            for case .count(let count) in typeMap?.chunks ?? [] {
                guard let address = chunkAddress(.count(count), addressToLabel: addressToLabel),
                      address >= baseAddress, address < sectionEnd else { continue }
                let offset = Int(address - baseAddress)
                guard sectionLabels[offset] == nil else { continue }
                guard offset % 4 == 0 else {
                    logger?.log(.warning(
                        "Count '\(count.label)' is at a misaligned address, which can't start a chunk; leaving it raw."
                    ))
                    continue
                }
                sectionLabels[offset] = count.label
            }
            if !misalignedLabels.isEmpty {
                let preview = misalignedLabels.sorted().prefix(5).joined(separator: ", ")
                logger?.log(.warning("\(sectionName): \(misalignedLabels.count) misaligned labels kept out of chunk boundaries (not shiftable): \(preview)\(misalignedLabels.count > 5 ? ", …" : "")"))
            }

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
                    manifest.chunks.append(.init(label: labelName, type: .assembly, file: fileName, size: chunkBytes.count))
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

                if let typeChunk = typeChunkByLabel[labelName] {
                    switch typeChunk {
                    case .count(let count):
                        // The count occupies its declared width; whatever
                        // follows before the next label is left to the gap
                        // chunk below, like any typed chunk's remainder.
                        let width = count.type.length
                        let span = labelOffset ..< labelOffset + width
                        guard nextOffset - labelOffset >= width,
                              !sectionPointers.keys.contains(where: { span.contains($0) }) else {
                            logger?.log(.warning(
                                "Count '\(count.label)' isn't \(width) plain byte(s) here; keeping its bytes."
                            ))
                            emitUntypedChunk(from: labelOffset, to: nextOffset, label: labelName)
                            consumedUpTo = nextOffset
                            continue
                        }
                        manifest.chunks.append(.init(
                            label: labelName, type: .count, file: "", size: width,
                            countOf: count.table, countType: count.type
                        ))
                        pendingCounts.append((sectionFolder, count, Array(bytes[span])))
                        consumedUpTo = labelOffset + width

                    case .table(let table):
                        guard let definition = resolvedStructs[table.entryType] else {
                            logger?.log(.warning("Unknown struct type '\(table.entryType)' for table '\(table.name)' — emitting as untyped chunk"))
                            emitUntypedChunk(from: labelOffset, to: nextOffset, label: labelName)
                            consumedUpTo = nextOffset
                            continue
                        }
                        // A table that declares no count runs to the next
                        // label, which is the rule the REL side already uses
                        // and the only one that can be right: a DOL chunk's
                        // end *is* the next label. Defaulting to zero instead
                        // wrote an empty CSV and pushed every byte of the
                        // table into the gap chunk behind it, saying nothing.
                        let entrySize = definition.length
                        let available = nextOffset - labelOffset
                        let count = table.count ?? (entrySize > 0 ? available / entrySize : 0)
                        guard entrySize > 0, count > 0 else {
                            logger?.log(.warning(
                                "Table '\(table.name)' of \(table.entryType) resolves to \(count) entries of "
                                + "\(entrySize) bytes — emitting as untyped chunk"
                            ))
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

                        // CSV is the only artifact for a table — no
                        // byte-identical sidecar, and no round-trip check
                        // either. A table the struct describes badly dumps as
                        // CSV anyway and the audit catches it as a byte
                        // difference; demoting it to a raw chunk here hid the
                        // bad definition behind a warning nobody reads.
                        let csv = try StructTableCSV.encode(
                            entries: entries.map(\.data), definition: definition
                        )
                        let fileName = "\(table.name).csv"
                        try output.writeFile(
                            GoDData(string: csv, format: .utf8),
                            at: sectionFolder.file(fileName),
                            overwrite: true
                        )
                        // Entry symbols are metadata, not fields, so they
                        // ride in the manifest rather than as a column.
                        var tableEntryLabels = [String: String]()
                        for (index, entry) in entries.enumerated() {
                            if let label = entry.label { tableEntryLabels[String(index)] = label }
                        }
                        manifest.chunks.append(.init(
                            label: table.start, type: .table, file: fileName,
                            structType: table.entryType, count: count,
                            size: tableSize,
                            entryLabels: tableEntryLabels.isEmpty ? nil : tableEntryLabels
                        ))
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

                        // Same policy as tables: JSON only, and a failure to
                        // encode it stops the dump rather than quietly
                        // becoming a raw chunk.
                        let fileName = "\(single.label).json"
                        let json: GoDData = try JSONEncoder.prettyPrinted.encode(structData)
                        try output.writeFile(json, at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(
                            label: single.label, type: .struct, file: fileName,
                            structType: single.type, size: structSize
                        ))
                        consumedUpTo = labelOffset + structSize

                    case .file(let embeddedFile):
                        // The gap to the next label is a floor, not the
                        // answer. A format that reads its own length off its
                        // header can raise it: XD's health-warning texture
                        // names its palette `tex_warning` 0x6C0 bytes in, and
                        // XD PAL's Spanish message table has a symbol 66 KB
                        // before its end, so the gap rule cut both short.
                        //
                        // It can only raise it. A measurement below the gap
                        // would leave the bytes between to a separate chunk,
                        // which is a layout decision the container already
                        // made: a `.msg` keeps the alignment padding after
                        // its pool, and `MSGFile` re-emits it. Declare
                        // `size` in the type map to shorten a chunk.
                        let ext = embeddedFile.extension
                        let available = min(nextOffset, bytes.count) - labelOffset
                        let toSectionEnd = bytes.count - labelOffset
                        let measured = registry.measuredLength(
                            of: GoDData(
                                byteStream: Array(bytes[labelOffset..<bytes.count]), byteOrder: .big
                            ),
                            extension: ext
                        )
                        let fileSize = min(
                            embeddedFile.size ?? max(measured ?? available, available), toSectionEnd
                        )
                        let fileBytes = Array(bytes[labelOffset..<(labelOffset + fileSize)])
                        let fileData = GoDData(byteStream: fileBytes, byteOrder: .big)

                        // Symbols the file swallowed. Code points at them, so
                        // the manifest carries them and the assembler puts
                        // them back at the same offsets inside the rebuilt file.
                        var interiorLabels = [String: String]()
                        if fileSize > available {
                            for (offset, name) in sectionLabels
                            where offset > labelOffset && offset < labelOffset + fileSize {
                                interiorLabels[String(offset - labelOffset)] = name
                            }
                            logger?.log(.info(
                                "'\(embeddedFile.label)' (.\(ext)) measures \(fileSize) bytes and runs past "
                                + "\(interiorLabels.count) of its own symbol(s); keeping them as interior labels."
                            ))
                        }
                        let interior = interiorLabels.isEmpty ? nil : interiorLabels

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
                                    size: fileSize, fileExtension: ext, interiorLabels: interior
                                ))
                            } catch {
                                logger?.log(.warning("Registry dump failed for '\(embeddedFile.label)' (.\(ext)): \(error). Falling back to raw bytes."))
                                let fileName = "\(embeddedFile.label).\(ext)"
                                try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: fileName,
                                    size: fileSize, fileExtension: ext, interiorLabels: interior
                                ))
                            }
                        } else {
                            let fileName = "\(embeddedFile.label).\(ext)"
                            try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: embeddedFile.label, type: .file, file: fileName,
                                size: fileSize, fileExtension: ext, interiorLabels: interior
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

            if let manifestJSON: GoDData = try? JSONEncoder.prettyPrinted.encode(manifest) {
                try output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
            }
            dataManifestFolders.append(sectionFolder)

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        if !pendingCounts.isEmpty {
            try verifyCounts(pendingCounts, manifestFolders: dataManifestFolders, in: output, logger: logger)
        }

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

        return output
    }

    /// Keeps a `count` chunk only where the value on disc is exactly its
    /// table's dumped entry count, so deriving it reproduces the DOL. Any
    /// other — the table didn't dump as a table, or the value disagrees —
    /// is turned back into a raw chunk holding its bytes, with a warning.
    private func verifyCounts(
        _ pending: [(folder: Folder, count: TypeMap.Chunk.Count, stored: [UInt8])],
        manifestFolders: [Folder],
        in output: FileSystemTree,
        logger: Logger?
    ) throws {
        func manifest(in folder: Folder) -> DataSectionManifest? {
            guard let data = output.readFile(at: folder.file("manifest.json"))?.allData else { return nil }
            return try? JSONDecoder().decode(DataSectionManifest.self, from: data.data)
        }
        var tableCounts = [String: Int]()
        for folder in manifestFolders {
            for chunk in manifest(in: folder)?.chunks ?? [] where chunk.type == .table {
                tableCounts[chunk.label] = chunk.count
            }
        }
        for (folder, count, stored) in pending {
            let problem: String
            if let entries = tableCounts[count.table] {
                let value = count.type.countValue(of: stored)
                guard value != Int64(entries) else { continue }
                problem = "holds \(value) but '\(count.table)' has \(entries) entries"
            } else {
                problem = "counts '\(count.table)', which didn't dump as a table"
            }
            logger?.log(.warning("Count '\(count.label)' \(problem); keeping its bytes."))
            guard var sectionManifest = manifest(in: folder),
                  let index = sectionManifest.chunks.firstIndex(where: { $0.label == count.label && $0.type == .count }) else {
                continue
            }
            let fileName = "\(count.label).bin"
            try output.writeFile(GoDData(byteStream: stored, byteOrder: .big), at: folder.file(fileName), overwrite: true)
            sectionManifest.chunks[index] = .init(label: count.label, type: .binary, file: fileName, size: stored.count)
            let json: GoDData = try JSONEncoder.prettyPrinted.encode(sectionManifest)
            try output.writeFile(json, at: folder.file("manifest.json"), overwrite: true)
        }
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
    case .count(let c): label = c.label
    }
    // Try exact lookup in reverse (label → address)
    if let entry = addressToLabel.first(where: { $0.value == label }) {
        return entry.key
    }
    // Try auto-label resolution
    return resolveAutoLabel(label)
}

/// Resolve the struct type names a type map references into concrete
/// `StructDefinition`s, against the engines the operation config names.
///
/// The engine folders are combined into a single `GenericEngine`, in config
/// order, so a type resolves against the first engine that declares it and
/// definitions may reference each other across engines — a game struct can
/// use a Pokemon enum when both engines are listed. Enums resolve properly
/// here, which a previous local resolver did not do: it read only
/// `<engine>/Structs/*.json` and mapped every `.enumeration` field to
/// `uint8`, so no typed chunk ever had an enum field.
///
/// A type no engine declares is left unresolved and its chunk degrades to
/// raw bytes. There is deliberately no fallback to a built-in engine:
/// resolving one game's type map against another game's structs produces
/// confident nonsense (Colosseum and XD both declare `CharacterModel`, at
/// 0xDC and 0x34 bytes).
public func resolveStructTypes(
    from typeMap: TypeMap,
    engineFolders: [Folder],
    fileSystem: FileSystemTree,
    logger: Logger?
) -> [String: StructDefinition] {
    var typeNames = Set<String>()
    for chunk in typeMap.chunks {
        switch chunk {
        case .table(let t): typeNames.insert(t.entryType)
        case .single(let s): typeNames.insert(s.type)
        case .file, .count: break
        }
    }
    return resolveStructTypes(named: typeNames, engineFolders: engineFolders, fileSystem: fileSystem, logger: logger)
}

/// The struct definitions behind a set of type names, resolved against the
/// combined engine built from `engineFolders` in order. Used directly by the
/// REL assembler, whose manifest already carries the type names, and through
/// the type-map overload above by both disassemblers.
public func resolveStructTypes(
    named typeNames: Set<String>,
    engineFolders: [Folder],
    fileSystem: FileSystemTree,
    logger: Logger?
) -> [String: StructDefinition] {
    guard !typeNames.isEmpty else { return [:] }

    guard !engineFolders.isEmpty else {
        logger?.log(.warning(
            "Type map references \(typeNames.count) type(s) but the config lists no engines — "
            + "typed chunks will be dumped as raw bytes."
        ))
        return [:]
    }

    let engine: GenericEngine
    do {
        engine = try GenericEngine(combining: engineFolders, in: fileSystem)
    } catch {
        logger?.log(.warning("Couldn't load engines \(engineFolders.map(\.path)): \(error)"))
        return [:]
    }
    logger?.log(.info(
        "Resolving type map against \(engineFolders.count) engine(s): "
        + engineFolders.map(\.path).joined(separator: ", ")
    ))

    let shadowed = engine.shadowedNames
    if !shadowed.structs.isEmpty {
        logger?.log(.warning(
            "Struct name(s) declared by more than one engine; the earliest listed engine wins: "
            + shadowed.structs.joined(separator: ", ")
        ))
    }
    if !shadowed.enums.isEmpty {
        logger?.log(.warning(
            "Enum name(s) declared by more than one engine; the earliest listed engine wins: "
            + shadowed.enums.joined(separator: ", ")
        ))
    }

    var resolved = [String: StructDefinition]()
    for typeName in typeNames.sorted() {
        do {
            resolved[typeName] = try engine.getStruct(typeName)
        } catch {
            logger?.log(.warning("Struct type '\(typeName)' not resolved: \(error)"))
        }
    }
    return resolved
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

public enum DolDisassemblyErrors: Error, CustomStringConvertible {
    case dolNotFound(file: File, ErrorTrace)
    case structNotFound(name: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .dolNotFound(file, trace):
            return "DOL file not found: \(file)\n\(trace)"
        case let .structNotFound(name, trace):
            return "Sub-struct '\(name)' not found\n\(trace)"
        }
    }
}
