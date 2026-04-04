import GoDFoundation
import Dolphin

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

        logger?.log(.info("Disassembling DOL (\(hasSymbols ? "shiftable" : "non-shiftable") mode)"))
        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .started))

        // Build everything in memory first
        let output = InMemoryFST()
        let relocAnalyzer = PPCRelocAnalyzer()

        let textSections = dol.textSections.enumerated().filter { $0.element.assembly.length > 0 }
        let dataSections = dol.dataSections.enumerated().filter { $0.element.data.length > 0 }
        let totalSections = textSections.count + dataSections.count
        var sectionsProcessed = 0

        // Disassemble text sections
        for (index, section) in textSections {
            let sectionName = "text\(index)"
            let bytes = section.assembly.rawBytes
            let instructions = decoder.decodeAll(bytes, baseAddress: section.RAMAddress)
            let sectionEnd = section.RAMAddress + UInt32(section.assembly.length)

            if hasSymbols {
                let sectionSymbols = allSymbols.filter {
                    $0.address >= section.RAMAddress && $0.address < sectionEnd
                }

                // Run relocation analysis for shiftable output
                let relocations = relocAnalyzer.analyze(
                    instructions,
                    symbols: symbolLookup,
                    sectionRanges: sectionRanges
                )

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

                    for function in functions {
                        let subfolder: Folder
                        if let objFile = symbolFileMap[function.name] {
                            subfolder = sectionFolder.folder(objFile)
                        } else {
                            subfolder = sectionFolder
                        }
                        let file = subfolder.file("\(function.name).s")
                        output.writeFile(GoDData(string: function.text, format: .utf8), at: file, overwrite: true)
                    }
                } else {
                    // Symbols exist but none in this section — single file with relocations
                    let text = formatter.formatAssembly(instructions, relocations: relocations, sectionName: ".\(sectionName)")
                    let file = outputFolder.file("\(sectionName).s")
                    output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
                }
            } else {
                // No symbol map — single file with auto-generated branch labels
                let text = formatter.formatAssembly(instructions, sectionName: ".\(sectionName)")
                let file = outputFolder.file("\(sectionName).s")
                output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Data sections
        for (index, section) in dataSections {
            let sectionName = "data\(index)"
            let bytes = section.data.rawBytes

            let text = formatter.formatDataSection(
                bytes,
                baseAddress: section.RAMAddress,
                symbols: symbolLookup,
                sectionName: ".\(sectionName)"
            )

            let file = outputFolder.file("\(sectionName).s")
            output.writeFile(GoDData(string: text, format: .utf8), at: file, overwrite: true)

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Section layout summary
        var summary = [String]()
        summary.append("# DOL Section Layout")
        summary.append("# Entry point: 0x\(String(dol.entryPoint, radix: 16, uppercase: true))")
        summary.append("# BSS: 0x\(String(dol.bssRAMAddress, radix: 16, uppercase: true)) (\(dol.bssSize) bytes)")
        if hasSymbols {
            summary.append("# Symbols: \(allSymbols.count)")
        }
        summary.append("")
        for (i, s) in textSections {
            summary.append("text\(i): 0x\(String(s.RAMAddress, radix: 16, uppercase: true)) (\(s.assembly.length) bytes)")
        }
        for (i, s) in dataSections {
            summary.append("data\(i): 0x\(String(s.RAMAddress, radix: 16, uppercase: true)) (\(s.data.length) bytes)")
        }
        output.writeFile(GoDData(string: summary.joined(separator: "\n"), format: .utf8), at: outputFolder.file("sections.txt"), overwrite: true)

        // Write everything to disk at once
        fileSystem.importFST(output, from: outputFolder, to: config.outputFolder, overwrite: true)

        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .completed(true)))
    }
}

enum DolDisassemblyErrors: Error, CustomStringConvertible {
    case dolNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .dolNotFound(file, trace):
            return "DOL file not found: \(file)\n\(trace)"
        }
    }
}
