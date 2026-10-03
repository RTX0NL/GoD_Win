//
//  RelDisassembler.swift
//  Dolphin
//
//  A `RELFile` into an editable source tree, and the source of truth for the
//  layout `RelAssembler` reads back. The pair sits beside `DolDisassembler`
//  and `DolAssembler` for the same reason those do: the assembler has to
//  read exactly what the disassembler wrote.
//
//  Layout, relative to the output folder:
//
//    <name>.rel.json     manifest — header, imports, chunk list per section,
//                        symbol table, at-rest words. No bytes. See RelManifest.
//    sections.txt        human summary
//    textN.s             one per text section
//    dataN.s             a data section with no labels of its own
//    dataN/              a data section with labels: one file per chunk, cut
//                        at every symbol the module's relocations point at
//      dataN_start.bin   bytes before the first label
//      <sym>.bin         opaque bytes, no pointers inside
//      <sym>.s           bytes with pointers, as .4byte/.byte directives
//      <sym>.csv         a struct table the type map named
//      <sym>/…           an embedded file the type map named, as the format
//                        registry dumps it
//      <sym>_tail.bin    bytes after a table or file that end before the
//                        next label
//
//  Relocations are written as assembler syntax — `lis r3, sym@ha`,
//  `stw r0, sym@l(r3)`, `.4byte sym` — and a CSV pointer cell holds the
//  symbol name. `RelAssembler` re-derives every relocation from those, so the
//  files are the module: an edit that moves code or data moves its
//  relocations with it. Targets the source can't define as a label (the
//  DOL, other modules, this module's BSS) go in the manifest's symbol table.
//
//  Typing policy for a chunk the type map names:
//    - a table is written as CSV only if every pointer inside it lands on a
//      field the struct declares as a label; otherwise it is written as
//      assembly, with a warning, so no relocation is lost. There is no
//      round-trip check on the CSV's bytes: a struct that describes the table
//      badly shows up as a module that doesn't rebuild byte-identically,
//      where demoting the chunk hid it behind a warning nobody reads.
//    - an embedded file is dumped through the registry only if no pointer
//      lands inside it, for the same reason.
//

import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Disassembler

public struct RelDisassembler {

    /// Optional context. Everything defaults to "none", which is what the
    /// format-level `RELFile.outputs` uses; the operation layer fills these
    /// in from the project's symbol index, DOL map, type map and registry.
    public struct Inputs {
        /// Names for the module's pointer indices (`common_rel_symbols.json`).
        public var symbolIndex = RelSymbolIndex()
        /// DOL RAM address → symbol, for relocations into the executable.
        public var dolSymbolLookup: [UInt32: String] = [:]
        /// Typed chunks, keyed by the symbol they start at.
        public var typeMap: TypeMap? = nil
        /// Struct definitions the type map's table chunks resolve to.
        public var structs: [String: StructDefinition] = [:]
        /// Formats to dump embedded files through. Nil writes them raw.
        public var registry: FileFormatRegistry? = nil

        public init() {}
    }

    public var inputs: Inputs

    public init(inputs: Inputs = Inputs()) {
        self.inputs = inputs
    }

    // MARK: - Entry points

    /// Every artifact for `rel`, manifest first, with paths relative to the
    /// module's folder. This is what `RELFile.outputs` returns.
    public func artifacts(for rel: RELFile, logger: Logger? = nil) throws -> [FileData] {
        let fst = InMemoryFST()
        let root = Folder("/")
        try disassemble(rel, into: root, fileSystem: fst, logger: logger)

        var files: [FileData] = []
        func walk(_ folder: Folder) {
            guard let contents = fst.inspectFolder(at: folder) else { return }
            for file in contents.files.sorted() {
                guard let data = fst.readFile(at: file)?.allData else { continue }
                let relative = String(file.path.dropFirst(root.path.count))
                files.append(FileData(file: File(relative), data: data))
            }
            for sub in contents.subFolders.sorted(by: { $0.path < $1.path }) {
                walk(sub)
            }
        }
        walk(root)

        let manifestName = RelManifest.fileName(for: rel.name)
        return files.sorted { a, b in
            if a.file.path == manifestName { return true }
            if b.file.path == manifestName { return false }
            return a.file.path < b.file.path
        }
    }

    /// Writes the source tree for `rel` under `folder` and returns the
    /// manifest it wrote.
    @discardableResult
    public func disassemble(
        _ rel: RELFile,
        into folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws -> RelManifest {
        let decoder = PPCDecoder()
        let formatter = PPCFormatter()
        let exporter = TypedDataExporter()

        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .started))

        // ---- Symbols: one name per relocation target ----

        let names = SymbolNames(rel: rel, inputs: inputs)

