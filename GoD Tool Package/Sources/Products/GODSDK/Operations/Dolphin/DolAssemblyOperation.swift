import GoDFoundation
import Dolphin

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
        let layout = parseSectionsFile(sectionsData.string(format: .utf8))

        let assembler = PPCSectionAssembler()
        var textSections = [Dol.TextSection]()
        var dataSections = [Dol.DataSection]()

        let totalSections = layout.textSections.count + layout.dataSections.count
        var sectionsProcessed = 0

        // Assemble text sections
        for section in layout.textSections {
            let sectionFolder = config.codeFolder.folder(section.name)

            if let folderContents = fileSystem.inspectFolder(at: sectionFolder) {
                // Per-function files in subfolders — collect all .s files recursively
                let files = collectAssemblyFiles(from: sectionFolder, fileSystem: fileSystem)

                if !files.isEmpty {
                    let assembled = try assembler.assemble(files: files, baseAddress: section.address)
                    textSections.append(.init(RAMAddress: section.address, assembly: assembled))
                } else {
                    textSections.append(.init(RAMAddress: section.address, assembly: .none))
                }
            } else {
                // No folder — check for a single section .s file
                let sectionFile = config.codeFolder.file("\(section.name).s")
                if let fileData = fileSystem.readFile(at: sectionFile) {
                    let content = fileData.string(format: .utf8)
                    let assembled = try assembler.assemble(files: [(section.name + ".s", content)], baseAddress: section.address)
                    textSections.append(.init(RAMAddress: section.address, assembly: assembled))
                } else {
                    textSections.append(.init(RAMAddress: section.address, assembly: .none))
                }
            }

            sectionsProcessed += 1
            if logger != nil {
                let pct = Percentage(Double(sectionsProcessed) / Double(totalSections) * 100)
                logger?.log(.taskStatus(taskName: "Assemble DOL", status: .progress(pct)))
            }
        }

        // Assemble data sections
        for section in layout.dataSections {
            let sectionFile = config.codeFolder.file("\(section.name).s")
            if let fileData = fileSystem.readFile(at: sectionFile) {
                let content = fileData.string(format: .utf8)
                let assembled = try assembler.assemble(files: [(section.name + ".s", content)], baseAddress: section.address)
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

    // MARK: - Collect .s files recursively

    private static func collectAssemblyFiles(
        from folder: Folder,
        fileSystem: FileSystemTree
    ) -> [(name: String, content: String)] {
        guard let contents = fileSystem.inspectFolder(at: folder) else { return [] }

        var files = [(name: String, content: String)]()

        // Collect .s files in this folder
        for file in contents.files where file.fileType == "s" {
            if let data = fileSystem.readFile(at: file) {
                files.append((name: file.fileName, content: data.string(format: .utf8)))
            }
        }

        // Recurse into subfolders
        for subFolder in contents.subFolders {
            files.append(contentsOf: collectAssemblyFiles(from: subFolder, fileSystem: fileSystem))
        }

        return files
    }

    // MARK: - sections.txt parser

    struct SectionInfo {
        let name: String
        let address: UInt32
    }

    struct DolLayout {
        var entryPoint: UInt32 = 0
        var bssAddress: UInt32 = 0
        var bssSize: UInt32 = 0
        var textSections = [SectionInfo]()
        var dataSections = [SectionInfo]()
    }

    private static func parseSectionsFile(_ text: String) -> DolLayout {
        var layout = DolLayout()

        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)

            // # Entry point: 0x80003154
            if s.hasPrefix("# Entry point:") {
                let hex = s.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
                if hex.hasPrefix("0x"), let val = UInt32(hex.dropFirst(2), radix: 16) {
                    layout.entryPoint = val
                }
                continue
            }

            // # BSS: 0x804205C0 (849860 bytes)
            if s.hasPrefix("# BSS:") {
                let parts = s.dropFirst(6).trimmingCharacters(in: .whitespaces).split(separator: " ")
                if let addrStr = parts.first, addrStr.hasPrefix("0x"),
                   let addr = UInt32(addrStr.dropFirst(2), radix: 16) {
                    layout.bssAddress = addr
                }
                if let sizeStr = parts.dropFirst().first?.replacingOccurrences(of: "(", with: ""),
                   let size = UInt32(sizeStr) {
                    layout.bssSize = size
                }
                continue
            }

            // text0: 0x80003100 (9472 bytes)
            if s.hasPrefix("text") {
                if let info = parseSectionLine(s) {
                    layout.textSections.append(info)
                }
            }
            if s.hasPrefix("data") {
                if let info = parseSectionLine(s) {
                    layout.dataSections.append(info)
                }
            }
        }

        return layout
    }

    private static func parseSectionLine(_ s: String) -> SectionInfo? {
        // "text0: 0x80003100 (9472 bytes)"
        let parts = s.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let rest = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let addrStr = rest.split(separator: " ").first ?? ""
        guard addrStr.hasPrefix("0x"), let addr = UInt32(addrStr.dropFirst(2), radix: 16) else { return nil }
        return SectionInfo(name: name, address: addr)
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
