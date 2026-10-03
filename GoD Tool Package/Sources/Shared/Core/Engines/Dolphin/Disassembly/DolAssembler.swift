//
//  DolAssembler.swift
//  Dolphin
//
//  The inverse of `DolDisassembler`: an edited source tree back into a `.dol`.
//
//  Moved out of `DolAssemblyOperation` for the same reasons — see that type's
//  note. The two belong together, since the assembler has to read back exactly
//  the layout the disassembler wrote.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Disassembler

public struct DolAssembler {

    private let dolphinEngine: DolphinEngine
    private let registry: FileFormatRegistry

    public init(dolphinEngine: DolphinEngine, registry: FileFormatRegistry) {
        self.dolphinEngine = dolphinEngine
        self.registry = registry
    }

    /// Assembles the source tree under `codeFolder` and writes the rebuilt
    /// executable to `outputDolPath`.
    public func assemble(
        codeFolder: Folder,
        outputDolPath: File,
        symbolMapPath: File?,
        outputSymbolMapPath: File? = nil,
        typeMapPath: File?,
        bssEntryListPath: File?,
        engineFolders: [Folder],
        sdaBase: UInt32?,
        sda2Base: UInt32?,
        allowResizedChunks: Bool = false,
        in fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {

        logger?.log(.info("Assembling DOL from \(codeFolder.path)"))
        logger?.log(.taskStatus(taskName: "Assemble DOL", status: .started))

        let sectionsFile = codeFolder.file("sections.txt")
        guard let sectionsData = fileSystem.readFile(at: sectionsFile)?.allData else {
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
        if let typeMapPath = typeMapPath,
           let typeMapData = fileSystem.readFile(at: typeMapPath)?.allData {
            if let typeMap = try? JSONDecoder().decode(TypeMap.self, from: typeMapData) {
                resolvedStructs = resolveStructTypes(
                    from: typeMap,
                    engineFolders: engineFolders,
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
        let counts = try Self.planCounts(
            dataSections: layout.dataSections.map(\.name), codeFolder: codeFolder,
            fileSystem: fileSystem, manifestReader: manifestReader, structs: resolvedStructs
        )

        var globalSymbols = [String: UInt32]()
        let prescanLabelTable = LabelTable()

        var prescanDataFiles = [String: [(name: String, content: String)]]()
        for section in layout.dataSections {
            prescanDataFiles[section.name] = try Self.collectDataSectionFiles(
                section.name,
                codeFolder: codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader,
                structs: resolvedStructs,
                labelTable: prescanLabelTable,
                registry: registry,
                counts: counts,
                allowResizedChunks: allowResizedChunks,
                logger: nil
            ).files
        }

        for section in layout.textSections {
            let files = manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: codeFolder,
                fileSystem: fileSystem
            )
            let labels = assembler.collectLabelsOnly(files: files, baseAddress: section.address)
            globalSymbols.merge(labels) { existing, _ in existing }
        }
        // Data labels are kept separately as well as merged: they are the
        // chunk and table-entry symbols a type map names, so a rewritten
        // symbol map has to carry them even when the input map never did.
        // Their addresses here are final — the prescan renders typed chunks
        // with an empty label table, which can leave a pointer *value*
        // wrong but never changes a chunk's length.
        var dataSectionLabels = [String: UInt32]()
        for section in layout.dataSections {
            let files = prescanDataFiles[section.name] ?? []
            let labels = assembler.collectLabelsOnly(files: files, baseAddress: section.address)
            dataSectionLabels.merge(labels) { existing, _ in existing }
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
                codeFolder: codeFolder,
                fileSystem: fileSystem
            ))
        }
        for section in layout.dataSections {
            absorbLblReferences(prescanDataFiles[section.name] ?? [])
        }

        // Load symbol map for external references (exception handlers, etc.)
        var inputSymbols = [PPCSymbol]()
        if let symbolMapPath = symbolMapPath,
           let mapData = fileSystem.readFile(at: symbolMapPath)?.allData {
            let parser = SymbolMapParser()
            inputSymbols = parser.parse(mapData.string(format: .utf8))
            for sym in inputSymbols where globalSymbols[sym.name] == nil {
                globalSymbols[sym.name] = sym.address
            }
        }

        if let bssPath = bssEntryListPath,
           let bssData = fileSystem.readFile(at: bssPath)?.allData {
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

        for section in layout.textSections {
            let files = manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: codeFolder,
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
            let source = try Self.collectDataSectionFiles(
                section.name,
                codeFolder: codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader,
                structs: resolvedStructs,
                labelTable: labelTable,
                registry: registry,
                counts: counts,
                allowResizedChunks: allowResizedChunks,
                logger: logger
            )
            if !source.files.isEmpty {
                let assembled = try assembler.assembleReportingFileLengths(
                    files: source.files, baseAddress: section.address, externalSymbols: globalSymbols
                )
                // Every other chunk type was held to its recorded size before
                // assembly; an assembly chunk is text the assembler consumes
                // verbatim, so this is the first point its length is known.
                for (name, length) in assembled.fileLengths {
                    guard let recorded = source.assemblySizes[name], recorded.recorded != length else { continue }
                    if length > recorded.recorded, !allowResizedChunks {
                        throw DolAssemblyErrors.chunkOverflow(
                            section: section.name, label: recorded.label,
                            recorded: recorded.recorded, assembled: length, .init()
                        )
                    }
                    logger?.log(.warning(
                        "\(section.name) assembly chunk '\(recorded.label)' assembled to \(length) bytes, "
                        + "\(abs(length - recorded.recorded)) \(length > recorded.recorded ? "more" : "fewer") "
                        + "than the \(recorded.recorded) it was dumped at — everything after it in "
                        + "\(section.name) shifts."
                    ))
                }
                if let recorded = section.size, UInt32(assembled.data.length) != recorded {
                    let assembledSize = assembled.data.length
                    if assembledSize > Int(recorded), !allowResizedChunks {
                        throw DolAssemblyErrors.sectionOverflow(
                            section: section.name, recorded: Int(recorded),
                            assembled: assembledSize, .init()
                        )
                    }
                    logger?.log(.warning(
                        "\(section.name) assembled to \(assembledSize) bytes against the \(recorded) "
                        + "sections.txt records."
                    ))
                }
                dataSections.append(.init(RAMAddress: section.address, data: assembled.data))
            } else {
                dataSections.append(.init(RAMAddress: section.address, data: .none))
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Assemble DOL", status: .progress(pct)))
            }
        }

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
        let sdaBases = Self.resolveSDABases(sdaBase: sdaBase, sda2Base: sda2Base, assembledTextSections: textSections)
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

        let dol = Dol(
            dolphinEngine: dolphinEngine,
            textSections: textSections,
            dataSections: dataSections,
            bssRAMAddress: layout.bssAddress,
            bssSize: layout.bssSize,
            entryPoint: layout.entryPoint
        )

        let dolData = try dol.data
        try fileSystem.writeFile(dolData, at: outputDolPath, overwrite: true)

        if let outputSymbolMapPath {
            let dataSectionRanges = layout.dataSections.enumerated().map { index, info in
                (
                    start: info.address,
                    end: info.address &+ UInt32(index < dataSections.count ? dataSections[index].data.length : 0)
                )
            }
            try Self.writeSymbolMap(
                to: outputSymbolMapPath,
                inputSymbols: inputSymbols,
                assembledSymbols: globalSymbols,
                dataSectionLabels: dataSectionLabels,
                dataSectionRanges: dataSectionRanges,
                in: fileSystem,
                logger: logger
            )
        }

        logger?.log(.taskStatus(taskName: "Assemble DOL", status: .completed(true)))
        logger?.log(.info("DOL written to \(outputDolPath.path) (\(dolData.length) bytes)"))
    }

    /// Re-emit the symbol map with the addresses this assembly produced.
    ///
    /// A DOL's symbol map is addresses, and the type map layered on it names
    /// chunks by label, so a chunk that re-encodes to a different size leaves
    /// every later symbol somewhere the map doesn't know and the next
    /// disassembly types the wrong bytes. Writing the map back closes that
    /// loop: the names stay put and the addresses follow the rebuild.
    ///
    /// Two sets go in. The **input map's symbols** keep their size, section
    /// and object file — those columns decide how the next disassembly
    /// groups text into per-object folders, so losing them would reshape the
    /// source tree — and take whatever address the assembly gave the label of
    /// that name, falling back to the address they came in with for symbols
    /// the source never defines (hardware registers, BSS interiors). The
    /// **data-section labels** are added whether or not the map had them,
    /// because on a game like XD the type map's tables are named by
    /// `lbl_XXXXXXXX` auto-labels that were never in the map to begin with,
    /// and those are exactly the names a shift would strand.
    ///
    /// A new label's size is the gap to the next label, which is what the
    /// disassembler's own chunking uses; the input map's sizes are left
    /// alone, since nothing here can measure a text symbol.
    ///
    /// One case is knowingly not covered: a map symbol inside a data section
    /// that the disassembler kept out of the chunk boundaries (a misaligned
    /// string or byte global — it warns about these) defines no label, so it
    /// keeps its old address and is wrong by the shift. Those are already
    /// documented as not shiftable.
    private static func writeSymbolMap(
        to path: File,
        inputSymbols: [PPCSymbol],
        assembledSymbols: [String: UInt32],
        dataSectionLabels: [String: UInt32],
        dataSectionRanges: [(start: UInt32, end: UInt32)],
        in fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        var output = [PPCSymbol]()
        var moved = 0
        var known = Set<String>()

        for symbol in inputSymbols {
            let address = assembledSymbols[symbol.name] ?? symbol.address
            if address != symbol.address { moved += 1 }
            known.insert(symbol.name)
            output.append(PPCSymbol(
                name: symbol.name,
                address: address,
                size: symbol.size,
                section: symbol.section,
                sourceFile: symbol.sourceFile
            ))
        }

        // Size a new label by the distance to the next one in its section.
        var boundariesBySection = [Int: [UInt32]]()
        func sectionIndex(of address: UInt32) -> Int? {
            dataSectionRanges.firstIndex { address >= $0.start && address < $0.end }
        }
        for (_, address) in dataSectionLabels {
            guard let index = sectionIndex(of: address) else { continue }
            boundariesBySection[index, default: []].append(address)
        }
        for index in boundariesBySection.keys {
            boundariesBySection[index]?.sort()
        }

        for (name, address) in dataSectionLabels where !known.contains(name) {
            var size: UInt32 = 0
            if let index = sectionIndex(of: address), let boundaries = boundariesBySection[index] {
                let next = boundaries.first(where: { $0 > address }) ?? dataSectionRanges[index].end
                size = next &- address
            }
            output.append(PPCSymbol(name: name, address: address, size: size, section: ".data"))
        }

        let sectionOrder = inputSymbols.reduce(into: [String]()) { order, symbol in
            if let section = symbol.section, !order.contains(section) { order.append(section) }
        }
        let text = SymbolMapWriter().write(output, sectionOrder: sectionOrder)
        try fileSystem.writeFile(GoDData(string: text, format: .utf8), at: path, overwrite: true)

        let added = output.count - inputSymbols.count
        logger?.log(.info(
            "Symbol map written to \(path.path) (\(output.count) symbols, "
            + "\(moved) moved, \(added) added from the assembled data sections)"
        ))
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
        counts: CountPlan,
        allowResizedChunks: Bool,
        logger: Logger?
    ) throws -> DataSectionSource {
        let sectionFolder = codeFolder.folder(sectionName)

        if let manifest = manifestReader.readDataManifest(from: sectionFolder, fileSystem: fileSystem) {
            var source = DataSectionSource()
            for chunk in manifest.chunks {
                let file = sectionFolder.file(chunk.file)
                switch chunk.type {
                case .assembly:
                    if let data = fileSystem.readFile(at: file)?.allData {
                        source.files.append((name: chunk.file, content: data.string(format: .utf8)))
                        if let recorded = chunk.size {
                            source.assemblySizes[chunk.file] = (label: chunk.label, recorded: recorded)
                        }
                    } else {
                        logger?.log(.warning("Assembly chunk '\(chunk.label)' dropped: \(chunk.file) missing — section \(sectionName) will come out short"))
                    }
                case .binary:
                    if let data = fileSystem.readFile(at: file)?.allData {
                        source.files.append((
                            name: "\(chunk.label).synthesized.s",
                            content: renderByteBlocksAsAssembly(
                                sectionName: sectionName,
                                chunkLabel: chunk.label,
                                blocks: try Self.fitToRecordedSize(
                                    [(label: nil, bytes: data)],
                                    chunk: chunk, sectionName: sectionName,
                                    allowResizedChunks: allowResizedChunks, logger: logger
                                )
                            )
                        ))
                    } else {
                        logger?.log(.warning("Binary chunk '\(chunk.label)' dropped: \(chunk.file) missing — section \(sectionName) will come out short"))
                    }
                case .file:
                    if let data = Self.fileChunkBinary(
                        chunk: chunk,
                        sectionFolder: sectionFolder,
                        fileSystem: fileSystem,
                        registry: registry,
                        logger: logger
                    ) {
                        source.files.append((
                            name: "\(chunk.label).synthesized.s",
                            content: renderByteBlocksAsAssembly(
                                sectionName: sectionName,
                                chunkLabel: chunk.label,
                                blocks: try Self.fitToRecordedSize(
                                    Self.splitAtInteriorLabels(data, chunk: chunk, logger: logger),
                                    chunk: chunk, sectionName: sectionName,
                                    allowResizedChunks: allowResizedChunks, logger: logger
                                )
                            )
                        ))
                    } else {
                        logger?.log(.warning("File chunk '\(chunk.label)' dropped: no rebuildable artifacts for \(chunk.file) — section \(sectionName) will come out short"))
                    }
                case .count:
                    let entries = counts.tableCounts[chunk.countOf ?? ""] ?? 0
                    let type = chunk.countType ?? .uint32
                    guard let bytes = type.countBytes(entries) else {
                        throw DolAssemblyErrors.countOverflow(
                            section: sectionName, label: chunk.label, table: chunk.countOf ?? "",
                            entries: entries, type: type.rawValue, .init()
                        )
                    }
                    source.files.append((
                        name: "\(chunk.label).synthesized.s",
                        content: renderByteBlocksAsAssembly(
                            sectionName: sectionName,
                            chunkLabel: chunk.label,
                            blocks: [(label: nil, bytes: GoDData(byteStream: bytes, byteOrder: .big))]
                        )
                    ))
                case .struct, .table:
                    if let blocks = Self.typedChunkBlocks(
                        chunk: chunk,
                        sizedByCSV: counts.countedTables.contains(chunk.label),
                        sectionFolder: sectionFolder,
                        fileSystem: fileSystem,
                        structs: structs,
                        labelTable: labelTable,
                        logger: logger
                    ) {
                        source.files.append((
                            name: "\(chunk.label).synthesized.s",
                            content: renderByteBlocksAsAssembly(
                                sectionName: sectionName,
                                chunkLabel: chunk.label,
                                blocks: try Self.fitToRecordedSize(
                                    blocks,
                                    chunk: chunk, sectionName: sectionName,
                                    allowResizedChunks: allowResizedChunks, logger: logger
                                )
                            )
                        ))
                    } else {
                        logger?.log(.warning("Typed chunk '\(chunk.label)' dropped: JSON missing or undecodable — section \(sectionName) will come out short"))
                    }
                }
            }
            return source
        }

        // Fall back to folder with .s files
        if fileSystem.inspectFolder(at: sectionFolder) != nil {
            return DataSectionSource(
                files: Self.collectAssemblyFiles(from: sectionFolder, fileSystem: fileSystem)
            )
        }

        // Fall back to single file
        let sectionFile = codeFolder.file("\(sectionName).s")
        if let data = fileSystem.readFile(at: sectionFile)?.allData {
            return DataSectionSource(files: [(sectionName + ".s", data.string(format: .utf8))])
        }
        return DataSectionSource()
    }

    /// The assembly sources for one data section, plus what the manifest
    /// said each `.assembly` chunk used to weigh.
    ///
    /// Every other chunk type is rebuilt from bytes this file holds, so its
    /// size is known — and enforced — before assembly. An assembly chunk is
    /// text handed straight to the assembler, so its length only becomes
    /// known once the section is encoded; `assemblySizes` is what lets the
    /// caller check it afterwards.
    /// Which tables a count derives from, and how many entries each will
    /// be rebuilt with. Settled before any section renders, because a count
    /// can sit ahead of its table or in another section.
    struct CountPlan {
        var countedTables = Set<String>()
        var tableCounts = [String: Int]()
    }

    /// Reads every data section's manifest for `count` chunks. A counted
    /// table's entry count is its CSV's row count; any other table keeps its
    /// manifest count. A count naming anything but a table chunk is an
    /// error, the same rule the type map is held to at dump time.
    private static func planCounts(
        dataSections: [String],
        codeFolder: Folder,
        fileSystem: FileSystemTree,
        manifestReader: ManifestReader,
        structs: [String: StructDefinition]
    ) throws -> CountPlan {
        var plan = CountPlan()
        var tables = [String: (chunk: DataSectionManifest.Chunk, folder: Folder)]()
        var countChunks = [(section: String, chunk: DataSectionManifest.Chunk)]()
        for name in dataSections {
            let folder = codeFolder.folder(name)
            for chunk in manifestReader.readDataManifest(from: folder, fileSystem: fileSystem)?.chunks ?? [] {
                if chunk.type == .table { tables[chunk.label] = (chunk, folder) }
                if chunk.type == .count { countChunks.append((name, chunk)) }
            }
        }
        for (section, chunk) in countChunks {
            guard let table = chunk.countOf, tables[table] != nil else {
                throw DolAssemblyErrors.countTargetNotATable(section: section, label: chunk.label, table: chunk.countOf, .init())
            }
            plan.countedTables.insert(table)
        }
        for (label, table) in tables {
            var entries = table.chunk.count
            if plan.countedTables.contains(label),
               let type = table.chunk.structType, let definition = structs[type],
               let csv = fileSystem.readFile(at: table.folder.file(table.chunk.file))?.allData,
               let decoded = try? StructTableCSV.decode(csv.string(format: .utf8), definition: definition, byteOrder: .big) {
                entries = decoded.entries.count
            }
            plan.tableCounts[label] = entries ?? 0
        }
        return plan
    }

    struct DataSectionSource {
        var files: [(name: String, content: String)] = []
        var assemblySizes: [String: (label: String, recorded: Int)] = [:]
    }

    /// Cut a rebuilt file into blocks at the symbols that live inside it,
    /// so each one is re-emitted as a label at the same offset.
    ///
    /// A file chunk normally has no interior symbols — the disassembler
    /// ends a chunk at the next one. It keeps going only when the format
    /// measured itself past a symbol (XD's health-warning texture and its
    /// `tex_warning` palette), and that symbol is a real relocation target,
    /// so dropping it would leave the code pointing at a stale address.
    ///
    /// An offset past the rebuilt file is dropped with a warning rather
    /// than silently losing the label: it means the file re-encoded shorter
    /// than the symbol it used to contain.
    private static func splitAtInteriorLabels(
        _ data: GoDData,
        chunk: DataSectionManifest.Chunk,
        logger: Logger?
    ) -> [(label: String?, bytes: GoDData)] {
        guard let interior = chunk.interiorLabels, !interior.isEmpty else {
            return [(label: nil, bytes: data)]
        }
        let cuts = interior
            .compactMap { key, name -> (offset: Int, name: String)? in
                guard let offset = Int(key), offset > 0 else { return nil }
                guard offset < data.length else {
                    logger?.log(.warning(
                        "Interior label '\(name)' sits \(offset) bytes into '\(chunk.label)', which "
                        + "rebuilt to only \(data.length) bytes — the label is dropped."
                    ))
                    return nil
                }
                return (offset: offset, name: name)
            }
            .sorted { $0.offset < $1.offset }
        guard !cuts.isEmpty else { return [(label: nil, bytes: data)] }

        // The chunk's own label is emitted by the renderer, so the first
        // block carries none; each cut names the block that starts at it.
        var blocks = [(label: String?, bytes: GoDData)]()
        var start = 0
        var pendingLabel: String?
        let bytes = data.byteStream
        for cut in cuts {
            blocks.append((
                label: pendingLabel,
                bytes: GoDData(byteStream: Array(bytes[start..<cut.offset]), byteOrder: .big)
            ))
            pendingLabel = cut.name
            start = cut.offset
        }
        blocks.append((
            label: pendingLabel,
            bytes: GoDData(byteStream: Array(bytes[start...]), byteOrder: .big)
        ))
        return blocks
    }

    /// Hold a rebuilt chunk to the extent the disassembly recorded for it.
    ///
    /// A chunk runs from its own symbol to the next one, so its length is
    /// part of the section's layout, not a property of its contents: let a
    /// chunk re-encode shorter or longer and every symbol after it in the
    /// section moves. The symbol map the next disassembly reads is keyed by
    /// address and the type map on top of it names chunks by label, so that
    /// shift is what turns a table into garbage rows on a second dump.
    ///
    /// Short is recoverable and common — a re-encoded `.msg` re-derives its
    /// own string layout and can land a few bytes under — so the gap is
    /// zero-filled and reported. Those bytes belong to the chunk and the
    /// formats that own them carry their own lengths, so nothing reads them.
    ///
    /// Long cannot be absorbed and stops the assembly, unless the caller has
    /// explicitly accepted resized chunks; the rebuild then rewrites the
    /// symbol map, which is what keeps a deliberate shift usable.
    ///
    /// A manifest from before chunk sizes were recorded has no `size`, and
    /// nothing is enforced for it.
    private static func fitToRecordedSize(
        _ blocks: [(label: String?, bytes: GoDData)],
        chunk: DataSectionManifest.Chunk,
        sectionName: String,
        allowResizedChunks: Bool,
        logger: Logger?
    ) throws -> [(label: String?, bytes: GoDData)] {
        guard let recorded = chunk.size else { return blocks }
        let assembled = blocks.reduce(0) { $0 + $1.bytes.length }
        if assembled == recorded { return blocks }

        if assembled > recorded {
            guard allowResizedChunks else {
                throw DolAssemblyErrors.chunkOverflow(
                    section: sectionName, label: chunk.label,
                    recorded: recorded, assembled: assembled, .init()
                )
            }
            logger?.log(.warning(
                "\(sectionName) chunk '\(chunk.label)' rebuilt \(assembled - recorded) bytes longer than "
                + "the \(recorded) it was dumped at — everything after it in \(sectionName) shifts."
            ))
            return blocks
        }

        logger?.log(.warning(
            "\(sectionName) chunk '\(chunk.label)' rebuilt \(recorded - assembled) bytes shorter than "
            + "the \(recorded) it was dumped at; padding with zeroes to keep the following symbols in place."
        ))
        return blocks + [(label: nil, bytes: GoDData(length: recorded - assembled, byteOrder: .big))]
    }

    /// Resolve the small-data-area base addresses (r13 = _SDA_BASE_,
    /// r2 = _SDA2_BASE_). Explicit config values win; otherwise scan the
    /// assembled text for the canonical __init_registers sequence —
    /// `lis r13/r2, hi` followed by `ori`/`addi` with the same register as
    /// source and destination. r2/r13 are ABI-reserved, so the pattern is
    /// unambiguous.
    private static func resolveSDABases(
        sdaBase: UInt32?,
        sda2Base: UInt32?,
        assembledTextSections: [Dol.TextSection]
    ) -> [(name: String, address: UInt32)] {
        var bases = [(name: String, address: UInt32)]()
        if let r13 = sdaBase { bases.append((name: "_SDA_BASE_ (r13)", address: r13)) }
        if let r2 = sda2Base { bases.append((name: "_SDA2_BASE_ (r2)", address: r2)) }
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
        return fileSystem.readFile(at: sectionFolder.file(chunk.file))?.allData
    }

    /// Decode a `.struct` chunk's JSON or a `.table` chunk's CSV into the
    /// labelled byte blocks it rebuilds to. Returns nil when the file is
    /// missing, its struct type is unresolved, or decoding fails — the
    /// caller drops the chunk with a warning.
    ///
    /// Blocks rather than finished assembly text so the caller can measure
    /// the chunk against its recorded size, and pad it, before rendering.
    private static func typedChunkBlocks(
        chunk: DataSectionManifest.Chunk,
        sizedByCSV: Bool,
        sectionFolder: Folder,
        fileSystem: FileSystemTree,
        structs: [String: StructDefinition],
        labelTable: LabelTable,
        logger: Logger?
    ) -> [(label: String?, bytes: GoDData)]? {
        guard let structType = chunk.structType else {
            logger?.log(.warning("Typed chunk '\(chunk.label)' has no structType in the manifest"))
            return nil
        }
        guard let definition = structs[structType] else {
            logger?.log(.warning("Struct type '\(structType)' for chunk '\(chunk.label)' not resolved — is typeMapPath set in the config?"))
            return nil
        }
        guard let chunkData = fileSystem.readFile(at: sectionFolder.file(chunk.file))?.allData else {
            return nil
        }
        let importer = TypedDataImporter()

        switch chunk.type {
        case .struct:
            do {
                let structData = try StructData(definition: definition, json: chunkData, byteOrder: .big)
                let bytes = importer.importStruct(structData: structData, labelTable: labelTable, byteOrder: .big)
                return [(label: nil, bytes: bytes)]
            } catch {
                logger?.log(.warning("Struct chunk '\(chunk.label)' JSON failed to decode: \(error)"))
                return nil
            }

        case .table:
            // Tables are CSV. A `.json` here is a dump from before that
            // change — say so rather than failing to parse it as CSV.
            guard chunk.file.hasSuffix(".csv") else {
                logger?.log(.warning(
                    "Table chunk '\(chunk.label)' is '\(chunk.file)', not a .csv — "
                    + "this disassembly predates CSV tables. Re-run the disassembly to regenerate it."
                ))
                return nil
            }

            let decoded: StructTableCSV.DecodeResult
            do {
                decoded = try StructTableCSV.decode(
                    chunkData.string(format: .utf8), definition: definition, byteOrder: .big
                )
            } catch {
                logger?.log(.warning("Table chunk '\(chunk.label)' failed to decode: \(error)"))
                return nil
            }
            for warning in decoded.warnings {
                logger?.log(.warning("Table '\(chunk.label)': \(warning)"))
            }

            // Pad-or-truncate to the manifest's declared count so the
            // section layout stays stable even if the CSV was
            // hand-edited to add/remove rows — unless something counts the
            // table, in which case the CSV is its length and the count
            // follows. The chunk is still held to its recorded size after
            // this, so a counted table that grows needs allowResizedChunks.
            let count = sizedByCSV ? decoded.entries.count : (chunk.count ?? decoded.entries.count)
            if decoded.entries.count > count {
                logger?.log(.warning("Table '\(chunk.label)': \(decoded.entries.count - count) surplus entries dropped (manifest count is \(count))"))
            } else if decoded.entries.count < count {
                logger?.log(.warning("Table '\(chunk.label)': \(count - decoded.entries.count) missing entries zero-filled (manifest count is \(count))"))
            }

            var blocks = [(label: String?, bytes: GoDData)]()
            for i in 0..<count {
                // Entry symbols live in the manifest, not in the CSV — a row
                // holds the struct's fields and nothing else.
                let entryLabel = chunk.entryLabels?[String(i)]
                guard i < decoded.entries.count else {
                    blocks.append((label: entryLabel, bytes: GoDData(length: definition.length, byteOrder: .big)))
                    continue
                }
                let bytes = importer.importStruct(
                    structData: decoded.entries[i], labelTable: labelTable, byteOrder: .big
                )
                blocks.append((label: entryLabel, bytes: bytes))
            }
            return blocks

        case .assembly, .binary, .file, .count:
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
            if let data = fileSystem.readFile(at: file)?.allData {
                files.append((name: file.fileName, content: data.string(format: .utf8)))
            }
        }

        for subFolder in contents.subFolders {
            files.append(contentsOf: Self.collectAssemblyFiles(from: subFolder, fileSystem: fileSystem))
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

public enum DolAssemblyErrors: Error, CustomStringConvertible {
    case sectionsFileNotFound(file: File, ErrorTrace)
    case chunkOverflow(section: String, label: String, recorded: Int, assembled: Int, ErrorTrace)
    case sectionOverflow(section: String, recorded: Int, assembled: Int, ErrorTrace)
    case countTargetNotATable(section: String, label: String, table: String?, ErrorTrace)
    case countOverflow(section: String, label: String, table: String, entries: Int, type: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .sectionsFileNotFound(file, trace):
            return "sections.txt not found: \(file)\n\(trace)"
        case let .chunkOverflow(section, label, recorded, assembled, trace):
            return """
            \(section) chunk '\(label)' rebuilt \(assembled - recorded) bytes longer than the \(recorded) \
            it was dumped at (now \(assembled)). Everything after it in \(section) would shift, which moves \
            every symbol the disassembly named. Shrink the chunk, or set "allowResizedChunks": true to accept \
            the shift — the assembly then rewrites the symbol map so the next dump can still find them.
            \(trace)
            """
        case let .sectionOverflow(section, recorded, assembled, trace):
            return """
            \(section) assembled to \(assembled) bytes, \(assembled - recorded) more than the \(recorded) \
            sections.txt records. A data section cannot grow past the next one's address. Shrink it, or set \
            "allowResizedChunks": true to accept the shift.
            \(trace)
            """
        case let .countTargetNotATable(section, label, table, trace):
            return "\(section) count '\(label)' counts '\(table ?? "(nothing)")', which isn't a table chunk in this DOL\n\(trace)"
        case let .countOverflow(section, label, table, entries, type, trace):
            return "\(section) count '\(label)' is a \(type), which can't hold the \(entries) entries '\(table)' now has\n\(trace)"
        }
    }
}
