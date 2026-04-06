import GoDFoundation
import Dolphin
import Disassembler
import Structs
import XD

extension DolDisassembly {
    static func disassemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
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

        // Disassemble text sections — always run relocation analysis
        for (index, section) in textSections {
            let sectionName = "text\(index)"
            let bytes = section.assembly.rawBytes
            let instructions = decoder.decodeAll(bytes, baseAddress: section.RAMAddress)
            let sectionEnd = section.RAMAddress + UInt32(section.assembly.length)

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

            if hasSymbols {
                let sectionSymbols = allSymbols.filter {
                    $0.address >= section.RAMAddress && $0.address < sectionEnd
                }

                if !sectionSymbols.isEmpty {
                    // Split into per-function files organized by source object file
                    let sectionFolder = outputFolder.folder(sectionName)
                    let functions = formatter.splitByFunction(instructions, symbols: sectionSymbols, relocations: relocations, sectionName: ".\(sectionName)")

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
                        output.writeFile(GoDData(string: function.text, format: .utf8), at: file, overwrite: true)
                        manifestFiles.append(relativePath)
                    }

                    // Write text section manifest for ordering
                    let manifest = TextSectionManifest(section: sectionName, files: manifestFiles)
                    if let manifestJSON: GoDData = try? JSONEncoder().encode(manifest) {
                        output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
                    }
                } else {
                    // Symbols exist but none in this section — single file with relocations
                    let text = formatter.formatAssembly(instructions, relocations: relocations, sectionName: ".\(sectionName)")
                    let file = outputFolder.file("\(sectionName).s")
                    output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
                }
            } else {
                // No symbol map — single file with auto-generated labels + relocations
                let text = formatter.formatAssembly(instructions, relocations: relocations, sectionName: ".\(sectionName)")
                let file = outputFolder.file("\(sectionName).s")
                output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
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
        // Add data pointer targets
        for sectionPointers in dataPointerResults {
            for (_, target) in sectionPointers where addressToLabel[target] == nil {
                addressToLabel[target] = "lbl_\(String(format: "%08X", target))"
            }
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
                resolvedStructs = resolveStructTypes(from: tm, fileSystem: fileSystem, logger: logger)
            }
        }

        // Data sections — always shiftable with pointer labels
        let assemblyExporter = AssemblyTextExporter()

