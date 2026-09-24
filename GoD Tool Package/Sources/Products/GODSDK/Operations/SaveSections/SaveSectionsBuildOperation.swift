import Foundation
import GoDFoundation
import GoDEngine
import Structs
import XD

extension SaveSectionsOps {

    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildSaveSections(slotFolder, overwrite, layoutPath, engines, flagsTable):
                try buildSaveSections(
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

    private static func buildSaveSections(
        slotFolder: Folder,
        overwrite: Bool,
        layoutPath: File,
        engines: [Folder],
        flagsTable: File?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Build Save Sections", status: .started))

        let layout = try loadLayout(at: layoutPath, fileSystem: fileSystem)
        let engine = try GenericEngine(combining: engines, in: fileSystem)
        let flagTable = try loadFlagTable(at: flagsTable, fileSystem: fileSystem, logger: logger)

        for (sectionName, section) in layout.sections.sorted(by: { $0.key < $1.key }) {
            // Field-addressed banks are written back into the typed section's
            // own JSON, which the save build reads next. The CSV is the source
            // of truth for those properties — see `Bank.field`.
            for chunk in fieldChunks(section) {
                guard case .flags(let spec) = chunk else { continue }
                guard let flagTable else {
                    throw SaveSectionsOpsErrors.missingFlagTable(chunk: spec.name, .init())
                }
                let (artifact, originalJSON) = try sectionJSONForWriting(
                    named: sectionName, in: slotFolder, fileSystem: fileSystem
                )
                var json = originalJSON
                let folder = slotFolder.folder(artifactFolderName(forBinary: artifact))
                let file = folder.file("\(spec.name).csv")
                guard let csvBytes = fileSystem.readFile(at: file)?.allData else {
                    throw SaveSectionsOpsErrors.missingArtifact(file: file, .init())
                }
                let bytes = try flagBytes(
                    csv: String(decoding: csvBytes.rawBytes, as: UTF8.self),
                    banks: spec.banks, table: flagTable, chunkName: spec.name
                )
                json = writeBankBytes(bytes, banks: spec.banks, into: json)
                try fileSystem.writeFile(
                    GoDData(byteStream: [UInt8](try JSONSerialization.data(
                        withJSONObject: json, options: [.prettyPrinted, .sortedKeys])), byteOrder: .big),
                    at: slotFolder.file(artifact),
                    overwrite: true
                )
                logger?.log(.info("Save sections: wrote '\(spec.name)' back into \(artifact)"))
            }
            guard section.chunks.contains(where: { !$0.isFieldAddressed }) else { continue }

            guard let binary = try sectionBinary(named: sectionName, in: slotFolder, fileSystem: fileSystem) else {
                throw SaveSectionsOpsErrors.missingSectionBinary(section: sectionName, folder: slotFolder, .init())
            }
            let sectionLength = binary.data.length
            let chunks = try resolve(section, sectionLength: sectionLength, engine: engine, sectionName: sectionName)
            let folder = slotFolder.folder(artifactFolderName(forBinary: binary.name))

            // Rebuild into a zeroed buffer: every byte comes from an artifact,
            // either a chunk or a gap file, so nothing is inherited from the
            // binary we're about to overwrite.
            var out = [UInt8](repeating: 0, count: sectionLength)
            for chunk in chunks {
                let bytes = try readChunk(chunk, from: folder, engine: engine,
                                          flagTable: flagTable, fileSystem: fileSystem)
                guard bytes.count == chunk.length else {
                    throw SaveSectionsOpsErrors.rebuiltSizeMismatch(
                        section: "\(sectionName)/\(chunk.chunk.name)",
                        expected: chunk.length, actual: bytes.count, .init()
                    )
                }
                out.replaceSubrange(chunk.offset ..< (chunk.offset + chunk.length), with: bytes)
            }
            for gap in gaps(around: chunks, sectionLength: sectionLength) {
                let file = folder.file(gapFilename(offset: gap.offset))
                guard let bytes = fileSystem.readFile(at: file)?.allData else {
                    throw SaveSectionsOpsErrors.missingArtifact(file: file, .init())
                }
                guard bytes.length == gap.length else {
                    throw SaveSectionsOpsErrors.rebuiltSizeMismatch(
                        section: "\(sectionName)/\(gapFilename(offset: gap.offset))",
                        expected: gap.length, actual: bytes.length, .init()
                    )
                }
                out.replaceSubrange(gap.offset ..< (gap.offset + gap.length), with: bytes.rawBytes)
            }

            try fileSystem.writeFile(
                GoDData(byteStream: out, byteOrder: .big),
                at: slotFolder.file(binary.name),
                overwrite: true
            )
            logger?.log(.info("Save sections: recomposed '\(sectionName)' (\(sectionLength) bytes) from \(folder.path)"))
        }

        logger?.log(.taskStatus(taskName: "Build Save Sections", status: .completed(true)))
    }

    private static func readChunk(
        _ chunk: ResolvedChunk,
        from folder: Folder,
        engine: GenericEngine,
        flagTable: XDFlagTable?,
        fileSystem: FileSystemTree
    ) throws -> [UInt8] {
        switch chunk.chunk {
        case .flags(let spec):
            guard let flagTable else {
                throw SaveSectionsOpsErrors.missingFlagTable(chunk: spec.name, .init())
            }
            let file = folder.file("\(spec.name).csv")
            guard let bytes = fileSystem.readFile(at: file)?.allData else {
                throw SaveSectionsOpsErrors.missingArtifact(file: file, .init())
            }
            return try flagBytes(
                csv: String(decoding: bytes.rawBytes, as: UTF8.self),
                banks: spec.banks, table: flagTable, chunkName: spec.name
            )

        case .structInstance(let spec):
            let file = folder.file("\(spec.name).json")
            guard let bytes = fileSystem.readFile(at: file)?.allData else {
                throw SaveSectionsOpsErrors.missingArtifact(file: file, .init())
            }
            let definition = try engine.getStruct(spec.type) as StructDefinition
            return try StructData(definition: definition, json: bytes).data.rawBytes

        case .table(let spec):
            let file = folder.file("\(spec.name).csv")
            guard let bytes = fileSystem.readFile(at: file)?.allData else {
                throw SaveSectionsOpsErrors.missingArtifact(file: file, .init())
            }
            let definition = try engine.getStruct(spec.type) as StructDefinition
            let decoded = try StructTableCSV.decode(
                String(decoding: bytes.rawBytes, as: UTF8.self), definition: definition
            )
            var out: [UInt8] = []
            for entry in decoded.entries { out += entry.data.rawBytes }
            return out
        }
    }

    /// Rebuilds a flag chunk's bytes from the decoded-flag CSV.
    ///
    /// Only `id` and `value` are read — every bit position comes from the flag
    /// table, so a CSV that disagrees about widths is ignored rather than
    /// trusted. Rows match by `id`, so a partial or reordered file works; an
    /// `id` the table doesn't define is an error rather than a silent no-op,
    /// since it would otherwise look like it had been applied.
    static func flagBytes(
        csv text: String,
        banks: [SectionLayout.Chunk.Flags.Bank],
        table: XDFlagTable,
        chunkName: String
    ) throws -> [UInt8] {
        var words: [Int: [UInt32]] = [:]
        for (index, bank) in banks.enumerated() {
            words[index + 1] = [UInt32](repeating: 0, count: bank.length / 4)
        }

        let rows = try CSV.parse(text)
        guard let header = rows.first else {
            throw SaveSectionsOpsErrors.malformedFlagCSV(chunk: chunkName, reason: "no header row", .init())
        }
        guard let idColumn = header.firstIndex(of: "id"),
              let valueColumn = header.firstIndex(of: "value") else {
            throw SaveSectionsOpsErrors.malformedFlagCSV(
                chunk: chunkName,
                reason: "header must name both 'id' and 'value'; found \(header.joined(separator: ", "))", .init()
            )
        }
        let byID = Dictionary(table.flags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (offset, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy(\.isEmpty) { continue }
            guard row.count > max(idColumn, valueColumn),
                  let id = Int(row[idColumn].trimmingCharacters(in: .whitespaces)) else {
                throw SaveSectionsOpsErrors.malformedFlagCSV(
                    chunk: chunkName, reason: "row \(offset + 2) has no readable id", .init()
                )
            }
            guard let flag = byID[id] else {
                throw SaveSectionsOpsErrors.malformedFlagCSV(
                    chunk: chunkName,
                    reason: "row \(offset + 2) names flag \(id), which the flag table doesn't define", .init()
                )
            }
            let raw = row[valueColumn].trimmingCharacters(in: .whitespaces)
            guard let value = raw.isEmpty ? 0 : UInt32(raw) else {
                throw SaveSectionsOpsErrors.malformedFlagCSV(
                    chunk: chunkName,
                    reason: "flag \(id) has value '\(raw)', which isn't a non-negative integer", .init()
                )
            }
            guard var bank = words[flag.bank] else { continue }
            XDFlagTable.setValue(value, of: flag, in: &bank)
            words[flag.bank] = bank
        }

        var out: [UInt8] = []
        for index in banks.indices { out += XDFlagTable.bytes(of: words[index + 1] ?? []) }
        return out
    }

    /// Same lookup as the dump's, but keeping the whole decoded object so the
    /// banks can be replaced and the rest written back unchanged.
    static func sectionJSONForWriting(
        named sectionName: String,
        in folder: Folder,
        fileSystem: FileSystemTree
    ) throws -> (artifact: String, json: [String: Any]) {
        try sectionJSON(named: sectionName, in: folder, fileSystem: fileSystem)
    }

    /// Splits the recomposed bank bytes back across the properties they came
    /// from, leaving every other property of the section untouched.
    static func writeBankBytes(
        _ bytes: [UInt8],
        banks: [SectionLayout.Chunk.Flags.Bank],
        into json: [String: Any]
    ) -> [String: Any] {
        var root = json
        var data = (root["data"] as? [String: Any]) ?? root
        var cursor = 0
        for bank in banks {
            guard let field = bank.field else { continue }
            let end = min(cursor + bank.length, bytes.count)
            data[field] = Array(bytes[cursor ..< end]).map { Int($0) }
            cursor += bank.length
        }
        if root["data"] is [String: Any] { root["data"] = data } else { root = data }
        return root
    }
}
