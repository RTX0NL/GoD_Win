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
        let outputFolder = config.outputFolder

        logger?.log(.info("Disassembling DOL (\(hasSymbols ? "with symbols" : "no symbols") mode)"))
        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .started))

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
                // Per-function splitting: find symbols that fall within this section
                let sectionSymbols = allSymbols.filter {
                    $0.address >= section.RAMAddress && $0.address < sectionEnd
                }

                if !sectionSymbols.isEmpty {
                    // Split into per-function files in a section subfolder
                    let sectionFolder = outputFolder.folder(sectionName)
                    let functions = formatter.splitByFunction(instructions, symbols: sectionSymbols, sectionName: ".\(sectionName)")

                    for function in functions {
                        let file = sectionFolder.file("\(function.name).s")
                        let data = GoDData(string: function.text, format: .utf8)
                        fileSystem.writeFile(data, at: file, overwrite: true)
                    }

                    // Also write a combined section file
                    let combined = formatter.formatAssembly(instructions, symbols: symbolLookup, sectionName: ".\(sectionName)")
                    let combinedFile = outputFolder.file("\(sectionName).s")
                    fileSystem.writeFile(GoDData(string: combined, format: .utf8), at: combinedFile, overwrite: true)
                } else {
                    // No symbols in this section — output as single file with auto-labels
                    let output = formatter.formatAssembly(instructions, sectionName: ".\(sectionName)")
                    let file = outputFolder.file("\(sectionName).s")
                    fileSystem.writeFile(GoDData(string: output, format: .utf8), at: file, overwrite: true)
                }
            } else {
                // No symbol map — output clean assembly with auto-generated branch labels
                let output = formatter.formatAssembly(instructions, sectionName: ".\(sectionName)")
                let file = outputFolder.file("\(sectionName).s")
                fileSystem.writeFile(GoDData(string: output, format: .utf8), at: file, overwrite: true)
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Output data sections
        for (index, section) in dataSections {
            let sectionName = "data\(index)"
            let bytes = section.data.rawBytes

            let output = formatter.formatDataSection(
                bytes,
                baseAddress: section.RAMAddress,
                symbols: symbolLookup,
                sectionName: ".\(sectionName)"
            )

            let file = outputFolder.file("\(sectionName).s")
            fileSystem.writeFile(GoDData(string: output, format: .utf8), at: file, overwrite: true)

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .progress(pct)))
            }
        }

        // Write section layout summary
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

        let summaryFile = outputFolder.file("sections.txt")
        fileSystem.writeFile(GoDData(string: summary.joined(separator: "\n"), format: .utf8), at: summaryFile, overwrite: true)

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
