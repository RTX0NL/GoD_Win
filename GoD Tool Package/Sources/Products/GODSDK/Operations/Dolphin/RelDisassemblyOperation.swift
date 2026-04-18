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
        registry: FileFormatRegistry = .builtins()
    ) throws {
        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)

        guard let relData = fileSystem.readFile(at: config.relPath) else {
            throw RelDisassemblyErrors.relNotFound(file: config.relPath, .init())
        }

        let rel = try Rel(data: relData)
        let decoder = PPCDecoder()
        let formatter = PPCFormatter()

        let relName = config.relPath.fileName.replacingOccurrences(of: ".rel", with: "")
        logger?.log(.info("Disassembling REL '\(relName)' (module \(rel.moduleID), \(rel.sections.filter { $0.size > 0 }.count) sections)"))
        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .started))

        // Load symbol index if available
        var symbolIndex = RelSymbolIndex()
        if let indexPath = config.symbolIndexPath,
           let indexData = fileSystem.readFile(at: indexPath) {
            if let parsed = try? JSONDecoder().decode(RelSymbolIndex.self, from: indexData) {
                symbolIndex = parsed
                logger?.log(.info("Loaded \(parsed.symbols.count) symbol names from index"))
            }
        }

        // Load DOL symbol map for cross-module resolution
        var dolSymbolLookup = [UInt32: String]()
        if let dolMapPath = config.dolSymbolMapPath,
           let dolMapData = fileSystem.readFile(at: dolMapPath) {
            let parser = SymbolMapParser()
            let dolSymbols = parser.parse(dolMapData.string(format: .utf8))
            dolSymbolLookup = parser.buildLookup(dolSymbols)
            logger?.log(.info("Loaded \(dolSymbols.count) DOL symbols for cross-module resolution"))
        }

        // Build label names for symbol pointers using the index
        var symbolLabels = [UInt32: String]()  // file offset → label name
        for (index, fileOffset) in rel.symbolPointers {
            let name = symbolIndex.name(for: index) ?? "sym_\(index)"
            symbolLabels[fileOffset] = name
        }

        // Build set of count symbol names (these will be auto-generated, not dumped)
        var countSymbolNames = Set<String>()
        for entry in symbolIndex.listSymbols {
            countSymbolNames.insert(entry.countName)
        }

        // Load type map if available
        var typeMap: TypeMap?
        var resolvedStructs = [String: StructDefinition]()
        if let typeMapPath = config.typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath) {
            typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData)
            if let tm = typeMap {
                logger?.log(.info("Loaded type map with \(tm.chunks.count) chunks"))
                resolvedStructs = resolveStructTypes(from: tm, fileSystem: fileSystem, typeMapFolder: typeMapPath.parentFolder, logger: logger)
            }
        }

        // Build type lookup: symbol name → TypeMap.Chunk for data sections
        var typeChunkBySymbol = [String: TypeMap.Chunk]()
        if let tm = typeMap {
            for chunk in tm.chunks {
                switch chunk {
                case .table(let t): typeChunkBySymbol[t.start] = chunk
                case .single(let s): typeChunkBySymbol[s.label] = chunk
                case .file(let f): typeChunkBySymbol[f.label] = chunk
                }
            }
        }

        let output = InMemoryFST()
        let outputFolder = Folder("/")

        let textSections = rel.textSections
        let dataSections = rel.dataSections
        let totalSections = textSections.count + dataSections.count
        var sectionsProcessed = 0

        // Build relocation lookup: (sectionIndex, offsetInSection) → relocation target info
        // This tells us what each relocated instruction/data word references
        var relocByPosition = [String: (targetSection: UInt8, addend: UInt32, sourceModule: UInt32)]()
        var writeSection: UInt8 = 0
        var writeOffset: UInt32 = 0

        for entry in rel.relocations {
            switch entry.command {
            case Rel.RelocationEntry.R_DOLPHIN_SECTION:
                writeSection = entry.targetSection
                writeOffset = 0
            case Rel.RelocationEntry.R_DOLPHIN_END:
                break
            case Rel.RelocationEntry.R_DOLPHIN_NOP:
                writeOffset += UInt32(entry.offset)
            default:
                writeOffset += UInt32(entry.offset)
                let key = "\(writeSection):\(writeOffset)"
                relocByPosition[key] = (
                    targetSection: entry.targetSection,
                    addend: entry.addend,
                    sourceModule: entry.sourceModuleID
                )
            }
        }

        // Disassemble text sections
        for section in textSections {
            let sectionName = "text\(section.index)"
            let bytes = section.data.rawBytes

            guard !bytes.isEmpty else { continue }

            let instructions = decoder.decodeAll(bytes, baseAddress: 0)

            // Build relocation annotations for this section
            var relocAnnotations = [UInt32: String]()
            for (i, inst) in instructions.enumerated() {
                let offset = UInt32(i * 4)
                let key = "\(section.index):\(offset)"
                if let reloc = relocByPosition[key] {
                    let targetName: String
                    if reloc.sourceModule == 0 {
                        // DOL reference
                        targetName = dolSymbolLookup[reloc.addend] ?? "dol_\(String(format: "%08X", reloc.addend))"
                    } else if reloc.sourceModule == rel.moduleID {
                        // Self reference — use symbol pointer table
                        let targetFileOffset = rel.sections.first(where: { $0.index == Int(reloc.targetSection) })
                            .map { $0.fileOffset + reloc.addend }
                        if let fOff = targetFileOffset, let name = symbolLabels[fOff] {
                            targetName = name
                        } else {
                            targetName = "sec\(reloc.targetSection)_\(String(format: "%X", reloc.addend))"
                        }
                    } else {
                        targetName = "mod\(reloc.sourceModule)_sec\(reloc.targetSection)_\(String(format: "%X", reloc.addend))"
                    }
                    relocAnnotations[offset] = targetName
                }
            }

            // Format as assembly with relocation comments
            var lines = [String]()
            lines.append(".section .\(sectionName)")
            lines.append("")

            // Add prolog/epilog labels
            if section.index == Int(rel.prologSection) {
                let prologOff = rel.prologOffset
                if prologOff == 0 {
                    lines.append(".global _prolog")
                    lines.append("_prolog:")
                }
            }

            for (i, inst) in instructions.enumerated() {
                let offset = UInt32(i * 4)

                // Add epilog label
                if section.index == Int(rel.epilogSection) && offset == rel.epilogOffset && offset > 0 {
                    lines.append("")
                    lines.append(".global _epilog")
                    lines.append("_epilog:")
                }

                // Check for symbol at this offset
                let fileOff = section.fileOffset + offset
                if let label = symbolLabels[fileOff] {
                    lines.append("")
                    lines.append(".global \(label)")
                    lines.append("\(label):")
                }

                if let relocTarget = relocAnnotations[offset] {
                    lines.append("    \(formatter.format(inst))  # -> \(relocTarget)")
                } else {
                    lines.append("    \(formatter.format(inst))")
                }
            }

            let file = outputFolder.file("\(sectionName).s")
            output.writeFile(GoDData(string: lines.joined(separator: "\n"), format: .utf8), at: file, overwrite: true)

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble REL", status: .progress(pct)))
            }
        }

        // Disassemble data sections
        let assemblyExporter = AssemblyTextExporter()

        for section in dataSections {
            let sectionName = "data\(section.index)"
            let bytes = section.data.rawBytes
            guard !bytes.isEmpty else { continue }

            // Build label map for this section from symbol pointers
            var sectionLabels = [Int: String]()
            for (_, fileOffset) in rel.symbolPointers {
                if fileOffset >= section.fileOffset && fileOffset < section.fileOffset + section.size {
                    let offset = Int(fileOffset - section.fileOffset)
                    if let name = symbolLabels[fileOffset] {
                        sectionLabels[offset] = name
                    }
                }
            }

            // Build pointer map from relocations targeting this section's data
            var sectionPointers = [Int: UInt32]()
            for (i, byte) in bytes.enumerated() where i % 4 == 0 && i + 4 <= bytes.count {
                let key = "\(section.index):\(i)"
                if let reloc = relocByPosition[key] {
                    // This data word is a relocated pointer
                    sectionPointers[i] = reloc.addend
                }
            }

            // If there are labels, split into per-label chunks (same as DOL data sections)
            if !sectionLabels.isEmpty {
                let sectionFolder = outputFolder.folder(sectionName)
                var manifest = DataSectionManifest(section: sectionName)
                let sortedLabelOffsets = sectionLabels.keys.sorted()

                for (labelIdx, labelOffset) in sortedLabelOffsets.enumerated() {
                    let labelName = sectionLabels[labelOffset]!
                    let nextOffset = labelIdx + 1 < sortedLabelOffsets.count
                        ? sortedLabelOffsets[labelIdx + 1]
                        : bytes.count
                    let chunkSize = nextOffset - labelOffset
                    guard chunkSize > 0 else { continue }

                    let chunkBytes = Array(bytes[labelOffset..<nextOffset])
                    let chunkPointers = sectionPointers
                        .filter { $0.key >= labelOffset && $0.key < nextOffset }
                        .reduce(into: [Int: UInt32]()) { $0[$1.key - labelOffset] = $1.value }

                    // Embedded file chunk — route through the file-format
                    // registry if registered, otherwise raw bytes with the
                    // declared extension.
                    if case .file(let embeddedFile) = typeChunkBySymbol[labelName] {
                        let fileSize = min(embeddedFile.size, chunkBytes.count)
                        let fileData = GoDData(byteStream: Array(chunkBytes.prefix(fileSize)), byteOrder: .big)
                        let ext = embeddedFile.extension
                        if registry.isRegistered(ext) {
                            do {
                                let written = try registry.dump(
                                    bytes: fileData,
                                    extension: ext,
                                    baseName: embeddedFile.label,
                                    into: sectionFolder,
                                    fileSystem: output,
                                    overwrite: true
                                )
                                let primary = written.first?.fileName ?? "\(embeddedFile.label).\(ext)"
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: primary,
                                    size: embeddedFile.size, fileExtension: ext
                                ))
                            } catch {
                                logger?.log(.warning("Registry dump failed for '\(embeddedFile.label)' (.\(ext)): \(error). Falling back to raw bytes."))
                                let fileName = "\(embeddedFile.label).\(ext)"
                                output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                                manifest.chunks.append(.init(
                                    label: embeddedFile.label, type: .file, file: fileName,
                                    size: embeddedFile.size, fileExtension: ext
                                ))
                            }
                        } else {
                            let fileName = "\(embeddedFile.label).\(ext)"
                            output.writeFile(fileData, at: sectionFolder.file(fileName), overwrite: true)
                            manifest.chunks.append(.init(
                                label: embeddedFile.label, type: .file, file: fileName,
                                size: embeddedFile.size, fileExtension: ext
                            ))
                        }
                    }
                    // Check if this label has a typed table definition
                    else if case .table(let tableDef) = typeChunkBySymbol[labelName],
                       let structDef = resolvedStructs[tableDef.entryType] {
                        // Export as typed JSON table
                        let entrySize = structDef.length
                        let count = tableDef.count ?? (chunkSize / entrySize)
                        let chunkData = GoDData(byteStream: chunkBytes, byteOrder: .big)

                        var entries = [[String: Any]]()
                        for i in 0..<count {
                            let offset = i * entrySize
                            guard offset + entrySize <= chunkData.length else { break }
                            if let structData = chunkData.read(struct: structDef, atAddress: offset) {
                                var entry = [String: Any]()
                                for prop in structDef.properties where prop.name != "padding" {
                                    if let value = readStructProperty(prop, from: structData) {
                                        entry[prop.name] = value
                                    }
                                }
                                entries.append(entry)
                            }
                        }

                        let fileName = "\(labelName).json"
                        let tableJSON: [String: Any] = [
                            "type": tableDef.entryType,
                            "count": count,
                            "entrySize": entrySize,
                            "entries": entries
                        ]
                        if let jsonData = try? JSONSerialization.data(withJSONObject: tableJSON, options: [.prettyPrinted, .sortedKeys]) {
                            output.writeFile(GoDData(data: jsonData, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                        }
                        // Also write raw binary as backup
                        let binFileName = "\(labelName).bin"
                        output.writeFile(GoDData(byteStream: chunkBytes, byteOrder: .big), at: sectionFolder.file(binFileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .table, file: fileName, structType: tableDef.entryType, count: count, size: chunkSize))
                    } else if !chunkPointers.isEmpty {
                        let fileName = "\(labelName).s"
                        let chunkLabels: [Int: String] = [0: labelName]
                        let text = assemblyExporter.format(
                            data: chunkBytes,
                            baseAddress: UInt32(labelOffset),
                            labels: chunkLabels,
                            pointers: chunkPointers,
                            addressToLabel: symbolLabels.reduce(into: [UInt32: String]()) { result, pair in
                                result[pair.key] = pair.value
                            },
                            sectionName: ".\(sectionName)"
                        )
                        output.writeFile(GoDData(string: text, format: .utf8), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .assembly, file: fileName))
                    } else {
                        let fileName = "\(labelName).bin"
                        output.writeFile(GoDData(byteStream: chunkBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .binary, file: fileName, size: chunkBytes.count))
                    }
                }

                // Handle data before first label
                if let firstOffset = sortedLabelOffsets.first, firstOffset > 0 {
                    let preBytes = Array(bytes[0..<firstOffset])
                    let preLabel = "\(sectionName)_start"
                    let fileName = "\(preLabel).bin"
                    output.writeFile(GoDData(byteStream: preBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                    manifest.chunks.insert(.init(label: preLabel, type: .binary, file: fileName, size: preBytes.count), at: 0)
                }

                // Handle data after last label
                if let lastOffset = sortedLabelOffsets.last {
                    let lastLabelName = sectionLabels[lastOffset]!
                    let lastEnd = bytes.count
                    // Already handled in the loop above
                }

                if let manifestJSON: GoDData = try? JSONEncoder().encode(manifest) {
                    output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
                }
            } else {
                // No symbol labels — output as single flat file
                let addressToLabel = symbolLabels.reduce(into: [UInt32: String]()) { $0[$1.key] = $1.value }
                let text = assemblyExporter.format(
                    data: bytes,
                    baseAddress: 0,
                    labels: sectionLabels,
                    pointers: sectionPointers,
                    addressToLabel: addressToLabel,
                    sectionName: ".\(sectionName)"
                )
                let file = outputFolder.file("\(sectionName).s")
                output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble REL", status: .progress(pct)))
            }
        }

        // Write sections.txt
        var summary = [String]()
        summary.append("# REL Section Layout")
        summary.append("# Module ID: \(rel.moduleID)")
        summary.append("# REL Version: \(rel.version)")
        summary.append("# Prolog: section \(rel.prologSection) offset 0x\(String(rel.prologOffset, radix: 16, uppercase: true))")
        summary.append("# Epilog: section \(rel.epilogSection) offset 0x\(String(rel.epilogOffset, radix: 16, uppercase: true))")
        if rel.bssSize > 0 {
            summary.append("# BSS: section \(rel.bssSection) (\(rel.bssSize) bytes)")
        }
        summary.append("# Symbol pointers: \(rel.symbolPointers.count)")
        summary.append("# Relocations: \(rel.relocations.count)")
        summary.append("# Imports: \(rel.imports.map { $0.moduleID == 0 ? "DOL" : "module \($0.moduleID)" }.joined(separator: ", "))")
        summary.append("")
        for section in textSections {
            summary.append("text\(section.index): offset 0x\(String(section.fileOffset, radix: 16, uppercase: true)) (\(section.size) bytes)")
        }
        for section in dataSections {
            summary.append("data\(section.index): offset 0x\(String(section.fileOffset, radix: 16, uppercase: true)) (\(section.size) bytes)")
        }
        output.writeFile(GoDData(string: summary.joined(separator: "\n"), format: .utf8), at: outputFolder.file("sections.txt"), overwrite: true)

        // Write everything to disk
        fileSystem.importFST(output, from: outputFolder, to: config.outputFolder, overwrite: true)

        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .completed(true)))
    }
}