        for (sectionIndex, (index, section)) in dataSections.enumerated() {
            let sectionName = "data\(index)"
            let bytes = section.data.rawBytes
            let baseAddress = section.RAMAddress
            let sectionEnd = baseAddress + UInt32(bytes.count)

            // Build label map for this section (offset → label name)
            var sectionLabels = [Int: String]()
            for (addr, name) in addressToLabel {
                if addr >= baseAddress && addr < sectionEnd {
                    sectionLabels[Int(addr - baseAddress)] = name
                }
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
                            logger?.log(.warning("Unknown struct type '\(table.entryType)' for table '\(table.name)'"))
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

                        let fileName = "\(table.name).json"
                        let tableJSON = BulkTableJSON(structType: table.entryType, entries: entries)
                        if let json: GoDData = try? JSONEncoder.prettyPrinted.encode(tableJSON) {
                            output.writeFile(json, at: sectionFolder.file(fileName), overwrite: true)
                        }
                        manifest.chunks.append(.init(
                            label: table.start, type: .table, file: fileName,
                            structType: table.entryType, count: count
                        ))
                        consumedUpTo = labelOffset + tableSize

                    case .single(let single):
                        guard let definition = resolvedStructs[single.type] else {
                            logger?.log(.warning("Unknown struct type '\(single.type)' for '\(single.label)'"))
                            continue
                        }
                        let structSize = min(definition.length, bytes.count - labelOffset)
                        let structBytes = Array(bytes[labelOffset..<(labelOffset + structSize)])
                        let structData = typedExporter.exportStruct(
                            data: GoDData(byteStream: structBytes, byteOrder: .big),
                            definition: definition,
                            addressToLabel: addressToLabel
                        )

                        let fileName = "\(single.label).json"
                        if let json: GoDData = try? JSONEncoder.prettyPrinted.encode(structData) {
                            output.writeFile(json, at: sectionFolder.file(fileName), overwrite: true)
                        }
                        manifest.chunks.append(.init(
                            label: single.label, type: .struct, file: fileName,
                            structType: single.type
                        ))
                        consumedUpTo = labelOffset + structSize

                    case .file(let embeddedFile):
                        let fileSize = min(embeddedFile.size, bytes.count - labelOffset)
                        let fileBytes = Array(bytes[labelOffset..<(labelOffset + fileSize)])
                        let fileName = "\(embeddedFile.label).\(embeddedFile.extension)"
                        output.writeFile(GoDData(byteStream: fileBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(
                            label: embeddedFile.label, type: .file, file: fileName,
                            size: embeddedFile.size, fileExtension: embeddedFile.extension
                        ))
                        consumedUpTo = labelOffset + fileSize
                    }
                } else {
                    // Untyped chunk — check if it has pointer labels
                    let chunkBytes = Array(bytes[labelOffset..<nextOffset])
                    let chunkPointers = sectionPointers
                        .filter { $0.key >= labelOffset && $0.key < nextOffset }
                        .reduce(into: [Int: UInt32]()) { $0[$1.key - labelOffset] = $1.value }

                    if !chunkPointers.isEmpty {
                        // Has pointers → assembly .s
                        let chunkLabels: [Int: String] = [0: labelName]
                        let fileName = "\(labelName).s"
                        let text = assemblyExporter.format(
                            data: chunkBytes,
                            baseAddress: baseAddress + UInt32(labelOffset),
                            labels: chunkLabels,
                            pointers: chunkPointers,
                            addressToLabel: addressToLabel,
                            sectionName: ".\(sectionName)"
                        )
                        output.writeFile(GoDData(string: text, format: .utf8), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .assembly, file: fileName))
                    } else {
                        // No pointers → raw .bin
                        let fileName = "\(labelName).bin"
                        output.writeFile(GoDData(byteStream: chunkBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                        manifest.chunks.append(.init(label: labelName, type: .binary, file: fileName, size: chunkBytes.count))
                    }
                }
            }

            // Handle data before the first label (if any)
            if let firstLabelOffset = sortedLabelOffsets.first, firstLabelOffset > 0 {
                let preBytes = Array(bytes[0..<firstLabelOffset])
                let preLabel = "lbl_\(String(format: "%08X", baseAddress))"
                let fileName = "\(preLabel).bin"
                output.writeFile(GoDData(byteStream: preBytes, byteOrder: .big), at: sectionFolder.file(fileName), overwrite: true)
                manifest.chunks.insert(.init(label: preLabel, type: .binary, file: fileName, size: preBytes.count), at: 0)
            }

            // Write manifest
            if let manifestJSON: GoDData = try? JSONEncoder.prettyPrinted.encode(manifest) {
                output.writeFile(manifestJSON, at: sectionFolder.file("manifest.json"), overwrite: true)
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
        output.writeFile(GoDData(string: summaryText, format: .utf8), at: outputFolder.file("sections.txt"), overwrite: true)

        // Write everything to disk at once
        fileSystem.importFST(output, from: outputFolder, to: config.outputFolder, overwrite: true)

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

private func resolveStructTypes(
    from typeMap: TypeMap,
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

    // Build struct definitions from XD engine defaults
    let allStructs = XDEngine.Structs.allItems
    var resolved = [String: StructDefinition]()

    for typeName in typeNames {
        guard let structMap = allStructs.first(where: { $0.name == typeName }) else {
            logger?.log(.warning("Struct type '\(typeName)' not found in XD engine"))
            continue
        }
        // Resolve StructMap → StructDefinition (resolve sub-struct references)
        do {
            let definition = try resolveStructMap(structMap, allStructs: allStructs)
            resolved[typeName] = definition
        } catch {
            logger?.log(.warning("Failed to resolve struct '\(typeName)': \(error)"))
        }
    }

    return resolved
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

/// Bulk table JSON format for encoding.
/// Each entry is a flat object with an optional `_label` and the struct fields directly.
/// Padding fields are excluded.
struct BulkTableJSON: Encodable {
    let structType: String
    let entries: [LabeledData]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(structType, forKey: .structType)

        var entriesContainer = container.nestedUnkeyedContainer(forKey: .entries)
        for entry in entries {
            var entryContainer = entriesContainer.nestedContainer(keyedBy: DynamicCodingKey.self)
            if let label = entry.label {
                try entryContainer.encode(label, forKey: DynamicCodingKey("_label"))
            }
            // Encode struct fields directly (flat), skipping padding
            for property in entry.data.definition.properties {
                guard property.name != "padding" && !isPadding(property.type) else { continue }
                let key = DynamicCodingKey(property.name)
                switch property.type {
                case .label:
                    let labelName = entry.data.labelValues[property.name] ?? ""
                    try entryContainer.encode(labelName, forKey: key)
                case .enumeration(let def):
                    if let rawValue: Int = entry.data.get(property.name),
                       let caseName = try? def.get(rawValue).name {
                        try entryContainer.encode(caseName, forKey: key)
                    } else {
                        let value: Int = entry.data.get(property.name) ?? 0
                        try entryContainer.encode(value, forKey: key)
                    }
                case .primitive(.float):
                    let value: Float = entry.data.get(property.name) ?? 0
                    try entryContainer.encode(value, forKey: key)
                case .primitive(.double):
                    let value: Double = entry.data.get(property.name) ?? 0
                    try entryContainer.encode(value, forKey: key)
                case .primitive(.boolean):
                    let value: Bool = entry.data.get(property.name) ?? false
                    try entryContainer.encode(value, forKey: key)
                default:
                    let value: Int = entry.data.get(property.name) ?? 0
                    try entryContainer.encode(value, forKey: key)
                }
            }
        }
    }

    private func isPadding(_ type: StructProperty) -> Bool {
        switch type {
        case .padding: return true
        case .array(.primitive(.integer(.uint8)), _):
            return false // could be padding named "padding" but we check name below
        default: return false
        }
    }

    enum CodingKeys: String, CodingKey {
        case structType, entries
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension JSONEncoder {
    static let prettyPrinted: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
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