        // Labels the module defines for its own relocation targets, per
        // section: offset → name.
        var selfLabels: [Int: [UInt32: String]] = [:]
        for (key, name) in names.byKey where key.module == rel.moduleID {
            selfLabels[Int(key.section), default: [:]][key.offset] = name
        }

        // ---- Type map, keyed by start symbol ----

        var typeChunkBySymbol: [String: TypeMap.Chunk] = [:]
        var counters: [String: TypeMap.Chunk.Count] = [:]
        var unsupportedSingles = [String]()
        if let typeMap = inputs.typeMap {
            try typeMap.validate()
            for chunk in typeMap.chunks {
                switch chunk {
                case .table(let t): typeChunkBySymbol[t.start] = chunk
                case .file(let f): typeChunkBySymbol[f.label] = chunk
                case .single(let s): unsupportedSingles.append(s.label)
                // Rendered as a plain word first; `deriveCounts` converts it
                // once every table's dumped count is known, since a count
                // can sit before its table or in another section.
                case .count(let c): counters[c.label] = c
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

        // ---- Sections ----

        var manifest = RelManifest(headerOf: rel)
        var emittedLabels = Set<String>()
        let workSections = rel.sections.filter { !$0.isEmpty && !$0.isBSS }
        var processed = 0

        for section in rel.sections {
            switch section.body {
            case .empty(let fileOffset):
                manifest.sections.append(.init(index: section.index, kind: .empty, fileOffset: HexInt(fileOffset)))

            case .bss(let size):
                manifest.sections.append(.init(index: section.index, kind: .bss, size: Int(size)))

            case .text(let instructions):
                let sectionName = "text\(section.index)"
                let rendered = renderText(
                    instructions,
                    sectionIndex: section.index,
                    sectionName: sectionName,
                    rel: rel,
                    labels: selfLabels[section.index] ?? [:],
                    names: names,
                    decoder: decoder,
                    formatter: formatter
                )
                let fileName = "\(sectionName).s"
                try fileSystem.writeFile(
                    GoDData(string: rendered.text, format: .utf8), at: folder.file(fileName), overwrite: true
                )
                emittedLabels.formUnion(rendered.emittedLabels)
                manifest.sections.append(.init(
                    index: section.index,
                    kind: .text,
                    file: fileName,
                    restWords: Self.restWordsEntry(rendered.restWords),
                    relocations: rendered.fallback.isEmpty ? nil : rendered.fallback
                ))
                processed += 1

            case .data(let chunks):
                let sectionName = "data\(section.index)"
                let rendered = try renderData(
                    chunks,
                    sectionName: sectionName,
                    rel: rel,
                    labels: selfLabels[section.index] ?? [:],
                    typeChunkBySymbol: typeChunkBySymbol,
                    names: names,
                    exporter: exporter,
                    into: folder,
                    fileSystem: fileSystem,
                    logger: logger
                )
                emittedLabels.formUnion(rendered.emittedLabels)
                manifest.sections.append(.init(
                    index: section.index,
                    kind: .data,
                    chunks: rendered.chunks,
                    restWords: Self.restWordsEntry(rendered.restWords)
                ))
                processed += 1
            }

            if logger != nil, !workSections.isEmpty {
                let pct = Percentage(Double(processed) / Double(workSections.count) * 100)
                logger?.log(.taskStatus(taskName: "Disassemble REL", status: .progress(pct)))
            }
        }

        if !counters.isEmpty {
            try deriveCounts(counters, in: &manifest, folder: folder, fileSystem: fileSystem, logger: logger)
        }

        // Every target the source does not define as a label.
        for (key, name) in names.byKey where !emittedLabels.contains(name) {
            manifest.symbols[name] = RelManifest.Symbol(
                moduleID: HexInt(key.module), section: key.section, offset: HexInt(key.offset)
            )
        }

        // ---- sections.txt ----

        try fileSystem.writeFile(
            GoDData(string: Self.summary(of: rel, symbolCount: names.byKey.count), format: .utf8),
            at: folder.file("sections.txt"),
            overwrite: true
        )

        // ---- manifest ----

        try fileSystem.writeFile(
            try manifest.encoded(),
            at: folder.file(RelManifest.fileName(for: rel.name)),
            overwrite: true
        )

        logger?.log(.taskStatus(taskName: "Disassemble REL", status: .completed(true)))
        return manifest
    }

    // MARK: - Counts

    /// Turns each declared count word into a `count` chunk, whose value the
    /// assembler derives from its table.
    ///
    /// Only a count that already holds exactly its table's dumped entry
    /// count is converted: deriving it is only safe if doing so reproduces
    /// the module. Anything else — a count whose table didn't dump as a
    /// table, a value that doesn't match, a chunk too short for the declared
    /// type or holding a pointer — keeps its bytes, with a warning. Bytes
    /// after a narrower count and before the next symbol become a
    /// `<label>_tail` chunk. A count whose label this module doesn't define
    /// is skipped in silence, like any other type-map chunk, so one map can
    /// serve modules that carry different tables.
    private func deriveCounts(
        _ counters: [String: TypeMap.Chunk.Count],
        in manifest: inout RelManifest,
        folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        var tableCounts = [String: Int]()
        for section in manifest.sections {
            for chunk in section.chunks ?? [] where chunk.type == .table {
                tableCounts[chunk.label] = chunk.count
            }
        }
        for sectionIndex in manifest.sections.indices {
            guard let original = manifest.sections[sectionIndex].chunks else { continue }
            var chunks = [DataSectionManifest.Chunk]()
            for chunk in original {
                guard let counter = counters[chunk.label] else { chunks.append(chunk); continue }
                let width = counter.type.length
                guard chunk.type == .binary,
                      let data = fileSystem.readFile(at: folder.file(chunk.file))?.allData,
                      data.length >= width else {
                    logger?.log(.warning(
                        "Count '\(chunk.label)' isn't \(width) plain byte(s) in this module; keeping its bytes."
                    ))
                    chunks.append(chunk)
                    continue
                }
                guard let tableCount = tableCounts[counter.table] else {
                    logger?.log(.warning(
                        "Count '\(chunk.label)' counts '\(counter.table)', which didn't dump as a table here; "
                        + "keeping its bytes."
                    ))
                    chunks.append(chunk)
                    continue
                }
                let bytes = data.rawBytes
                let stored = counter.type.countValue(of: Array(bytes[..<width]))
                guard stored == Int64(tableCount) else {
                    logger?.log(.warning(
                        "Count '\(chunk.label)' holds \(stored) but '\(counter.table)' has \(tableCount) entries; "
                        + "keeping its bytes."
                    ))
                    chunks.append(chunk)
                    continue
                }
                try fileSystem.deleteFile(at: folder.file(chunk.file))
                chunks.append(.init(
                    label: chunk.label, type: .count, file: "", size: width,
                    countOf: counter.table, countType: counter.type
                ))
                if bytes.count > width {
                    let tailLabel = "\(chunk.label)_tail"
                    // `chunk.file` is relative to the module folder
                    // ("data3/x.bin"), which `Folder` won't take, so the
                    // tail's path is built beside it by string.
                    let directory = chunk.file.split(separator: "/").dropLast().joined(separator: "/")
                    let tailFile = (directory.isEmpty ? "" : directory + "/") + "\(tailLabel).bin"
                    try fileSystem.writeFile(
                        GoDData(byteStream: Array(bytes[width...]), byteOrder: .big),
                        at: folder.file(tailFile), overwrite: true
                    )
                    chunks.append(.init(label: tailLabel, type: .binary, file: tailFile, size: bytes.count - width))
                }
            }
            manifest.sections[sectionIndex].chunks = chunks
        }
    }

    // MARK: - Text sections

    private struct RenderedText {
        var text: String
        var restWords: [UInt32: UInt32] = [:]
        var fallback: [RelManifest.Relocation] = []
        var emittedLabels: Set<String> = []
    }

    private func renderText(
        _ instructions: [RELFile.TextInstruction],
        sectionIndex: Int,
        sectionName: String,
        rel: RELFile,
        labels selfLabelsAtOffset: [UInt32: String],
        names: SymbolNames,
        decoder: PPCDecoder,
        formatter: PPCFormatter
    ) -> RenderedText {
        var bytes = [UInt8]()
        bytes.reserveCapacity(instructions.count * 4)
        for instruction in instructions {
            bytes.append(UInt8((instruction.raw >> 24) & 0xFF))
            bytes.append(UInt8((instruction.raw >> 16) & 0xFF))
            bytes.append(UInt8((instruction.raw >> 8) & 0xFF))
            bytes.append(UInt8(instruction.raw & 0xFF))
        }
        let decoded = decoder.decodeAll(bytes, baseAddress: 0)
        let size = UInt32(bytes.count)

        var result = RenderedText(text: "")

        // Label lines per offset. A self label gets a `.global`; the entry
        // point markers and auto branch labels don't.
        var labelLines: [UInt32: [String]] = [:]
        var primary: [UInt32: String] = [:]
        for (offset, name) in selfLabelsAtOffset where offset % 4 == 0 && offset < size {
            labelLines[offset, default: []].append(name)
            primary[offset] = name
            result.emittedLabels.insert(name)
        }
        let markers: [(section: UInt8, offset: UInt32, name: String)] = [
            (rel.prologSection, rel.prologOffset, "_prolog"),
            (rel.epilogSection, rel.epilogOffset, "_epilog"),
            (rel.unresolvedSection, rel.unresolvedOffset, "_unresolved"),
        ]
        for marker in markers where Int(marker.section) == sectionIndex && marker.offset % 4 == 0 && marker.offset < size {
            labelLines[marker.offset, default: []].append(marker.name)
            if primary[marker.offset] == nil { primary[marker.offset] = marker.name }
        }
        // Local branch targets that have no name yet.
        for instruction in decoded {
            guard let d = instruction.decoded else { continue }
            for operand in d.operands {
                if case .branchTarget(let target) = operand,
                   target % 4 == 0, target < size, primary[target] == nil {
                    let name = "lbl_" + String(format: "%08X", target)
                    primary[target] = name
                    labelLines[target, default: []].append(name)
                }
            }
        }

        // Relocation annotations for the formatter: half-word fixups.
        var relocationsForFormatter: [UInt32: PPCRelocation] = [:]
        for (i, instruction) in instructions.enumerated() {
            guard let ref = instruction.ref, let fixup = instruction.fixup else { continue }
            let halfType: PPCRelocation.HalfType
            switch fixup {
            case .addr16_ha: halfType = .ha
            case .addr16_hi: halfType = .h
            case .addr16_lo: halfType = .lo
            default: continue
            }
            relocationsForFormatter[UInt32(i * 4)] = PPCRelocation(
                targetAddress: 0, symbolName: names.name(for: ref), halfType: halfType
            )
        }

        var lines = [String]()
        lines.reserveCapacity(instructions.count + instructions.count / 8 + 4)
        lines.append(".section .\(sectionName)")
        lines.append("")

        for (i, instruction) in instructions.enumerated() {
            let offset = UInt32(i * 4)
            if let names = labelLines[offset] {
                for name in names {
                    if selfLabelsAtOffset[offset] == name {
                        lines.append("")
                        lines.append(".global \(name)")
                    }
                    lines.append("\(name):")
                }
            }

            let ppc = decoded[i]
            guard let ref = instruction.ref, let fixup = instruction.fixup else {
                lines.append("    " + formatter.format(ppc, labels: primary))
                continue
            }
            let symbol = names.name(for: ref)

            switch fixup {
            case .addr32:
                lines.append("    .4byte \(symbol)")
                if instruction.raw != 0 { result.restWords[offset] = instruction.raw }

            case .rel24, .rel14:
                if let d = ppc.decoded, d.operands.contains(where: { if case .branchTarget = $0 { return true }; return false }) {
                    let operands = d.operands.map { operand -> String in
                        if case .branchTarget = operand { return symbol }
                        return formatter.formatOperand(operand)
                    }
                    lines.append("    \(d.mnemonic) \(operands.joined(separator: ", "))")
                    let fieldMask: UInt32 = fixup == .rel24 ? 0x03FF_FFFC : 0xFFFC
                    if instruction.raw & fieldMask != 0 { result.restWords[offset] = instruction.raw }
                } else {
                    lines.append("    " + formatter.format(ppc, labels: primary))
                    result.fallback.append(.init(offset: HexInt(offset), fixup: fixup, symbol: symbol))
                }

            case .addr16_ha, .addr16_hi, .addr16_lo:
                let text = formatter.format(ppc, labels: primary, relocations: relocationsForFormatter)
                if text.contains("\(symbol)@") {
                    lines.append("    " + text)
                    if instruction.raw & 0xFFFF != 0 { result.restWords[offset] = instruction.raw }
                } else {
                    // The formatter has no symbolic spelling for this
                    // consumer; keep the raw instruction and the edge.
                    lines.append("    " + formatter.format(ppc, labels: primary))
                    result.fallback.append(.init(offset: HexInt(offset), fixup: fixup, symbol: symbol))
                }

            case .addr16, .addr24, .addr14:
                lines.append("    " + formatter.format(ppc, labels: primary))
                result.fallback.append(.init(offset: HexInt(offset), fixup: fixup, symbol: symbol))
            }
        }

        result.text = lines.joined(separator: "\n") + "\n"
        return result
    }

    // MARK: - Data sections

    private struct RenderedData {
        var chunks: [DataSectionManifest.Chunk] = []
        var restWords: [UInt32: UInt32] = [:]
        var emittedLabels: Set<String> = []
    }

    private func renderData(
        _ dataChunks: [RELFile.DataChunk],
        sectionName: String,
        rel: RELFile,
        labels labelsAtOffset: [UInt32: String],
        typeChunkBySymbol: [String: TypeMap.Chunk],
        names: SymbolNames,
        exporter: TypedDataExporter,
        into folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> RenderedData {
        // Flatten to bytes plus a pointer map (section offset → target).
        var bytes = [UInt8]()
        var pointers: [Int: RELFile.SymbolRef] = [:]
        var result = RenderedData()
        for chunk in dataChunks {
            switch chunk {
            case .binary(let b):
                bytes.append(contentsOf: b)
            case .pointer(let ref, let restValue):
                pointers[bytes.count] = ref
                if restValue != 0 { result.restWords[UInt32(bytes.count)] = restValue }
                bytes.append(UInt8((restValue >> 24) & 0xFF))
                bytes.append(UInt8((restValue >> 16) & 0xFF))
                bytes.append(UInt8((restValue >> 8) & 0xFF))
                bytes.append(UInt8(restValue & 0xFF))
            }
        }
        guard !bytes.isEmpty else { return result }

        func pointerNames(in range: Range<Int>) -> [Int: String] {
            var out = [Int: String]()
            for (offset, ref) in pointers where range.contains(offset) {
                out[offset - range.lowerBound] = names.name(for: ref)
            }
            return out
        }

        // Writes one span as assembly (`.s`) or opaque bytes (`.bin`)
        // depending on whether a pointer lands inside it.
        func writePlain(
            _ range: Range<Int>, label: String, isGlobal: Bool, file: (String) -> String
        ) throws -> DataSectionManifest.Chunk {
            let span = Array(bytes[range])
            let pointerMap = pointerNames(in: range)
            if pointerMap.isEmpty {
                let path = file("bin")
                try fileSystem.writeFile(GoDData(byteStream: span, byteOrder: .big), at: folder.file(path), overwrite: true)
                return .init(label: label, type: .binary, file: path, size: span.count)
            }
            let path = file("s")
            let text = Self.renderDataAssembly(
                bytes: span, label: label, isGlobal: isGlobal, pointers: pointerMap, sectionName: sectionName
            )
            try fileSystem.writeFile(GoDData(string: text, format: .utf8), at: folder.file(path), overwrite: true)
            return .init(label: label, type: .assembly, file: path, size: span.count)
        }

        // A section nothing points into is one assembly file.
        guard !labelsAtOffset.isEmpty else {
            let path = "\(sectionName).s"
            let text = Self.renderDataAssembly(
                bytes: bytes, label: sectionName, isGlobal: false,
                pointers: pointerNames(in: 0..<bytes.count), sectionName: sectionName
            )
            try fileSystem.writeFile(GoDData(string: text, format: .utf8), at: folder.file(path), overwrite: true)
            result.chunks.append(.init(label: sectionName, type: .assembly, file: path, size: bytes.count))
            result.emittedLabels.insert(sectionName)
            return result
        }

        let boundaries = labelsAtOffset.keys.map(Int.init).filter { $0 < bytes.count }.sorted()

        if let first = boundaries.first, first > 0 {
            let label = "\(sectionName)_start"
            result.chunks.append(try writePlain(0..<first, label: label, isGlobal: false) { ext in
                "\(sectionName)/\(label).\(ext)"
            })
            result.emittedLabels.insert(label)
        }

        var i = 0
        while i < boundaries.count {
            let start = boundaries[i]
            let nextBoundary = i + 1 < boundaries.count ? boundaries[i + 1] : bytes.count
            let label = labelsAtOffset[UInt32(start)]!
            result.emittedLabels.insert(label)

            var end = nextBoundary
            var consumed = 0   // bytes a typed chunk claimed from `start`

            if case .file(let embedded) = typeChunkBySymbol[label] {
                // The next symbol is a floor, not the answer: a format that
                // reads its own length off its header can raise it, since a
                // symbol can sit inside a file (a GTX names its palette) and
                // would otherwise cut it short. It can only raise it — a
                // measurement below the gap would take the container's
                // trailing padding away from the chunk that owns it.
                let measured = inputs.registry?.measuredLength(
                    of: GoDData(byteStream: Array(bytes[start...]), byteOrder: .big),
                    extension: embedded.extension
                )
                let fileSize = min(
                    embedded.size ?? max(measured ?? (end - start), end - start), bytes.count - start
                )
                if pointers.keys.contains(where: { $0 >= start && $0 < start + fileSize }) {
                    logger?.log(.warning(
                        "'\(label)' is typed as a .\(embedded.extension) file but a relocation lands inside it; "
                        + "emitting it as assembly so the pointer survives."
                    ))
                } else {
                    // Symbols the file swallowed. They are relocation targets,
                    // so the manifest carries them and the assembler puts them
                    // back at the same offsets inside the rebuilt file.
                    var interiorLabels = [String: String]()
                    if fileSize > end - start {
                        for offset in boundaries where offset > start && offset < start + fileSize {
                            interiorLabels[String(offset - start)] = labelsAtOffset[UInt32(offset)]!
                        }
                        logger?.log(.info(
                            "'\(label)' (.\(embedded.extension)) measures \(fileSize) bytes and runs past "
                            + "\(interiorLabels.count) of its own symbol(s); keeping them as interior labels."
                        ))
                    }
                    let fileData = GoDData(byteStream: Array(bytes[start..<start + fileSize]), byteOrder: .big)
                    var chunk = try writeEmbeddedFile(
                        fileData, label: label, extension: embedded.extension,
                        sectionName: sectionName, into: folder, fileSystem: fileSystem, logger: logger
                    )
                    if !interiorLabels.isEmpty {
                        chunk = .init(
                            label: chunk.label, type: chunk.type, file: chunk.file,
                            structType: chunk.structType,
                            count: chunk.count, size: chunk.size,
                            fileExtension: chunk.fileExtension, entryLabels: chunk.entryLabels,
                            interiorLabels: interiorLabels
                        )
                        for (_, name) in interiorLabels { result.emittedLabels.insert(name) }
                    }
                    result.chunks.append(chunk)
                    consumed = fileSize
                    // Boundaries the file swallowed are interior labels, not
                    // chunks of their own — the same rule the table path uses.
                    while i + 1 < boundaries.count, boundaries[i + 1] < start + consumed {
                        i += 1
                    }
                    end = i + 1 < boundaries.count ? boundaries[i + 1] : bytes.count
                }
            } else if case .table(let table) = typeChunkBySymbol[label] {
                if let definition = inputs.structs[table.entryType] {
                    // Labels after this one that the table may run over. Only an
                    // explicit `count` lets a table cross a label; without one the
                    // table ends at the next label, as any other chunk does.
                    let interior = boundaries[(i + 1)...].map { (offset: $0 - start, name: labelsAtOffset[UInt32($0)]!) }
                    if let written = try writeTable(
                        table, definition: definition, label: label,
                        bytes: bytes, start: start, nextBoundary: nextBoundary, interiorLabels: interior,
                        pointers: pointers, sectionName: sectionName, names: names, exporter: exporter,
                        into: folder, fileSystem: fileSystem, logger: logger
                    ) {
                        result.chunks.append(written.chunk)
                        consumed = written.size
                        for (_, entryLabel) in written.chunk.entryLabels ?? [:] {
                            result.emittedLabels.insert(entryLabel)
                        }
                        // Boundaries the table swallowed are its entry labels, not
                        // chunks of their own.
                        while i + 1 < boundaries.count, boundaries[i + 1] < start + consumed {
                            i += 1
                        }
                        end = i + 1 < boundaries.count ? boundaries[i + 1] : bytes.count
                    }
                } else {
                    logger?.log(.warning(
                        "Table '\(label)' names struct '\(table.entryType)', which no engine resolved; emitting raw."
                    ))
                }
            }

            if consumed == 0 {
                result.chunks.append(try writePlain(start..<end, label: label, isGlobal: true) { ext in
                    "\(sectionName)/\(label).\(ext)"
                })
            } else if start + consumed < end {
                let tailLabel = "\(label)_tail"
                result.chunks.append(try writePlain((start + consumed)..<end, label: tailLabel, isGlobal: false) { ext in
                    "\(sectionName)/\(tailLabel).\(ext)"
                })
                result.emittedLabels.insert(tailLabel)
            }
            i += 1
        }

        return result
    }

    private func writeEmbeddedFile(
        _ fileData: GoDData,
        label: String,
        extension ext: String,
        sectionName: String,
        into folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> DataSectionManifest.Chunk {
        if let registry = inputs.registry, registry.isRegistered(ext) {
            let chunkFolder = folder.folder(sectionName).folder(label)
            do {
                let written = try registry.dump(
                    bytes: fileData, extension: ext, into: chunkFolder, fileSystem: fileSystem, overwrite: true
                )
                let primary = written.first?.fileName ?? "\(label).\(ext)"
                return .init(
                    label: label, type: .file, file: "\(sectionName)/\(label)/\(primary)",
                    size: fileData.length, fileExtension: ext
                )
            } catch {
                logger?.log(.warning("Registry dump failed for '\(label)' (.\(ext)): \(error). Falling back to raw bytes."))
            }
        }
        let path = "\(sectionName)/\(label).\(ext)"
        try fileSystem.writeFile(fileData, at: folder.file(path), overwrite: true)
        return .init(label: label, type: .file, file: path, size: fileData.length, fileExtension: ext)
    }

    /// Writes a struct table as CSV. Returns nil — and the caller falls back
    /// to assembly — when a pointer inside the table is not on a label field,
    /// or the CSV does not decode back to the same bytes.
    ///
    /// `interiorLabels` are the module's own symbols past `start`, in order.
    /// One that lands on an entry boundary becomes that entry's label; one
    /// that lands mid-entry ends the table before it.
    private func writeTable(
        _ table: TypeMap.Chunk.Table,
        definition: StructDefinition,
        label: String,
        bytes: [UInt8],
        start: Int,
        nextBoundary: Int,
        interiorLabels: [(offset: Int, name: String)],
        pointers: [Int: RELFile.SymbolRef],
        sectionName: String,
        names: SymbolNames,
        exporter: TypedDataExporter,
        into folder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> (chunk: DataSectionManifest.Chunk, size: Int)? {
        let entrySize = definition.length
        guard entrySize > 0 else { return nil }

        var count: Int
        if let declared = table.count {
            count = min(declared, (bytes.count - start) / entrySize)
        } else {
            count = (nextBoundary - start) / entrySize
        }
        var entryLabelList: [(offset: Int, name: String)] = []
        for interior in interiorLabels where interior.offset < count * entrySize {
            if interior.offset % entrySize == 0 {
                entryLabelList.append(interior)
            } else {
                logger?.log(.warning(
                    "Table '\(label)': symbol '\(interior.name)' lands mid-entry at +0x\(String(interior.offset, radix: 16)); "
                    + "the table ends before it."
                ))
                count = interior.offset / entrySize
                entryLabelList.removeAll { $0.offset >= count * entrySize }
            }
        }
        guard count > 0 else { return nil }
        let tableSize = entrySize * count

        let labelColumns = StructCSVSchema.columns(of: definition).filter { $0.labelKey != nil }
        let labelOffsets = Set(labelColumns.map(\.offset))
        for offset in pointers.keys where offset >= start && offset < start + tableSize {
            let inEntry = (offset - start) % entrySize
            guard labelOffsets.contains(inEntry) else {
                logger?.log(.warning(
                    "Table '\(label)': a relocation at entry offset 0x\(String(inEntry, radix: 16)) is not on a "
                    + "label field of \(definition.name); emitting the table as assembly."
                ))
                return nil
            }
        }

        let tableData = GoDData(byteStream: Array(bytes[start..<start + tableSize]), byteOrder: .big)
        // Pointer cells carry the relocation target's name; a slot with no
        // relocation is a null pointer and stays empty (or keeps a non-zero
        // word as an `lbl_` literal — see `TypedDataExporter`).
        var pointerLabels = [Int: String]()
        for (offset, ref) in pointers where offset >= start && offset < start + tableSize {
            pointerLabels[offset - start] = names.name(for: ref)
        }
        let entries = exporter.exportTable(
            data: tableData, definition: definition, count: count,
            entryLabels: entryLabelList, addressToLabel: [:], pointerLabels: pointerLabels
        )

        // No round-trip check: a table whose struct describes it badly dumps
        // as CSV anyway, and the module failing to rebuild byte-identically is
        // what reports it. Falling back to assembly here turned a wrong struct
        // definition into a warning and a module that still rebuilt.
        let csv = try StructTableCSV.encode(entries: entries.map(\.data), definition: definition)

        let path = "\(sectionName)/\(label).csv"
        try fileSystem.writeFile(GoDData(string: csv, format: .utf8), at: folder.file(path), overwrite: true)

        var namesByIndex = [String: String]()
        for (index, entry) in entries.enumerated() {
            if let entryLabel = entry.label { namesByIndex[String(index)] = entryLabel }
        }
        let chunk = DataSectionManifest.Chunk(
            label: label, type: .table, file: path,
            structType: table.entryType, count: count, size: tableSize,
            entryLabels: namesByIndex.isEmpty ? nil : namesByIndex
        )
        return (chunk, tableSize)
    }

    // MARK: - Rendering helpers

    /// `.4byte`/`.byte` directives for a run of data bytes. A pointer slot
    /// becomes `.4byte <symbol>`; every other word is a literal, and runs
    /// that don't fill a word — or sit before a pointer that isn't
    /// word-aligned relative to the chunk — are single bytes.
    static func renderDataAssembly(
        bytes: [UInt8],
        label: String?,
        isGlobal: Bool,
        pointers: [Int: String],
        sectionName: String
    ) -> String {
        var lines = [String]()
        lines.append(".section .\(sectionName)")
        lines.append("")
        if let label {
            if isGlobal { lines.append(".global \(label)") }
            lines.append("\(label):")
        }
        var offset = 0
        let count = bytes.count
        while offset < count {
            if let symbol = pointers[offset], offset + 4 <= count {
                lines.append("    .4byte \(symbol)")
                offset += 4
            } else if offset + 4 <= count,
                      pointers[offset + 1] == nil, pointers[offset + 2] == nil, pointers[offset + 3] == nil {
                let word = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                         | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
                lines.append("    .4byte 0x" + String(format: "%08X", word))
                offset += 4
            } else {
                lines.append("    .byte 0x" + String(format: "%02X", bytes[offset]))
                offset += 1
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func restWordsEntry(_ words: [UInt32: UInt32]) -> [String: HexInt]? {
        guard !words.isEmpty else { return nil }
        var out = [String: HexInt]()
        for (offset, word) in words { out[RelManifest.offsetKey(offset)] = HexInt(word) }
        return out
    }

    private static func summary(of rel: RELFile, symbolCount: Int) -> String {
        var sectionFileOffset: [Int: UInt32] = [:]
        var cursor = UInt32(rel.headerSize + rel.sectionTableSize)
        for s in rel.sections {
            switch s.body {
            case .empty(let fileOffset): sectionFileOffset[s.index] = fileOffset
            case .bss: sectionFileOffset[s.index] = 0
            default:
                sectionFileOffset[s.index] = cursor
                cursor &+= s.size
            }
        }
        var lines: [String] = []
        lines.append("# REL Section Layout")
        lines.append("# Module ID: \(rel.moduleID)")
        lines.append("# REL Version: \(rel.version)")
        lines.append("# Prolog: section \(rel.prologSection) offset 0x\(String(rel.prologOffset, radix: 16, uppercase: true))")
        lines.append("# Epilog: section \(rel.epilogSection) offset 0x\(String(rel.epilogOffset, radix: 16, uppercase: true))")
        lines.append("# Unresolved: section \(rel.unresolvedSection) offset 0x\(String(rel.unresolvedOffset, radix: 16, uppercase: true))")
        if rel.bssSize > 0 {
            lines.append("# BSS: \(rel.bssSize) bytes total")
        }
        lines.append("# Unique relocation targets: \(symbolCount)")
        lines.append("# Imports: \(rel.importedModules.map { $0 == 0 ? "DOL" : "module \($0)" }.joined(separator: ", "))")
        lines.append("")
        for s in rel.textSections {
            let off = sectionFileOffset[s.index] ?? 0
            lines.append("text\(s.index): offset 0x\(String(off, radix: 16, uppercase: true)) (\(s.size) bytes)")
        }
        for s in rel.dataSections {
            let off = sectionFileOffset[s.index] ?? 0
            lines.append("data\(s.index): offset 0x\(String(off, radix: 16, uppercase: true)) (\(s.size) bytes)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Symbol naming

/// One name for every relocation target in a module, chosen once so the
/// text, the data chunks, the CSV cells and the manifest agree.
///
/// Preference order: the symbol index's name for the target's pointer
/// index; a DOL map name for a DOL address; `dol_XXXXXXXX` for an unnamed
/// DOL address; `sym_N` for an unnamed target in this module; and
/// `modM_secS_OFF` for another module. Names are then made assembler-safe
/// (identifier characters only, not parseable as a register or number) and
/// unique.
struct SymbolNames {
    struct TargetKey: Hashable {
        let module: UInt32
        let section: UInt8
        let offset: UInt32

        init(_ ref: RELFile.SymbolRef) {
            module = ref.moduleID
            section = ref.section
            offset = ref.offset
        }
    }

    let selfModule: UInt32
    private(set) var byKey: [TargetKey: String] = [:]

    init(rel: RELFile, inputs: RelDisassembler.Inputs) {
        selfModule = rel.moduleID
        let parser = PPCAssemblyParser()
        var taken = Set<String>()

        let table = rel.pointerIndexTable()
        for index in table.keys.sorted() {
            let ref = table[index]!
            var name: String
            if let indexed = inputs.symbolIndex.name(for: index) {
                name = indexed
            } else if ref.moduleID == 0 {
                name = inputs.dolSymbolLookup[ref.offset] ?? "dol_" + String(format: "%08X", ref.offset)
            } else if ref.moduleID == rel.moduleID {
                name = "sym_\(index)"
            } else {
                name = "mod\(ref.moduleID)_sec\(ref.section)_" + String(ref.offset, radix: 16, uppercase: true)
            }

            name = Self.sanitized(name, parser: parser)
            if taken.contains(name) {
                var candidate = "\(name)_\(index)"
                var bump = 0
                while taken.contains(candidate) {
                    bump += 1
                    candidate = "\(name)_\(index)_\(bump)"
                }
                name = candidate
            }
            taken.insert(name)
            byKey[TargetKey(ref)] = name
        }
    }

    func name(for ref: RELFile.SymbolRef) -> String {
        byKey[TargetKey(ref)] ?? "mod\(ref.moduleID)_sec\(ref.section)_" + String(ref.offset, radix: 16, uppercase: true)
    }

    /// Identifier characters only, and nothing the operand parser would read
    /// as a register, condition bit, special register or number.
    static func sanitized(_ raw: String, parser: PPCAssemblyParser) -> String {
        var cleaned = String(raw.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "$") ? ch : "_"
        })
        if cleaned.isEmpty || cleaned.first!.isNumber || cleaned.first! == "." {
            cleaned = "sym_" + cleaned
        }
        if case .label(let back)? = parser.parseOperand(cleaned, mnemonic: ""), back == cleaned {
            return cleaned
        }
        return "sym_" + cleaned
    }
}
