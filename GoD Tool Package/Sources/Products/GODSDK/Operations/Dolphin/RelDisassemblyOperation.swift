import GoDFoundation
import Dolphin
import Disassembler
import Structs
import XD
import GeniusSonority

extension RelDisassembly {
    static func disassemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        guard RelOperationsGate.enabled else {
            throw RelOperationsGate.DisabledError(operation: "relDisassembly", trace: .init())
        }

        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)
        _ = dolphinEngine  // reserved for future (e.g. SDA base → name resolution)

        guard let relData = fileSystem.readFile(at: config.relPath)?.allData else {
            throw RelDisassemblyErrors.relNotFound(file: config.relPath, .init())
        }

        let relName = config.relPath.fileName.replacingOccurrences(of: ".rel", with: "")
        let rel = try RELFile(binary: relData, name: relName)
        let formatter = PPCFormatter()
        let decoder = PPCDecoder()

        logger?.log(.info("Disassembling REL '\(relName)' (module \(rel.moduleID), \(rel.sections.filter { !$0.isEmpty }.count) non-empty sections)"))
        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .started))

        // ---- Load optional sidecar inputs ----

        var symbolIndex = RelSymbolIndex()
        if let indexPath = config.symbolIndexPath,
           let indexData = fileSystem.readFile(at: indexPath)?.allData,
           let parsed = try? JSONDecoder().decode(RelSymbolIndex.self, from: indexData) {
            symbolIndex = parsed
            logger?.log(.info("Loaded \(parsed.symbols.count) symbol names from index"))
        }

        var dolSymbolLookup: [UInt32: String] = [:]
        if let dolMapPath = config.dolSymbolMapPath,
           let dolMapData = fileSystem.readFile(at: dolMapPath)?.allData {
            let parser = SymbolMapParser()
            let dolSymbols = parser.parse(dolMapData.string(format: .utf8))
            dolSymbolLookup = parser.buildLookup(dolSymbols)
            logger?.log(.info("Loaded \(dolSymbols.count) DOL symbols for cross-module resolution"))
        }

        var typeMap: TypeMap?
        var resolvedStructs: [String: StructDefinition] = [:]
        if let typeMapPath = config.typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath)?.allData {
            typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData)
            if let tm = typeMap {
                logger?.log(.info("Loaded type map with \(tm.chunks.count) chunks"))
                resolvedStructs = resolveStructTypes(
                    from: tm,
                    engineFolders: config.engines ?? [],
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }

        var typeChunkBySymbol: [String: TypeMap.Chunk] = [:]
        var unsupportedSingles = [String]()
        if let tm = typeMap {
            for chunk in tm.chunks {
                switch chunk {
                case .table(let t): typeChunkBySymbol[t.start] = chunk
                case .single(let s):
                    // The data-section walk below handles `.table` and
                    // `.file`; a lone struct has no branch yet, so say so
                    // rather than letting the chunk quietly come out untyped.
                    unsupportedSingles.append(s.label)
                case .file(let f): typeChunkBySymbol[f.label] = chunk
                }
            }
        }
        if !unsupportedSingles.isEmpty {
            logger?.log(.warning(
                "Type map declares \(unsupportedSingles.count) single-struct chunk(s) "
                + "(\(unsupportedSingles.prefix(3).joined(separator: ", "))"
                + "\(unsupportedSingles.count > 3 ? ", …" : "")) — the REL path only types "
                + "tables and files, so these will be emitted as raw chunks."
            ))
        }

        // ---- Derive the canonical pointer-index map ----
        //
        // Walk every SymbolRef in the REL in canonical chain order (group
        // by imported module, then source section/offset) and assign
        // sequential indices to unique target tuples. This reproduces the
        // numbering the legacy `Rel` parser produced so existing
        // RelSymbolIndex JSON files keep working after the migration.

        struct TargetKey: Hashable {
            let module: UInt32
            let section: UInt8
            let offset: UInt32
        }

        struct EdgeDescriptor {
            let targetModule: UInt32
            let targetSection: UInt8
            let targetOffset: UInt32
            let sourceSection: UInt8
            let sourceOffset: UInt32
        }

        var allEdges: [EdgeDescriptor] = []
        for section in rel.sections {
            switch section.body {
            case .text(let instructions):
                var off: UInt32 = 0
                for inst in instructions {
                    if let ref = inst.ref, let fixup = inst.fixup {
                        allEdges.append(EdgeDescriptor(
                            targetModule: ref.moduleID,
                            targetSection: ref.section,
                            targetOffset: ref.offset,
                            sourceSection: UInt8(section.index),
                            sourceOffset: off + fixup.wordInnerOffset
                        ))
                    }
                    off &+= 4
                }
            case .data(let chunks):
                var off: UInt32 = 0
                for chunk in chunks {
                    if case .pointer(let ref, _) = chunk {
                        allEdges.append(EdgeDescriptor(
                            targetModule: ref.moduleID,
                            targetSection: ref.section,
                            targetOffset: ref.offset,
                            sourceSection: UInt8(section.index),
                            sourceOffset: off
                        ))
                    }
                    off &+= UInt32(chunk.byteLength)
                }
            case .empty, .bss:
                continue
            }
        }

        var pointerIndexByTarget: [TargetKey: Int] = [:]
        var pointerTargets: [Int: TargetKey] = [:]
        var nextPointerIndex = 0

        for mod in rel.importedModules {
            let modEdges = allEdges
                .filter { $0.targetModule == mod }
                .sorted {
                    if $0.sourceSection != $1.sourceSection { return $0.sourceSection < $1.sourceSection }
                    return $0.sourceOffset < $1.sourceOffset
                }
            for edge in modEdges {
                let key = TargetKey(module: edge.targetModule, section: edge.targetSection, offset: edge.targetOffset)
                if pointerIndexByTarget[key] == nil {
                    pointerIndexByTarget[key] = nextPointerIndex
                    pointerTargets[nextPointerIndex] = key
                    nextPointerIndex += 1
                }
            }
        }

        // ---- Section file-offset table (for sections.txt + data-section label keying) ----

        var sectionFileOffset: [Int: UInt32] = [:]
        let hdrSize: Int = {
            switch rel.version { case 1: return 0x40; case 2: return 0x48; default: return 0x4C }
        }()
        var cursor = UInt32(hdrSize + rel.sections.count * 8)
        for s in rel.sections {
            switch s.body {
            case .empty(let fileOff):
                sectionFileOffset[s.index] = fileOff
            case .bss:
                sectionFileOffset[s.index] = 0
            default:
                sectionFileOffset[s.index] = cursor
                cursor &+= s.size
            }
        }

        // ---- Symbol resolution ----

        func nameFor(targetKey: TargetKey, preferredIndex: Int? = nil) -> String {
            if let idx = preferredIndex ?? pointerIndexByTarget[targetKey],
               let name = symbolIndex.name(for: idx) {
                return name
            }
            if targetKey.module == 0 {
                if let name = dolSymbolLookup[targetKey.offset] { return name }
                return "dol_\(String(format: "%08X", targetKey.offset))"
            }
            if let idx = pointerIndexByTarget[targetKey], targetKey.module == rel.moduleID {
                return "sym_\(idx)"
            }
            if targetKey.module == rel.moduleID {
                return "sec\(targetKey.section)_\(String(format: "%X", targetKey.offset))"
            }
            return "mod\(targetKey.module)_sec\(targetKey.section)_\(String(format: "%X", targetKey.offset))"
        }

        func nameFor(ref: RELFile.SymbolRef) -> String {
            nameFor(targetKey: TargetKey(module: ref.moduleID, section: ref.section, offset: ref.offset))
        }

        // Labels reachable from SELF relocations — these get `.global` +
        // `label:` headers in the matching output section.
        var selfLabelsBySection: [Int: [UInt32: String]] = [:]
        for (key, idx) in pointerIndexByTarget where key.module == rel.moduleID {
            let name = symbolIndex.name(for: idx) ?? "sym_\(idx)"
            selfLabelsBySection[Int(key.section), default: [:]][key.offset] = name
        }

        // ---- Output scaffolding ----

        let output = InMemoryFST()
        let outputFolder = Folder("/")
        let textSections = rel.sections.filter { $0.isExecutable }
        let dataSections = rel.sections.filter { !$0.isExecutable && !$0.isBSS && !$0.isEmpty }
        let totalSections = textSections.count + dataSections.count
        var sectionsProcessed = 0

        // ---- Text sections ----

        for section in textSections {
            guard case .text(let instructions) = section.body else { continue }
            let sectionName = "text\(section.index)"
            var lines: [String] = []
            lines.append(".section .\(sectionName)")
            lines.append("")

            let labels = selfLabelsBySection[section.index] ?? [:]

            for (i, instruction) in instructions.enumerated() {
                let offset = UInt32(i * 4)

                // Prolog / epilog / unresolved markers
                if section.index == Int(rel.prologSection), offset == rel.prologOffset {
                    lines.append(offset == 0 ? "" : "")
                    lines.append(".global _prolog")
                    lines.append("_prolog:")
                }
                if section.index == Int(rel.epilogSection), offset == rel.epilogOffset, offset != rel.prologOffset {
                    lines.append("")
                    lines.append(".global _epilog")
                    lines.append("_epilog:")
                }
                if section.index == Int(rel.unresolvedSection), offset == rel.unresolvedOffset,
                   offset != rel.prologOffset, offset != rel.epilogOffset {
                    lines.append("")
                    lines.append(".global _unresolved")
                    lines.append("_unresolved:")
                }
                if let label = labels[offset] {
                    lines.append("")
                    lines.append(".global \(label)")
                    lines.append("\(label):")
                }

                let decoded = decoder.decode(instruction.raw, at: offset)
                let formatted = formatter.format(decoded)
                if let ref = instruction.ref {
                    let target = nameFor(ref: ref)
                    lines.append("    \(formatted)  # -> \(target)")
                } else {
                    lines.append("    \(formatted)")
                }
            }

            let file = outputFolder.file("\(sectionName).s")
            try output.writeFile(GoDData(string: lines.joined(separator: "\n"), format: .utf8), at: file, overwrite: true)

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble REL", status: .progress(pct)))
            }
        }

        // ---- Data sections ----

        let assemblyExporter = AssemblyTextExporter()

        for section in dataSections {
            guard case .data(let chunks) = section.body else { continue }
            let sectionName = "data\(section.index)"

            // Flatten chunks back to bytes + a per-offset pointer map so
            // we can reuse the existing per-label exporter surface.
            var bytes: [UInt8] = []
            var sectionPointers: [Int: UInt32] = [:]   // chunk-offset → target-file-offset
            var sectionPointerRefs: [Int: RELFile.SymbolRef] = [:]
            for chunk in chunks {
                let startOff = bytes.count
                switch chunk {
                case .binary(let b):
                    bytes.append(contentsOf: b)
                case .pointer(let ref, let restValue):
                    bytes.append(UInt8((restValue >> 24) & 0xFF))
                    bytes.append(UInt8((restValue >> 16) & 0xFF))
                    bytes.append(UInt8((restValue >> 8) & 0xFF))
                    bytes.append(UInt8(restValue & 0xFF))
                    let targetFileOff: UInt32
                    if ref.moduleID == rel.moduleID,
                       let tBase = sectionFileOffset[Int(ref.section)] {
                        targetFileOff = tBase &+ ref.offset
                    } else {
                        targetFileOff = ref.offset
                    }
                    sectionPointers[startOff] = targetFileOff
                    sectionPointerRefs[startOff] = ref
                }
            }

            guard !bytes.isEmpty else { continue }

            // Label map within this section: self-targeted symbols.
            let sectionLabels: [Int: String] = (selfLabelsBySection[section.index] ?? [:])
                .reduce(into: [Int: String]()) { $0[Int($1.key)] = $1.value }

            // Address-to-label (file-offset based) for assembly exporter.
            var addressToLabel: [UInt32: String] = [:]
            for (key, idx) in pointerIndexByTarget where key.module == rel.moduleID {
                if let base = sectionFileOffset[Int(key.section)] {
                    let fileOff = base &+ key.offset
                    addressToLabel[fileOff] = symbolIndex.name(for: idx) ?? "sym_\(idx)"
                }
            }

            if !sectionLabels.isEmpty {
                let sectionFolder = outputFolder.folder(sectionName)
                var manifest = DataSectionManifest(section: sectionName)
                let sortedLabelOffsets = sectionLabels.keys.sorted()

                for (i, labelOffset) in sortedLabelOffsets.enumerated() {
                    let labelName = sectionLabels[labelOffset]!
                    let nextOffset = i + 1 < sortedLabelOffsets.count
                        ? sortedLabelOffsets[i + 1]
                        : bytes.count
                    let chunkSize = nextOffset - labelOffset
                    guard chunkSize > 0 else { continue }
                    let chunkBytes = Array(bytes[labelOffset..<nextOffset])
                    let chunkPointers = sectionPointers
                        .filter { $0.key >= labelOffset && $0.key < nextOffset }
                        .reduce(into: [Int: UInt32]()) { $0[$1.key - labelOffset] = $1.value }

                    if case .file(let embeddedFile) = typeChunkBySymbol[labelName] {
                        // A REL data chunk already runs from this symbol to
                        // the next, so that span is the file's length unless
                        // the map deliberately declares a shorter one.
                        let fileSize = min(embeddedFile.size ?? chunkBytes.count, chunkBytes.count)
                        let fileData = GoDData(byteStream: Array(chunkBytes.prefix(fileSize)), byteOrder: .big)
                        let ext = embeddedFile.extension
                        if registry.isRegistered(ext) {
                            let chunkFolder = sectionFolder.folder(embeddedFile.label)
                            do {
                                let written = try registry.dump(
                                    bytes: fileData, extension: ext,
                                    into: chunkFolder, fileSystem: output, overwrite: true
                                )
                                let primary = written.first?.fileName ?? "\(embeddedFile.label).\(ext)"
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: primary,
                                    size: fileSize, fileExtension: ext
                                ))
                            } catch {
                                logger?.log(.warning("Registry dump failed for '\(embeddedFile.label)' (.\(ext)): \(error). Falling back to raw bytes."))
                                let fileName = "\(embeddedFile.label).\(ext)"
                                try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: fileName,
                                    size: fileSize, fileExtension: ext
                                ))
                            }
                        } else {
                            let fileName = "\(embeddedFile.label).\(ext)"
                            try output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: embeddedFile.label, type: .file, file: fileName,
                                size: fileSize, fileExtension: ext
                            ))
                        }
                    } else if case .table(let tableDef) = typeChunkBySymbol[labelName],
                              let structDef = resolvedStructs[tableDef.entryType] {
                        // Same policy as the DOL side: CSV is the only
                        // artifact, verified by decoding it straight back and
                        // comparing bytes. A table that can't round-trip
                        // demotes to a raw binary chunk rather than being
                        // written out lossily beside a `.bin` nobody reads.
                        let entrySize = structDef.length
                        let count = tableDef.count ?? (chunkSize / entrySize)
                        let tableSize = min(entrySize * count, chunkBytes.count)
                        let tableBytes = Array(chunkBytes.prefix(tableSize))
                        let tableData = GoDData(byteStream: tableBytes, byteOrder: .big)

                        let entryLabels = sectionLabels
                            .filter { $0.key >= labelOffset && $0.key < labelOffset + tableSize }
                            .map { (offset: $0.key - labelOffset, name: $0.value) }
                            .sorted(by: { $0.offset < $1.offset })

                        let entries = TypedDataExporter().exportTable(
                            data: tableData,
                            definition: structDef,
                            count: count,
                            entryLabels: entryLabels,
                            addressToLabel: addressToLabel
                        )

                        do {
                            let csv = try StructTableCSV.encode(
                                entries: entries.map(\.data), definition: structDef
                            )
                            try verifyTableRoundTrips(
                                csv: csv, against: entries, definition: structDef, label: labelName
                            )
                            let fileName = "\(labelName).csv"
                            try output.writeFile(
                                GoDData(string: csv, format: .utf8),
                                at: sectionFolder.file(fileName),
                                overwrite: true
                            )
                            var namesByIndex = [String: String]()
                            for (index, entry) in entries.enumerated() {
                                if let label = entry.label { namesByIndex[String(index)] = label }
                            }
                            manifest.chunks.append(.init(
                                label: labelName, type: .table, file: fileName,
                                structType: tableDef.entryType, count: count,
                                entryLabels: namesByIndex.isEmpty ? nil : namesByIndex
                            ))
                        } catch {
                            logger?.log(.warning(
                                "Table '\(labelName)' doesn't round-trip as CSV: \(error). "
                                + "Emitting as raw binary chunk."
                            ))
                            let binName = "\(labelName).bin"
                            try output.writeFile(
                                tableData, at: sectionFolder.file(binName), overwrite: true
                            )
                            manifest.chunks.append(.init(
                                label: labelName, type: .binary, file: binName, size: tableSize
                            ))
                        }
                    } else if !chunkPointers.isEmpty {
                        let fileName = "\(labelName).s"
                        let chunkLabels: [Int: String] = [0: labelName]
                        let text = assemblyExporter.format(
                            data: chunkBytes,
                            baseAddress: UInt32(labelOffset),
                            labels: chunkLabels,
                            pointers: chunkPointers,
                            addressToLabel: addressToLabel,
                            sectionName: ".\(sectionName)"
                        )
                        try output.writeFile(GoDData(string: text, format: .utf8), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .assembly, file: fileName))
                    } else {
                        let fileName = "\(labelName).bin"
                        try output.writeFile(
                            GoDData(byteStream: chunkBytes, byteOrder: .big),
                            at: sectionFolder.file(fileName), overwrite: true
                        )
                        manifest.chunks.append(.init(label: labelName, type: .binary, file: fileName, size: chunkBytes.count))
                    }
                }

                if let first = sortedLabelOffsets.first, first > 0 {
                    let preBytes = Array(bytes[0..<first])
                    let preLabel = "\(sectionName)_start"
                    let fileName = "\(preLabel).bin"
                    try output.writeFile(
                        GoDData(byteStream: preBytes, byteOrder: .big),
                        at: sectionFolder.file(fileName), overwrite: true
                    )
                    manifest.chunks.insert(.init(label: preLabel, type: .binary, file: fileName, size: preBytes.count), at: 0)
                }

                if let manifestJSON: GoDData = try? JSONEncoder().encode(manifest) {
                    try output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
                }
            } else {
                // No named labels — emit the whole section as one assembly
                // blob with pointer annotations inlined.
                let text = assemblyExporter.format(
                    data: bytes,
                    baseAddress: 0,
                    labels: [:],
                    pointers: sectionPointers,
                    addressToLabel: addressToLabel,
                    sectionName: ".\(sectionName)"
                )
                let file = outputFolder.file("\(sectionName).s")
                try output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble REL", status: .progress(pct)))
            }
        }

        // ---- sections.txt summary ----

        var summary: [String] = []
        summary.append("# REL Section Layout")
        summary.append("# Module ID: \(rel.moduleID)")
        summary.append("# REL Version: \(rel.version)")
        summary.append("# Prolog: section \(rel.prologSection) offset 0x\(String(rel.prologOffset, radix: 16, uppercase: true))")
        summary.append("# Epilog: section \(rel.epilogSection) offset 0x\(String(rel.epilogOffset, radix: 16, uppercase: true))")
        summary.append("# Unresolved: section \(rel.unresolvedSection) offset 0x\(String(rel.unresolvedOffset, radix: 16, uppercase: true))")
        if rel.bssSize > 0 {
            summary.append("# BSS: \(rel.bssSize) bytes total")
        }
        summary.append("# Unique pointer targets: \(pointerIndexByTarget.count)")
        summary.append("# Total relocations (derived): \(allEdges.count)")
        summary.append("# Imports: \(rel.importedModules.map { $0 == 0 ? "DOL" : "module \($0)" }.joined(separator: ", "))")
        summary.append("")
        for s in textSections {
            let off = sectionFileOffset[s.index] ?? 0
            summary.append("text\(s.index): offset 0x\(String(off, radix: 16, uppercase: true)) (\(s.size) bytes)")
        }
        for s in dataSections {
            let off = sectionFileOffset[s.index] ?? 0
            summary.append("data\(s.index): offset 0x\(String(off, radix: 16, uppercase: true)) (\(s.size) bytes)")
        }
        try output.writeFile(GoDData(string: summary.joined(separator: "\n"), format: .utf8),
                         at: outputFolder.file("sections.txt"), overwrite: true)

        // Also emit the canonical RELFile JSON. This is the lossless
        // machine representation the assembly op reads to reconstruct
        // bytes. The .s / chunk files are the human-editable view.
        for artifact in try rel.outputs {
            try output.writeFile(artifact.data, at: outputFolder.file(artifact.file.path), overwrite: true)
        }

        try fileSystem.importFST(output, from: outputFolder, to: config.outputFolder, overwrite: true)
        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .completed(true)))
    }
}

enum RelDisassemblyErrors: Error, CustomStringConvertible {
    case relNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .relNotFound(file, trace):
            return "REL file not found: \(file)\n\(trace)"
        }
    }
}

private extension RELFile.RelocationFixup {
    /// Re-exposed for the operation: byte offset into the host 32-bit
    /// word where the patch is applied (matches the private helper
    /// inside RELFile).
    var wordInnerOffset: UInt32 {
        switch self {
        case .addr16, .addr16_lo, .addr16_hi, .addr16_ha: return 2
        default: return 0
        }
    }
}