/// Read a struct property value in a JSON-serializable format,
/// handling each type correctly (floats as Float, arrays as [Any], etc.)
private func readStructProperty(
    _ prop: StructDefinition.Property,
    from structData: StructData
) -> Any? {
    switch prop.type {
    case .primitive(.float):
        return (try? structData[dynamicMember: prop.name]) as Float?
    case .primitive(.double):
        return (try? structData[dynamicMember: prop.name]) as Double?
    case .primitive(.boolean):
        return (try? structData[dynamicMember: prop.name]) as Bool?
    case .primitive(.character(let format)):
        return (try? structData[dynamicMember: prop.name]) as String?
    case .primitive(.integer), .primitive(.void):
        return (try? structData[dynamicMember: prop.name]) as Int?
    case .array(let elementType, let count):
        // Read array elements individually from the raw data
        guard let fieldOffset = structData.definition.offset(for: prop.name) else { return nil }
        switch elementType {
        case .primitive(.integer(let intType)):
            var values = [Int]()
            for i in 0..<count {
                switch intType {
                case .uint8, .int8:
                    let addr = fieldOffset + i
                    values.append(structData.data.readTypeAsInt(UInt8.self, atAddress: addr))
                case .uint16, .int16:
                    let addr = fieldOffset + i * 2
                    if let val: UInt16 = structData.data.readValue(atAddress: addr) { values.append(Int(val)) }
                case .uint32, .int32:
                    let addr = fieldOffset + i * 4
                    if let val: UInt32 = structData.data.readValue(atAddress: addr) { values.append(Int(val)) }
                default:
                    break
                }
            }
            return values
        case .primitive(.float):
            var values = [Float]()
            for i in 0..<count {
                if let val: Float = structData.data.readValue(atAddress: fieldOffset + i * 4) {
                    values.append(val)
                }
            }
            return values
        case .primitive(.character):
            // String — read as string
            return (try? structData[dynamicMember: prop.name]) as String?
        default:
            return nil
        }
    case .padding:
        return nil
    case .subStruct, .enumeration, .label:
        // For enumerations, read as int
        return (try? structData[dynamicMember: prop.name]) as Int?
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
