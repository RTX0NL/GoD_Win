import GoDFoundation
import Structs
import GoDEngine
import Colosseum

extension ColoSaveOps {

    /// Folder name for save slot N (1-indexed in the dump folder, but
    /// 0-indexed when reading PKHeX-style slot bins).
    static func slotFolderName(_ index: Int) -> String { "Slot \(index + 1)" }
    static let saveMetadataFilename = "save-metadata.json"
    static let slotMetadataFilename = "slot-metadata.json"
    static let rawSlotFilename = "raw-slot.bin"

    struct SaveMetadata: Codable, Equatable {
        let decrypted: Bool
        let slots: [SlotSummary]
        let latestSlotIndex: Int?

        struct SlotSummary: Codable, Equatable {
            let counter: UInt32
            let headerChecksumValid: Bool?
            let bodyChecksumValid: Bool?
        }
    }

    struct SlotMetadata: Codable, Equatable {
        let header: ColosseumSaveSlot.Header
        let decrypted: Bool
        let headerChecksumValid: Bool?
        let bodyChecksumValid: Bool?
        let sections: [SectionEntry]

        /// Same shape as `XDSaveOps.SlotMetadata.SectionEntry` — both
        /// games dump through the same section taxonomy. Each section
        /// dumps to *either* `bin` *or* `json`, never both.
        struct SectionEntry: Codable, Equatable {
            let index: Int
            let name: String
            let type: SaveSectionType
            let structType: String?
            let count: Int?
            let offset: Int
            let length: Int
            let bin: String?
            let json: String?
        }
    }

    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpColosseumSave(unpackedFolder, outputFolder, overwrite, decrypted, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                try dumpColosseumSave(
                    unpackedFolder: unpackedFolder,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    decrypted: decrypted,
                    engine: engine,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func dumpColosseumSave(
        unpackedFolder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump Colo Save", status: .started))

        var summaries: [SaveMetadata.SlotSummary] = []
        for i in 0..<ColoSaveCardFile.slotCount {
            let path = unpackedFolder.file(GCIOps.coloSlotFilename(i))
            guard let raw = fileSystem.readFile(at: path) else {
                throw ColoSaveOpsErrors.missingSlot(file: path, .init())
            }
            let summary = try dumpOneSlot(
                slotBytes: raw,
                slotFolder: outputFolder.folder(slotFolderName(i)),
                overwrite: overwrite,
                decrypted: decrypted,
                engine: engine,
                fileSystem: fileSystem,
                logger: logger
            )
            summaries.append(summary)
        }

        // Pick latest slot by counter — PKHeX `ColoCrypto.DetectLatest`.
        let latest = summaries.enumerated().max { $0.element.counter < $1.element.counter }?.offset

        let topLevel = SaveMetadata(
            decrypted: decrypted,
            slots: summaries,
            latestSlotIndex: latest
        )
        try fileSystem.encodeJSON(
            topLevel,
            to: outputFolder.file(saveMetadataFilename),
            overwrite: overwrite
        )

        logger?.log(.taskStatus(taskName: "Dump Colo Save", status: .completed(true)))
    }

    private static func dumpOneSlot(
        slotBytes: GoDData,
        slotFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> SaveMetadata.SlotSummary {
        // Decrypt unless the caller asserts the input is already
        // plaintext. Decrypt also returns header/body checksum
        // validity, which we propagate into the metadata.
        let plaintextBytes: GoDData
        var headerOK: Bool? = nil
        var bodyOK: Bool? = nil
        if decrypted {
            plaintextBytes = slotBytes
        } else {
            plaintextBytes = GoDData(byteStream: slotBytes.rawBytes, byteOrder: .big)
            let result = try ColoSaveCipher.decrypt(slot: plaintextBytes)
            headerOK = result.headerValid
            bodyOK = result.bodyValid
            if !(result.headerValid && result.bodyValid) {
                logger?.log(.info("Colo slot decrypt: header=\(result.headerValid), body=\(result.bodyValid)"))
            }
        }

        let slot = try ColosseumSaveSlot(raw: plaintextBytes)

        fileSystem.writeFile(
            slot.raw,
            at: slotFolder.file(rawSlotFilename),
            overwrite: overwrite
        )

        // Walk the engine's section array sequentially. Each
        // section's physical offset is the cumulative sum of prior
        // section lengths added to `bodyBaseOffset`; each length
        // comes from the section's struct binding (resolved via
        // `sectionStructTypes` → `engine.structs`). Both are
        // therefore derivable — the spec only carries name + type.
        // Same emitter as XD — `XDSaveOps.emitJSON` handles
        // .struct / .table / .binary uniformly across both games.
        var entries: [SlotMetadata.SectionEntry] = []
        let slotBytes = slot.raw
        var cursor = engine.data.bodyBaseOffset
        for (index, spec) in engine.data.saveSections.enumerated() {
            let structTypeName = engine.data.sectionStructTypes[index]
            guard let typeName = structTypeName,
                  let definition = try? engine.getStruct(typeName) as StructDefinition else {
                logger?.log(.info("Colo section '\(spec.name)' (idx \(index)): no struct binding — can't derive length, skipping"))
                continue
            }
            // Total section length = struct length × count for
            // tables, struct length × 1 otherwise.
            let perEntry = definition.length
            let totalLength = (spec.type == .table) ? perEntry * (spec.count ?? 1) : perEntry
            let offset = cursor
            cursor += totalLength

            guard offset + totalLength <= slotBytes.length else {
                logger?.log(.info("Colo section '\(spec.name)' at +\(String(format: "0x%X", offset)) extends beyond slot (len \(totalLength)) — stopping"))
                break
            }
            guard let bytes = slotBytes.read(atAddress: offset, length: totalLength) else { continue }

            let stem = String(format: "%02d-%@", index, spec.name)

            // Try JSON first; fall back to `.bin` when the JSON
            // path declines (binary section, missing struct binding,
            // or bytes too short to parse).
            let jsonFilename = try XDSaveOps.emitJSON(
                bytes: bytes,
                spec: spec,
                structTypeName: structTypeName,
                stem: stem,
                slotFolder: slotFolder,
                engine: engine,
                fileSystem: fileSystem,
                overwrite: overwrite,
                logger: logger
            )

            let binFilename: String?
            if jsonFilename == nil {
                let filename = "\(stem).bin"
                fileSystem.writeFile(
                    bytes,
                    at: slotFolder.file(filename),
                    overwrite: overwrite
                )
                binFilename = filename
            } else {
                binFilename = nil
            }

            entries.append(SlotMetadata.SectionEntry(
                index: index,
                name: spec.name,
                type: spec.type,
                structType: structTypeName,
                count: spec.count,
                offset: offset,
                length: totalLength,
                bin: binFilename,
                json: jsonFilename
            ))
        }

        let slotMetadata = SlotMetadata(
            header: slot.header,
            decrypted: true,
            headerChecksumValid: headerOK,
            bodyChecksumValid: bodyOK,
            sections: entries
        )
        try fileSystem.encodeJSON(
            slotMetadata,
            to: slotFolder.file(slotMetadataFilename),
            overwrite: overwrite
        )

        return SaveMetadata.SlotSummary(
            counter: slot.header.counter,
            headerChecksumValid: headerOK,
            bodyChecksumValid: bodyOK
        )
    }
}
