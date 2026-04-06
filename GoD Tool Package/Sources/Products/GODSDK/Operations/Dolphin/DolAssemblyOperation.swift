import GoDFoundation
import Dolphin
import Disassembler

enum DolAssembly {
    static func assemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
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

        // Pre-scan: collect all labels from all sections to build global symbol table
        var globalSymbols = [String: UInt32]()

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
            let files = collectDataSectionFiles(
                section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader
            )
            let labels = assembler.collectLabelsOnly(files: files, baseAddress: section.address)
            globalSymbols.merge(labels) { existing, _ in existing }
        }

        // Scan all text section files for lbl_XXXXXXXX references that point to BSS or
        // other areas not covered by the section files (auto-generated relocation labels)
        for section in layout.textSections {
            let files = manifestReader.loadTextSectionFiles(
                sectionName: section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem
            )
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

        // Assemble data sections
        for section in layout.dataSections {
            let files = collectDataSectionFiles(
                section.name,
                codeFolder: config.codeFolder,
                fileSystem: fileSystem,
                manifestReader: manifestReader
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
        fileSystem.writeFile(dolData, at: config.outputDolPath, overwrite: true)

        logger?.log(.taskStatus(taskName: "Assemble DOL", status: .completed(true)))
        logger?.log(.info("DOL written to \(config.outputDolPath.path) (\(dolData.length) bytes)"))
    }

    /// Collect assembly files for a data section.
    /// Checks for manifest first, falls back to single file.
    private static func collectDataSectionFiles(
        _ sectionName: String,
        codeFolder: Folder,
        fileSystem: FileSystemTree,
        manifestReader: ManifestReader
    ) -> [(name: String, content: String)] {
        let sectionFolder = codeFolder.folder(sectionName)

        // Check for data section manifest
        if let manifest = manifestReader.readDataManifest(from: sectionFolder, fileSystem: fileSystem) {
            // For now, only collect .s assembly chunks from the manifest
            // TODO: Handle struct/table/binary chunks via DataSectionImporter
            var files = [(name: String, content: String)]()
            for chunk in manifest.chunks where chunk.type == .assembly {
                let file = sectionFolder.file(chunk.file)
                if let data = fileSystem.readFile(at: file) {
                    files.append((name: chunk.file, content: data.string(format: .utf8)))
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

enum DolAssemblyErrors: Error, CustomStringConvertible {
    case sectionsFileNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .sectionsFileNotFound(file, trace):
            return "sections.txt not found: \(file)\n\(trace)"
        }
    }
}
