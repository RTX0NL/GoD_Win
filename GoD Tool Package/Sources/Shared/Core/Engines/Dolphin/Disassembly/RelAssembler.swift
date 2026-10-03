//
//  RelAssembler.swift
//  Dolphin
//
//  The inverse of `RelDisassembler`: a source tree back into a `RELFile`.
//
//  Every section is rebuilt from the files the manifest points at. Text
//  sections assemble from their `.s`; data sections are rendered chunk by
//  chunk into assembler directives — `.bin` and embedded files as `.byte`
//  runs, CSV tables and struct JSON as `.byte` runs with `.4byte <symbol>` at
//  each pointer field, `.s` chunks verbatim — and assembled the same way.
//  Relocations fall out of that pass (see `assembleRelocatable`), then each
//  symbol resolves to a target: a label defined in any section of the module
//  first, the manifest's symbol table second. So moving a definition moves
//  every reference to it, and only targets the source cannot define need the
//  table.
//
//  The module's own labels are the source of truth over the manifest in the
//  other direction too: `_prolog`, `_epilog` and `_unresolved` labels set the
//  entry-point offsets when present, and any module a relocation targets is
//  added to the import list if the manifest forgot it.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Disassembler

public struct RelAssembler {

    private let registry: FileFormatRegistry?
    private let engineFolders: [Folder]

    /// - Parameters:
    ///   - registry: formats to rebuild embedded-file chunks through. Nil
    ///     reads them as the raw file the manifest names.
    ///   - engineFolders: engines whose structs resolve the manifest's
    ///     `structType` names, game definitions first.
    public init(registry: FileFormatRegistry? = nil, engineFolders: [Folder] = []) {
        self.registry = registry
        self.engineFolders = engineFolders
    }

