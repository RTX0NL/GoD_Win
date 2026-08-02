import GoDFoundation
import Structs
import GoDEngine
import Colosseum

extension ColoSaveOps {

    /// Only the latest slot is dumped, into this single folder. The
    /// other two slots stay untouched in the unpacked GCI and pass
    /// straight through on rebuild.
    static let latestSlotFolderName = "Latest Slot"
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
        /// 0-based physical slot index these artifacts came from.
        let physicalSlotIndex: Int
        /// Base64 of `slot[0x00..bodyBaseOffset]` (magic + counter) —
        /// the header bytes before the first section. Everything from
        /// bodyBaseOffset on is reconstructed from the sections.
        let headerRegion: String
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

        // Parse every slot (decrypt + header/body checksum validity)
        // so we can pick the latest by counter and summarise all of
        // them, but dump only the latest.
        var summaries: [SaveMetadata.SlotSummary] = []
        var parsed: [(slot: ColosseumSaveSlot, headerOK: Bool?, bodyOK: Bool?)] = []
        for i in 0..<ColoSaveCardFile.slotCount {
            let path = unpackedFolder.file(GCIOps.coloSlotFilename(i))
            guard let raw = fileSystem.readFile(at: path)?.allData else {
                throw ColoSaveOpsErrors.missingSlot(file: path, .init())
            }
            let (plaintext, headerOK, bodyOK) = try decryptedPlaintext(of: raw, decrypted: decrypted, logger: logger)
            let slot = try ColosseumSaveSlot(raw: plaintext)
            parsed.append((slot, headerOK, bodyOK))
            summaries.append(.init(
                counter: slot.header.counter,
                headerChecksumValid: headerOK,
                bodyChecksumValid: bodyOK
            ))
        }

        // Latest = highest save counter — PKHeX `ColoCrypto.DetectLatest`.
        let latestIndex = summaries.enumerated().max { $0.element.counter < $1.element.counter }?.offset ?? 0
        let latest = parsed[latestIndex]

        try dumpOneSlot(
            slot: latest.slot,
            physicalSlotIndex: latestIndex,
            headerOK: latest.headerOK,
            bodyOK: latest.bodyOK,
            bodyBaseOffset: engine.data.bodyBaseOffset,
            slotFolder: outputFolder.folder(latestSlotFolderName),
            overwrite: overwrite,
            engine: engine,
            fileSystem: fileSystem,
            logger: logger
        )

        let topLevel = SaveMetadata(
            decrypted: decrypted,
            slots: summaries,
            latestSlotIndex: latestIndex
        )
        try fileSystem.encodeJSON(
            topLevel,
            to: outputFolder.file(saveMetadataFilename),
            overwrite: overwrite
        )

        logger?.log(.info("Colo save dump: latest is slot \(latestIndex + 1) (counter \(latest.slot.header.counter)) — dumped to \(latestSlotFolderName)/"))
        logger?.log(.taskStatus(taskName: "Dump Colo Save", status: .completed(true)))
    }

    /// Decrypts a slot (or passes an already-plaintext one through),
    /// returning the plaintext plus header/body checksum validity
    /// (nil when the input was already decrypted).
    private static func decryptedPlaintext(
        of slotBytes: GoDData,
        decrypted: Bool,
        logger: Logger?
    ) throws -> (GoDData, Bool?, Bool?) {
        if decrypted { return (slotBytes, nil, nil) }
        let copy = GoDData(byteStream: slotBytes.rawBytes, byteOrder: .big)
        let result = try ColoSaveCipher.decrypt(slot: copy)
        if !(result.headerValid && result.bodyValid) {
            logger?.log(.info("Colo slot decrypt: header=\(result.headerValid), body=\(result.bodyValid)"))
        }
        return (copy, result.headerValid, result.bodyValid)
    }

    private static func dumpOneSlot(
        slot: ColosseumSaveSlot,
        physicalSlotIndex: Int,
        headerOK: Bool?,
        bodyOK: Bool?,
        bodyBaseOffset: Int,
        slotFolder: Folder,
        overwrite: Bool,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        // raw-slot.bin is a read-only reference/diff artifact. Build
        // never reads it — it reconstructs from header region + sections.
        try fileSystem.writeFile(
            slot.raw,
            at: slotFolder.file(rawSlotFilename),
            overwrite: overwrite
        )

        // Capture the pre-section header (magic + counter). Everything
        // from bodyBaseOffset on is covered by the sections.
        let headerRegion = slot.raw.read(atAddress: 0, length: UInt(bodyBaseOffset)) ?? slot.raw
        let headerRegionBase64 = Data(headerRegion.rawBytes).base64EncodedString()

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
                try fileSystem.writeFile(
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
            physicalSlotIndex: physicalSlotIndex,
            headerRegion: headerRegionBase64,
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
    }
}
