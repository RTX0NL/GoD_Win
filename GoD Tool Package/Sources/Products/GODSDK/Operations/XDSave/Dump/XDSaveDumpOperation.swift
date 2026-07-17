import GoDFoundation
import Structs
import GoDEngine
import XD

extension XDSaveOps {

    static let slot1FolderName = "Slot 1"
    static let slot2FolderName = "Slot 2"
    static let saveMetadataFilename = "save-metadata.json"
    static let slotMetadataFilename = "slot-metadata.json"
    static let rawSlotFilename = "raw-slot.bin"

    /// Top-level metadata that lives next to the slot folders.
    struct SaveMetadata: Codable, Equatable {
        let decrypted: Bool
        let slotA: SlotSummary
        let slotB: SlotSummary

        struct SlotSummary: Codable, Equatable {
            let counter: UInt32
            let magic: [UInt8]
        }
    }

    /// Per-slot metadata file. Captures the plaintext slot header plus
    /// the 16-entry section list (only meaningful post-decrypt, since
    /// the offset/size tables sit inside the encrypted region).
    struct SlotMetadata: Codable, Equatable {
        let header: XDSaveSlot.Header
        let decrypted: Bool
        let sections: [SectionEntry]

        /// One per section that actually has bytes (zero-size
        /// sub-blocks are skipped). Each section dumps to *either*
        /// `bin` *or* `json`, never both: when the engine has a
        /// resolvable struct binding for the index, the section's
        /// JSON sidecar is the source of truth and we omit the
        /// raw `.bin`; for `.binary`-typed sections (or struct
        /// bindings that fail to resolve) we fall back to the
        /// `.bin`.
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
            case let .dumpXDSave(unpackedFolder, outputFolder, overwrite, decrypted, xdEnginePath):
                let xdEngine = try XDEngine(from: xdEnginePath, in: fileSystem)
                try dumpXDSave(
                    unpackedFolder: unpackedFolder,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    decrypted: decrypted,
                    xdEngine: xdEngine,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func dumpXDSave(
        unpackedFolder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        xdEngine: XDEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump XD Save", status: .started))

        let slotAFile = unpackedFolder.file(GCIOps.slotAFilename)
        let slotBFile = unpackedFolder.file(GCIOps.slotBFilename)
        guard let slotABytes = fileSystem.readFile(at: slotAFile) else {
            throw XDSaveOpsErrors.missingSlot(file: slotAFile, .init())
        }
        guard let slotBBytes = fileSystem.readFile(at: slotBFile) else {
            throw XDSaveOpsErrors.missingSlot(file: slotBFile, .init())
        }

        let slotASummary = try dumpOneSlot(
            slotBytes: slotABytes,
            slotFolder: outputFolder.folder(slot1FolderName),
            overwrite: overwrite,
            decrypted: decrypted,
            xdEngine: xdEngine,
            fileSystem: fileSystem,
            logger: logger
        )
        let slotBSummary = try dumpOneSlot(
            slotBytes: slotBBytes,
            slotFolder: outputFolder.folder(slot2FolderName),
            overwrite: overwrite,
            decrypted: decrypted,
            xdEngine: xdEngine,
            fileSystem: fileSystem,
            logger: logger
        )

        let topLevel = SaveMetadata(
            decrypted: decrypted,
            slotA: slotASummary,
            slotB: slotBSummary
        )
        try fileSystem.encodeJSON(
            topLevel,
            to: outputFolder.file(saveMetadataFilename),
            overwrite: overwrite
        )

        logger?.log(.taskStatus(taskName: "Dump XD Save", status: .completed(true)))
    }

    private static func dumpOneSlot(
        slotBytes: GoDData,
        slotFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        xdEngine: XDEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> SaveMetadata.SlotSummary {
        let plaintextBytes: GoDData
        if decrypted {
            plaintextBytes = slotBytes
        } else {
            plaintextBytes = GoDData(byteStream: slotBytes.rawBytes, byteOrder: .big)
            let ok = try XDSaveCipher.decrypt(slot: plaintextBytes)
            if !ok {
                logger?.log(.info("XD slot decrypt: running-sum tags did not match — slot may be corrupt"))
            }
        }

        let slot = try XDSaveSlot(raw: plaintextBytes)

        // raw-slot.bin holds the *plaintext* slot. Build reads it
        // back, re-encrypts, and writes to slot-{a,b}.bin.
        fileSystem.writeFile(
            slot.raw,
            at: slotFolder.file(rawSlotFilename),
            overwrite: overwrite
        )

        // Walk the engine's section list. The array's position is
        // the in-slot TOC index; XD reads each section's physical
        // offset and length from the slot itself, so the engine
        // spec just provides name + type.
        var entries: [SlotMetadata.SectionEntry] = []
        for index in 0..<XDSaveSlot.subBlockCount {
            let offset = slot.subBlockOffset(at: index)
            let length = slot.subBlockSize(at: index)
            let spec = (index < xdEngine.data.saveSections.count)
                ? xdEngine.data.saveSections[index]
                : .binary(name: "Section\(index)")

            guard let bytes = slot.subBlockBytes(at: index) else {
                // Zero-size sections aren't dumped at all — match
                // PKHeX's behaviour of leaving them implicit.
                continue
            }

            let stem = String(format: "%02d-%@", index, spec.name)
            let structTypeName = xdEngine.data.sectionStructTypes[index]

            // Try the JSON path first. When it produces a sidecar,
            // it's the canonical edit form for this section and the
            // raw `.bin` is redundant — skip it. When it returns nil
            // (no struct binding, struct missing, bytes too short,
            // or section is `.binary`), fall back to the `.bin`.
            let jsonFilename = try emitJSON(
                bytes: bytes,
                spec: spec,
                structTypeName: structTypeName,
                stem: stem,
                slotFolder: slotFolder,
                engine: xdEngine,
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
                length: length,
                bin: binFilename,
                json: jsonFilename
            ))
        }

        let slotMetadata = SlotMetadata(
            header: slot.header,
            decrypted: true,
            sections: entries
        )
        try fileSystem.encodeJSON(
            slotMetadata,
            to: slotFolder.file(slotMetadataFilename),
            overwrite: overwrite
        )

        return SaveMetadata.SlotSummary(
            counter: slot.header.counter,
            magic: slot.header.magic
        )
    }

    /// Emits the section's JSON sidecar based on its `SaveSectionType`
    /// and the engine's index→struct binding.
    ///
    /// Returns the JSON filename written, or nil when:
    ///   - section is `.binary` (no JSON path), or
    ///   - the engine has no struct binding for this section index
    ///     (no entry in `sectionStructTypes`), or
    ///   - the named struct isn't registered in `engine.structs`, or
    ///   - the section bytes are too small to parse one entry.
    /// In all "skip" cases the `.bin` already on disk is the source
    /// of truth — nothing's lost from a round-trip perspective.
    static func emitJSON<E: Engine>(
        bytes: GoDData,
        spec: SaveSectionSpec,
        structTypeName: String?,
        stem: String,
        slotFolder: Folder,
        engine: E,
        fileSystem: FileSystemTree,
        overwrite: Bool,
        logger: Logger?
    ) throws -> String? {
        switch spec.type {
        case .binary:
            return nil

        case .struct:
            guard let typeName = structTypeName,
                  let definition = try? engine.getStruct(typeName) as StructDefinition else {
                logger?.log(.info("Save section '\(spec.name)': no struct binding (engine.sectionStructTypes missing or struct '\(structTypeName ?? "<nil>")' unregistered) — falling back to .bin only"))
                return nil
            }
            guard bytes.length >= definition.length else {
                logger?.log(.info("Save section '\(spec.name)': bytes (\(bytes.length)) shorter than struct '\(typeName)' (\(definition.length)) — skipping JSON"))
                return nil
            }
            let head = bytes.read(atAddress: 0, length: definition.length) ?? bytes
            let parsed = StructData(definition: definition, data: head)
            let filename = "\(stem).json"
            try fileSystem.encodeJSON(parsed, to: slotFolder.file(filename), overwrite: overwrite)
            return filename

        case .table:
            guard let typeName = structTypeName,
                  let definition = try? engine.getStruct(typeName) as StructDefinition else {
                logger?.log(.info("Save section '\(spec.name)': no struct binding (engine.sectionStructTypes missing or struct '\(structTypeName ?? "<nil>")' unregistered) — falling back to .bin only"))
                return nil
            }
            let entrySize = definition.length
            guard entrySize > 0 else { return nil }
            let count = spec.count ?? (bytes.length / entrySize)
            guard count > 0, count * entrySize <= bytes.length else {
                logger?.log(.info("Save section '\(spec.name)': table count \(count) × \(entrySize) exceeds \(bytes.length) bytes — skipping JSON"))
                return nil
            }
            var rows: [StructData] = []
            for i in 0..<count {
                let row = bytes.read(atAddress: i * entrySize, length: entrySize)
                    ?? GoDData(length: entrySize, byteOrder: .big)
                rows.append(StructData(definition: definition, data: row))
            }
            let filename = "\(stem).json"
            try fileSystem.encodeJSON(rows, to: slotFolder.file(filename), overwrite: overwrite)
            return filename
        }
    }
}