    /// Rebuilds the module named `relName` from the source tree in `folder`.
    public func assemble(
        relName: String,
        in folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws -> RELFile {
        let manifestFile = folder.file(RelManifest.fileName(for: relName))
        guard let manifestData = fileSystem.readFile(at: manifestFile)?.allData else {
            throw RelAssemblerErrors.manifestNotFound(file: manifestFile, .init())
        }
        let manifest: RelManifest
        do {
            manifest = try RelManifest(json: manifestData)
        } catch {
            throw RelAssemblerErrors.invalidManifest(file: manifestFile, underlying: error, .init())
        }

        logger?.log(.taskStatus(taskName: "Assemble REL", status: .started))

        // Struct definitions for the typed chunks the manifest names.
        var structNames = Set<String>()
        for section in manifest.sections {
            for chunk in section.chunks ?? [] {
                if let name = chunk.structType { structNames.insert(name) }
            }
        }
        let structs = structNames.isEmpty
            ? [:]
            : resolveStructTypes(named: structNames, engineFolders: engineFolders, fileSystem: fileSystem, logger: logger)

        // ---- Counts ----

        // A table something counts is sized by its CSV — its count word is
        // derived from it, so a row added there is a row the game reads. One
        // nothing counts stays at its dumped size, since growing it would
        // leave whatever the game uses as its count stale.
        var countedTables = Set<String>()
        var tableLabels = Set<String>()
        for section in manifest.sections {
            for chunk in section.chunks ?? [] {
                if chunk.type == .table { tableLabels.insert(chunk.label) }
                if chunk.type == .count, let table = chunk.countOf { countedTables.insert(table) }
            }
        }
        for section in manifest.sections {
            for chunk in section.chunks ?? [] where chunk.type == .count {
                guard let table = chunk.countOf, tableLabels.contains(table) else {
                    throw RelAssemblerErrors.countTargetNotATable(count: chunk.label, table: chunk.countOf, .init())
                }
            }
        }
        var tableCounts = [String: Int]()

        // ---- Source for every section ----

        var sources: [Int: [(name: String, content: String)]] = [:]
        // Count chunks, rendered once every table's final size is known:
        // section → (position in its source list, chunk).
        var pendingCounts: [Int: [(position: Int, chunk: DataSectionManifest.Chunk)]] = [:]
        for section in manifest.sections {
            switch section.kind {
            case .empty, .bss:
                continue
            case .text:
                guard let path = section.file else {
                    throw RelAssemblerErrors.missingSource(section: section.index, file: manifestFile, .init())
                }
                let file = folder.file(path)
                guard let data = fileSystem.readFile(at: file)?.allData else {
                    throw RelAssemblerErrors.missingSource(section: section.index, file: file, .init())
                }
                sources[section.index] = [(name: path, content: data.string(format: .utf8))]
            case .data:
                var files = [(name: String, content: String)]()
                for chunk in section.chunks ?? [] {
                    if chunk.type == .count {
                        pendingCounts[section.index, default: []].append((files.count, chunk))
                        files.append((name: "", content: ""))
                        continue
                    }
                    files.append(try render(
                        chunk, sectionName: "data\(section.index)", folder: folder,
                        structs: structs, sizedByCSV: countedTables.contains(chunk.label),
                        tableCounts: &tableCounts, fileSystem: fileSystem, logger: logger
                    ))
                }
                sources[section.index] = files
            }
        }
        for (sectionIndex, pending) in pendingCounts {
            for (position, chunk) in pending {
                // Validated above: `countOf` names a table chunk, and every
                // table chunk records its count when it renders.
                let count = tableCounts[chunk.countOf ?? ""] ?? 0
                let type = chunk.countType ?? .uint32
                guard let bytes = type.countBytes(count) else {
                    throw RelAssemblerErrors.countOverflow(count: chunk.label, table: chunk.countOf ?? "", entries: count, type: type.rawValue, .init())
                }
                sources[sectionIndex]?[position] = (
                    name: "\(chunk.label).synthesized.s",
                    content: Self.renderBlocks(sectionName: "data\(sectionIndex)", label: chunk.label, blocks: [
                        .init(label: nil, bytes: bytes, pointers: [:])
                    ])
                )
            }
        }

        // ---- Labels defined anywhere in the module ----

        let assembler = PPCSectionAssembler()
        var definedLabels: [String: (section: Int, offset: UInt32)] = [:]
        for section in manifest.sections {
            guard let files = sources[section.index] else { continue }
            for (name, offset) in assembler.collectLabelsOnly(files: files, baseAddress: 0) {
                if let existing = definedLabels[name], existing.section != section.index {
                    logger?.log(.warning(
                        "Label '\(name)' is defined in section \(existing.section) and again in section "
                        + "\(section.index); the first definition wins."
                    ))
                    continue
                }
                definedLabels[name] = (section: section.index, offset: offset)
            }
        }
        let isKnownSymbol: (String) -> Bool = { definedLabels[$0] != nil || manifest.symbols[$0] != nil }

        func resolve(_ symbol: String, section: Int) throws -> RELFile.SymbolRef {
            if let label = definedLabels[symbol] {
                return RELFile.SymbolRef(moduleID: manifest.moduleID.uint32, section: UInt8(label.section), offset: label.offset)
            }
            if let entry = manifest.symbols[symbol] {
                return entry.ref
            }
            throw RelAssemblerErrors.unresolvedSymbol(symbol, section: section, .init())
        }

        // ---- Assemble ----

        var rel = RELFile(moduleID: manifest.moduleID.uint32, version: manifest.version)
        manifest.applyHeader(to: &rel)
        rel.name = relName

        var referencedModules = Set<UInt32>()
        var sections: [RELFile.Section] = []
        let workCount = manifest.sections.filter { $0.kind == .text || $0.kind == .data }.count
        var processed = 0

        for section in manifest.sections {
            switch section.kind {
            case .empty:
                sections.append(.init(index: section.index, body: .empty(fileOffset: section.fileOffset?.uint32 ?? 0)))
                continue
            case .bss:
                sections.append(.init(index: section.index, body: .bss(size: UInt32(section.size ?? 0))))
                continue
            case .text, .data:
                break
            }

            var restWords: [UInt32: UInt32] = [:]
            for (key, word) in section.restWords ?? [:] {
                guard let offset = RelManifest.offset(fromKey: key) else {
                    throw RelAssemblerErrors.invalidRestWordKey(key, section: section.index, .init())
                }
                restWords[offset] = word.uint32
            }

            let assembled = try assembler.assembleRelocatable(
                files: sources[section.index] ?? [],
                isKnownSymbol: isKnownSymbol,
                restWords: restWords
            )
            let bytes = assembled.data.rawBytes

            switch section.kind {
            case .text:
                var relocationsByWord: [Int: (ref: RELFile.SymbolRef, fixup: RELFile.RelocationFixup)] = [:]
                for site in assembled.relocations {
                    let ref = try resolve(site.symbol, section: section.index)
                    relocationsByWord[Int(site.offset) / 4] = (ref, Self.fixup(for: site.kind))
                    referencedModules.insert(ref.moduleID)
                }
                for fallback in section.relocations ?? [] {
                    let word = fallback.offset.value / 4
                    guard relocationsByWord[word] == nil else { continue }
                    let ref = try resolve(fallback.symbol, section: section.index)
                    relocationsByWord[word] = (ref, fallback.fixup)
                    referencedModules.insert(ref.moduleID)
                }
                var instructions: [RELFile.TextInstruction] = []
                instructions.reserveCapacity(bytes.count / 4)
                var offset = 0
                var word = 0
                while offset + 4 <= bytes.count {
                    let raw = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
                    if let reloc = relocationsByWord[word] {
                        instructions.append(.init(raw: raw, ref: reloc.ref, fixup: reloc.fixup))
                    } else {
                        instructions.append(.init(raw: raw))
                    }
                    offset += 4
                    word += 1
                }
                if offset != bytes.count {
                    throw RelAssemblerErrors.textNotWordAligned(section: section.index, size: bytes.count, .init())
                }
                sections.append(.init(index: section.index, body: .text(instructions)))

            case .data:
                var pointerAt: [Int: RELFile.SymbolRef] = [:]
                for site in assembled.relocations {
                    guard site.kind == .addr32 else {
                        throw RelAssemblerErrors.unsupportedDataRelocation(
                            symbol: site.symbol, kind: site.kind.rawValue, section: section.index, .init()
                        )
                    }
                    let ref = try resolve(site.symbol, section: section.index)
                    pointerAt[Int(site.offset)] = ref
                    referencedModules.insert(ref.moduleID)
                }
                for fallback in section.relocations ?? [] where fallback.fixup == .addr32 {
                    guard pointerAt[fallback.offset.value] == nil else { continue }
                    let ref = try resolve(fallback.symbol, section: section.index)
                    pointerAt[fallback.offset.value] = ref
                    referencedModules.insert(ref.moduleID)
                }
                var chunks: [RELFile.DataChunk] = []
                var cursor = 0
                for offset in pointerAt.keys.sorted() {
                    guard offset + 4 <= bytes.count else { break }
                    if offset > cursor {
                        chunks.append(.binary(bytes: Array(bytes[cursor..<offset])))
                    }
                    let word = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                             | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
                    chunks.append(.pointer(ref: pointerAt[offset]!, restValue: word))
                    cursor = offset + 4
                }
                if cursor < bytes.count {
                    chunks.append(.binary(bytes: Array(bytes[cursor..<bytes.count])))
                }
                if chunks.isEmpty {
                    chunks = [.binary(bytes: bytes)]
                }
                sections.append(.init(index: section.index, body: .data(chunks)))

            case .empty, .bss:
                break
            }

            processed += 1
            if logger != nil, workCount > 0 {
                let pct = Percentage(Double(processed) / Double(workCount) * 100)
                logger?.log(.taskStatus(taskName: "Assemble REL", status: .progress(pct)))
            }
        }
        rel.sections = sections

        // Entry points: a label in the source outranks the manifest's offset.
        if let prolog = definedLabels["_prolog"] {
            rel.prologSection = UInt8(prolog.section)
            rel.prologOffset = prolog.offset
        }
        if let epilog = definedLabels["_epilog"] {
            rel.epilogSection = UInt8(epilog.section)
            rel.epilogOffset = epilog.offset
        }
        if let unresolved = definedLabels["_unresolved"] {
            rel.unresolvedSection = UInt8(unresolved.section)
            rel.unresolvedOffset = unresolved.offset
        }

        // Every module a relocation targets needs an import-table entry, or
        // the writer would silently drop its edges.
        for module in referencedModules.sorted() where !rel.importedModules.contains(module) {
            logger?.log(.warning(
                "Relocations target module \(module) but the manifest's importedModules omits it; appending."
            ))
            rel.importedModules.append(module)
        }

        logger?.log(.taskStatus(taskName: "Assemble REL", status: .completed(true)))
        return rel
    }

    // MARK: - Chunk rendering

    /// Turns one manifest chunk into assembler source for the section it
    /// belongs to.
    private func render(
        _ chunk: DataSectionManifest.Chunk,
        sectionName: String,
        folder: Folder,
        structs: [String: StructDefinition],
        sizedByCSV: Bool,
        tableCounts: inout [String: Int],
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> (name: String, content: String) {
        let file = folder.file(chunk.file)

        switch chunk.type {
        case .count:
            // Rendered by the caller once every table's size is known.
            throw RelAssemblerErrors.countTargetNotATable(count: chunk.label, table: chunk.countOf, .init())

        case .assembly:
            guard let data = fileSystem.readFile(at: file)?.allData else {
                throw RelAssemblerErrors.missingChunk(label: chunk.label, file: file, .init())
            }
            return (name: chunk.file, content: data.string(format: .utf8))

        case .binary:
            guard let data = fileSystem.readFile(at: file)?.allData else {
                throw RelAssemblerErrors.missingChunk(label: chunk.label, file: file, .init())
            }
            return (
                name: "\(chunk.label).synthesized.s",
                content: Self.renderBlocks(sectionName: sectionName, label: chunk.label, blocks: [
                    .init(label: nil, bytes: data.rawBytes, pointers: [:])
                ])
            )

        case .file:
            let data = try embeddedFileBinary(chunk, file: file, fileSystem: fileSystem, logger: logger)
            // A file that measured itself past one of its own symbols keeps
            // those symbols; they are relocation targets, so each is put back
            // at the same offset inside the rebuilt file.
            return (
                name: "\(chunk.label).synthesized.s",
                content: Self.renderBlocks(
                    sectionName: sectionName, label: chunk.label,
                    blocks: Self.splitAtInteriorLabels(data.rawBytes, chunk: chunk, logger: logger)
                )
            )

        case .struct, .table:
            guard let structType = chunk.structType else {
                throw RelAssemblerErrors.untypedChunk(label: chunk.label, .init())
            }
            guard let definition = structs[structType] else {
                throw RelAssemblerErrors.structNotResolved(label: chunk.label, type: structType, .init())
            }
            guard let data = fileSystem.readFile(at: file)?.allData else {
                throw RelAssemblerErrors.missingChunk(label: chunk.label, file: file, .init())
            }
            let labelColumns = StructCSVSchema.columns(of: definition).filter { $0.labelKey != nil }

            func block(_ entry: StructData, label: String?) -> Block {
                var pointers = [Int: String]()
                for column in labelColumns {
                    if let name = entry.labelValues[column.labelKey!], !name.isEmpty {
                        pointers[column.offset] = name
                    }
                }
                return .init(label: label, bytes: entry.data.rawBytes, pointers: pointers)
            }

            if chunk.type == .struct {
                let structData: StructData
                do {
                    structData = try StructData(definition: definition, json: data, byteOrder: .big)
                } catch {
                    throw RelAssemblerErrors.chunkUndecodable(label: chunk.label, underlying: error, .init())
                }
                return (
                    name: "\(chunk.label).synthesized.s",
                    content: Self.renderBlocks(sectionName: sectionName, label: chunk.label, blocks: [block(structData, label: nil)])
                )
            }

            guard chunk.file.hasSuffix(".csv") else {
                throw RelAssemblerErrors.chunkUndecodable(
                    label: chunk.label,
                    underlying: RelAssemblerErrors.notCSV(file: file, .init()),
                    .init()
                )
            }
            let decoded: StructTableCSV.DecodeResult
            do {
                decoded = try StructTableCSV.decode(data.string(format: .utf8), definition: definition, byteOrder: .big)
            } catch {
                throw RelAssemblerErrors.chunkUndecodable(label: chunk.label, underlying: error, .init())
            }
            for warning in decoded.warnings {
                logger?.log(.warning("Table '\(chunk.label)': \(warning)"))
            }
            // The manifest's count fixes the size of a table nothing counts,
            // so a hand-edited CSV can't silently shift everything after it.
            // A counted table is sized by its CSV: its count word follows it.
            let count = sizedByCSV ? decoded.entries.count : (chunk.count ?? decoded.entries.count)
            tableCounts[chunk.label] = count
            if decoded.entries.count > count {
                logger?.log(.warning("Table '\(chunk.label)': \(decoded.entries.count - count) surplus entries dropped (manifest count is \(count))"))
            } else if decoded.entries.count < count {
                logger?.log(.warning("Table '\(chunk.label)': \(count - decoded.entries.count) missing entries zero-filled (manifest count is \(count))"))
            }
            var blocks = [Block]()
            for i in 0..<count {
                let entryLabel = chunk.entryLabels?[String(i)]
                if i < decoded.entries.count {
                    blocks.append(block(decoded.entries[i], label: entryLabel))
                } else {
                    blocks.append(.init(label: entryLabel, bytes: [UInt8](repeating: 0, count: definition.length), pointers: [:]))
                }
            }
            return (
                name: "\(chunk.label).synthesized.s",
                content: Self.renderBlocks(sectionName: sectionName, label: chunk.label, blocks: blocks)
            )
        }
    }

    /// Bytes for an embedded-file chunk: rebuilt through the registry when
    /// the dump routed it there (a per-chunk folder of artifacts), else the
    /// raw file the manifest names.
    private func embeddedFileBinary(
        _ chunk: DataSectionManifest.Chunk,
        file: File,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> GoDData {
        if let registry, let ext = chunk.fileExtension, registry.isRegistered(ext),
           let chunkFolder = file.parentFolder, chunkFolder.folderName == chunk.label,
           fileSystem.inspectFolder(at: chunkFolder) != nil {
            do {
                return try registry.buildSingle(extension: ext, from: chunkFolder, fileSystem: fileSystem)
            } catch {
                logger?.log(.warning("Registry build failed for file chunk '\(chunk.label)' (.\(ext)): \(error). Falling back to raw bytes."))
            }
        }
        guard let data = fileSystem.readFile(at: file)?.allData else {
            throw RelAssemblerErrors.missingChunk(label: chunk.label, file: file, .init())
        }
        return data
    }

    struct Block {
        let label: String?
        let bytes: [UInt8]
        /// Offset within `bytes` → symbol for each pointer slot.
        let pointers: [Int: String]
    }

    /// Cut a rebuilt file into blocks at the symbols that live inside it.
    ///
    /// A chunk normally ends at the next symbol, so a file has no interior
    /// ones. It keeps going only when the format measured itself past one —
    /// a GTX whose palette carries its own name — and that symbol is a
    /// relocation target, so it has to come back at the same offset. An
    /// offset past the rebuilt file is dropped with a warning: the file
    /// re-encoded shorter than the symbol it used to contain.
    static func splitAtInteriorLabels(
        _ bytes: [UInt8],
        chunk: DataSectionManifest.Chunk,
        logger: Logger?
    ) -> [Block] {
        guard let interior = chunk.interiorLabels, !interior.isEmpty else {
            return [.init(label: nil, bytes: bytes, pointers: [:])]
        }
        let cuts = interior
            .compactMap { key, name -> (offset: Int, name: String)? in
                guard let offset = Int(key), offset > 0 else { return nil }
                guard offset < bytes.count else {
                    logger?.log(.warning(
                        "Interior label '\(name)' sits \(offset) bytes into '\(chunk.label)', which "
                        + "rebuilt to only \(bytes.count) bytes — the label is dropped."
                    ))
                    return nil
                }
                return (offset: offset, name: name)
            }
            .sorted { $0.offset < $1.offset }
        guard !cuts.isEmpty else { return [.init(label: nil, bytes: bytes, pointers: [:])] }

        var blocks = [Block]()
        var start = 0
        var pendingLabel: String?
        for cut in cuts {
            blocks.append(.init(label: pendingLabel, bytes: Array(bytes[start..<cut.offset]), pointers: [:]))
            pendingLabel = cut.name
            start = cut.offset
        }
        blocks.append(.init(label: pendingLabel, bytes: Array(bytes[start...]), pointers: [:]))
        return blocks
    }

    /// Wraps byte blocks in a `.section` + label + directives the assembler
    /// ingests: `.byte` runs with `.4byte <symbol>` at pointer slots, and
    /// interior labels (table entries) between blocks.
    static func renderBlocks(sectionName: String, label: String, blocks: [Block]) -> String {
        var lines: [String] = []
        lines.append(".section .\(sectionName)")
        lines.append("")
        lines.append(".global \(label)")
        lines.append("\(label):")
        for block in blocks {
            if let interior = block.label, interior != label {
                lines.append("\(interior):")
            }
            var offset = 0
            while offset < block.bytes.count {
                if let symbol = block.pointers[offset], offset + 4 <= block.bytes.count {
                    lines.append("    .4byte \(symbol)")
                    offset += 4
                } else {
                    lines.append(String(format: "    .byte 0x%02X", block.bytes[offset]))
                    offset += 1
                }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func fixup(for kind: PPCSectionAssembler.RelocationKind) -> RELFile.RelocationFixup {
        switch kind {
        case .addr16_ha: return .addr16_ha
        case .addr16_hi: return .addr16_hi
        case .addr16_lo: return .addr16_lo
        case .addr32: return .addr32
        case .rel24: return .rel24
        case .rel14: return .rel14
        }
    }
}

public enum RelAssemblerErrors: Error, CustomStringConvertible {
    case manifestNotFound(file: File, ErrorTrace)
    case invalidManifest(file: File, underlying: Error, ErrorTrace)
    case missingSource(section: Int, file: File, ErrorTrace)
    case missingChunk(label: String, file: File, ErrorTrace)
    case untypedChunk(label: String, ErrorTrace)
    case structNotResolved(label: String, type: String, ErrorTrace)
    case chunkUndecodable(label: String, underlying: Error, ErrorTrace)
    case notCSV(file: File, ErrorTrace)
    case unresolvedSymbol(String, section: Int, ErrorTrace)
    case invalidRestWordKey(String, section: Int, ErrorTrace)
    case textNotWordAligned(section: Int, size: Int, ErrorTrace)
    case unsupportedDataRelocation(symbol: String, kind: String, section: Int, ErrorTrace)
    case countTargetNotATable(count: String, table: String?, ErrorTrace)
    case countOverflow(count: String, table: String, entries: Int, type: String, ErrorTrace)

    public var description: String {
        switch self {
        case let .manifestNotFound(file, trace):
            return "REL manifest not found: \(file)\n\(trace)"
        case let .invalidManifest(file, underlying, trace):
            return "Invalid REL manifest at \(file): \(underlying)\n\(trace)"
        case let .missingSource(section, file, trace):
            return "REL section \(section) has no source file (\(file))\n\(trace)"
        case let .missingChunk(label, file, trace):
            return "REL chunk '\(label)' is missing its file \(file)\n\(trace)"
        case let .untypedChunk(label, trace):
            return "REL chunk '\(label)' is typed but names no struct type\n\(trace)"
        case let .structNotResolved(label, type, trace):
            return "REL chunk '\(label)' needs struct '\(type)', which no engine folder resolved — is `engines` set in the config?\n\(trace)"
        case let .chunkUndecodable(label, underlying, trace):
            return "REL chunk '\(label)' could not be decoded: \(underlying)\n\(trace)"
        case let .notCSV(file, trace):
            return "table chunk '\(file)' is not a .csv — this disassembly predates CSV tables; re-run the disassembly\n\(trace)"
        case let .unresolvedSymbol(symbol, section, trace):
            return "Section \(section) references '\(symbol)', which is neither a label in the module nor in the manifest's symbols\n\(trace)"
        case let .invalidRestWordKey(key, section, trace):
            return "Section \(section) restWords key '\(key)' is not an offset\n\(trace)"
        case let .textNotWordAligned(section, size, trace):
            return "Text section \(section) assembled to \(size) bytes, which is not a multiple of 4\n\(trace)"
        case let .unsupportedDataRelocation(symbol, kind, section, trace):
            return "Data section \(section) relocates '\(symbol)' as \(kind); only .4byte pointers are representable in a data section\n\(trace)"
        case let .countTargetNotATable(count, table, trace):
            return "Count chunk '\(count)' counts '\(table ?? "(nothing)")', which isn't a table chunk in this module\n\(trace)"
        case let .countOverflow(count, table, entries, type, trace):
            return "Count '\(count)' is a \(type), which can't hold the \(entries) entries '\(table)' now has\n\(trace)"
        }
    }
}
