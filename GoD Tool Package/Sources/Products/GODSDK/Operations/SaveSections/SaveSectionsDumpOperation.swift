import Foundation
import GoDFoundation
import GoDEngine
import Structs
import XD

extension SaveSectionsOps {

    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpSaveSections(slotFolder, overwrite, layoutPath, engines, flagsTable):
                try dumpSaveSections(
                    slotFolder: slotFolder,
                    overwrite: overwrite,
                    layoutPath: layoutPath,
                    engines: engines,
                    flagsTable: flagsTable,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func dumpSaveSections(
        slotFolder: Folder,
        overwrite: Bool,
        layoutPath: File,
        engines: [Folder],
        flagsTable: File?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump Save Sections", status: .started))

        let layout = try loadLayout(at: layoutPath, fileSystem: fileSystem)
        let engine = try GenericEngine(combining: engines, in: fileSystem)
        let flagTable = try loadFlagTable(at: flagsTable, fileSystem: fileSystem, logger: logger)

        for (sectionName, section) in layout.sections.sorted(by: { $0.key < $1.key }) {
            // Banks that name struct properties live in a typed section's
            // JSON, which has no `.bin` to slice — handle those first and on
            // their own terms.
            for chunk in fieldChunks(section) {
                guard case .flags(let spec) = chunk else { continue }
                guard let flagTable else {
                    throw SaveSectionsOpsErrors.missingFlagTable(chunk: spec.name, .init())
                }
                let (artifact, json) = try sectionJSON(named: sectionName, in: slotFolder, fileSystem: fileSystem)
                let bytes = try bankBytes(from: json, banks: spec.banks, chunk: spec.name)
                let folder = slotFolder.folder(artifactFolderName(forBinary: artifact))
                try fileSystem.writeFile(
                    GoDData(string: flagCSV(bytes: bytes, banks: spec.banks, table: flagTable), format: .utf8),
                    at: folder.file("\(spec.name).csv"),
                    overwrite: overwrite
                )
                logger?.log(.info("Save sections: '\(sectionName)' flags -> \(folder.path)/\(spec.name).csv"))
            }
            guard section.chunks.contains(where: { !$0.isFieldAddressed }) else { continue }

            guard let binary = try sectionBinary(named: sectionName, in: slotFolder, fileSystem: fileSystem) else {
                throw SaveSectionsOpsErrors.missingSectionBinary(section: sectionName, folder: slotFolder, .init())
            }
            let bytes = binary.data.rawBytes
            let chunks = try resolve(section, sectionLength: bytes.count, engine: engine, sectionName: sectionName)
            let folder = slotFolder.folder(artifactFolderName(forBinary: binary.name))

            for chunk in chunks {
                let slice = Array(bytes[chunk.offset ..< (chunk.offset + chunk.length)])
                try writeChunk(chunk.chunk, bytes: slice, into: folder, engine: engine,
                               flagTable: flagTable, overwrite: overwrite, fileSystem: fileSystem)
            }
            // Anything the layout doesn't describe is kept verbatim, so a
            // partial layout is lossless and can be extended later.
            for gap in gaps(around: chunks, sectionLength: bytes.count) {
                try fileSystem.writeFile(
                    GoDData(byteStream: Array(bytes[gap.offset ..< (gap.offset + gap.length)]), byteOrder: .big),
                    at: folder.file(gapFilename(offset: gap.offset)),
                    overwrite: overwrite
                )
            }
            logger?.log(.info("Save sections: '\(sectionName)' -> \(chunks.count) chunk(s) in \(folder.path)"))
        }

        logger?.log(.taskStatus(taskName: "Dump Save Sections", status: .completed(true)))
    }

    private static func writeChunk(
        _ chunk: SectionLayout.Chunk,
        bytes: [UInt8],
        into folder: Folder,
        engine: GenericEngine,
        flagTable: XDFlagTable?,
        overwrite: Bool,
        fileSystem: FileSystemTree
    ) throws {
        switch chunk {
        case .flags(let spec):
            guard let flagTable else {
                throw SaveSectionsOpsErrors.missingFlagTable(chunk: spec.name, .init())
            }
            let csv = flagCSV(bytes: bytes, banks: spec.banks, table: flagTable)
            try fileSystem.writeFile(
                GoDData(string: csv, format: .utf8),
                at: folder.file("\(spec.name).csv"),
                overwrite: overwrite
            )

        case .structInstance(let spec):
            let definition = try engine.getStruct(spec.type) as StructDefinition
            let parsed = StructData(definition: definition, data: GoDData(byteStream: bytes, byteOrder: .big))
            try fileSystem.encodeJSON(parsed, to: folder.file("\(spec.name).json"), overwrite: overwrite)

        case .table(let spec):
            let definition = try engine.getStruct(spec.type) as StructDefinition
            var rows: [StructData] = []
            for i in 0 ..< spec.count {
                let row = Array(bytes[(i * definition.length) ..< ((i + 1) * definition.length)])
                rows.append(StructData(definition: definition, data: GoDData(byteStream: row, byteOrder: .big)))
            }
            let csv = try StructTableCSV.encode(entries: rows, definition: definition)
            try fileSystem.writeFile(
                GoDData(string: csv, format: .utf8),
                at: folder.file("\(spec.name).csv"),
                overwrite: overwrite
            )
        }
    }

    /// One row per flag: `id,value`. A flag's bank, width and bit position all
    /// come from the table, so repeating them here would only offer columns
    /// that look editable and aren't.
    static func flagCSV(bytes: [UInt8], banks: [SectionLayout.Chunk.Flags.Bank], table: XDFlagTable) -> String {
        var bankWords: [Int: [UInt32]] = [:]
        var cursor = 0
        for (index, bank) in banks.enumerated() {
            let end = min(cursor + bank.length, bytes.count)
            guard cursor < end else { break }
            bankWords[index + 1] = XDFlagTable.words(of: bytes[cursor ..< end])
            cursor += bank.length
        }
        var rows: [[String]] = [["id", "value"]]
        for flag in table.flags {
            guard let words = bankWords[flag.bank] else { continue }
            rows.append(["\(flag.id)", "\(XDFlagTable.value(of: flag, in: words))"])
        }
        return CSV.encode(rows: rows)
    }

    // MARK: - Shared loading

    static func loadLayout(at path: File, fileSystem: FileSystemTree) throws -> SectionLayout {
        guard fileSystem.readFile(at: path)?.allData != nil else {
            throw SaveSectionsOpsErrors.missingLayout(file: path, .init())
        }
        return try fileSystem.decodeJSON(from: path)
    }

    /// The flag descriptor table, when the config names one. Optional because
    /// only `flags` chunks need it — a layout of plain structs works without.
    static func loadFlagTable(
        at path: File?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> XDFlagTable? {
        guard let path else { return nil }
        guard let bytes = fileSystem.readFile(at: path)?.allData else {
            logger?.log(.warning("Save sections: no flag table at \(path) — flag chunks can't be decoded."))
            return nil
        }
        let text = String(decoding: bytes.rawBytes, as: UTF8.self)
        let (table, warnings) = try XDFlagTable.load(csv: text)
        warnings.forEach { logger?.log(.warning("Flag table: \($0)")) }
        return table
    }

    /// Finds `<index>-<name>.bin` in the slot folder. Matched on the stem's
    /// suffix rather than a fixed index, so renumbering a section doesn't
    /// invalidate a layout.
    static func sectionBinary(
        named sectionName: String,
        in folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> (name: String, data: GoDData)? {
        for file in fileSystem.inspectFolder(at: folder)?.files ?? [] {
            let name = file.fileName
            guard name.hasSuffix(".bin") else { continue }
            let stem = String(name.dropLast(4))
            guard stem == sectionName || stem.hasSuffix("-\(sectionName)") else { continue }
            guard let data = fileSystem.readFile(at: file)?.allData else { continue }
            return (name, data)
        }
        return nil
    }

    // MARK: - Typed sections

    /// The typed artifact for a section that dumps as JSON rather than bytes.
    static func sectionJSON(
        named sectionName: String,
        in folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> (artifact: String, json: [String: Any]) {
        for file in fileSystem.inspectFolder(at: folder)?.files ?? [] {
            let name = file.fileName
            guard name.hasSuffix(".json") else { continue }
            let stem = String(name.dropLast(5))
            guard stem == sectionName || stem.hasSuffix("-\(sectionName)") else { continue }
            guard let bytes = fileSystem.readFile(at: file)?.allData,
                  let root = try JSONSerialization.jsonObject(with: bytes.data) as? [String: Any] else { continue }
            return (name, root)
        }
        throw SaveSectionsOpsErrors.missingSectionBinary(section: sectionName, folder: folder, .init())
    }

    /// Concatenates the banks' bytes out of a typed section's JSON.
    static func bankBytes(
        from json: [String: Any],
        banks: [SectionLayout.Chunk.Flags.Bank],
        chunk: String
    ) throws -> [UInt8] {
        let data = (json["data"] as? [String: Any]) ?? json
        var out: [UInt8] = []
        for bank in banks {
            guard let field = bank.field, let raw = data[field] as? [Any] else {
                throw SaveSectionsOpsErrors.missingBankField(chunk: chunk, field: bank.field ?? bank.name, .init())
            }
            let bytes = raw.compactMap { ($0 as? NSNumber).map { UInt8(truncatingIfNeeded: $0.intValue) } }
            guard bytes.count == bank.length else {
                throw SaveSectionsOpsErrors.rebuiltSizeMismatch(
                    section: "\(chunk)/\(bank.name)", expected: bank.length, actual: bytes.count, .init()
                )
            }
            out += bytes
        }
        return out
    }
}
