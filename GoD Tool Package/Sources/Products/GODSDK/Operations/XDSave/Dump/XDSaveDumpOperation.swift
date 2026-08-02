import GoDFoundation
import Structs
import GoDEngine
import XD

extension XDSaveOps {

    /// Only the latest slot is dumped, into this single folder. The
    /// non-latest slot stays untouched in the unpacked GCI and passes
    /// straight through on rebuild.
    static let latestSlotFolderName = "Latest Slot"
    static let saveMetadataFilename = "save-metadata.json"
    static let slotMetadataFilename = "slot-metadata.json"
    static let rawSlotFilename = "raw-slot.bin"

    /// Top-level metadata that lives next to the slot folder.
    struct SaveMetadata: Codable, Equatable {
        let decrypted: Bool
        /// Which physical slot ("A" or "B") is the latest save and was
        /// the one dumped. Build replaces this slot and leaves the
        /// other as-is.
        let latestSlot: String
        let slotA: SlotSummary
        let slotB: SlotSummary

        struct SlotSummary: Codable, Equatable {
            let counter: UInt32
            let magic: [UInt8]
        }
    }

    /// Per-slot metadata file. Captures the plaintext slot header, the
    /// full 0xA8 header region (base64 — the seed, 24-entry TOC, and
    /// size fields the from-scratch rebuild carries verbatim), plus the
    /// 16-entry section list.
    struct SlotMetadata: Codable, Equatable {
        let header: XDSaveSlot.Header
        /// "A" or "B" — the physical slot these artifacts came from.
        let physicalSlot: String
        /// Base64 of `slot[0x00..0xA8]`: cipher seed (0x08), placeholder
        /// checksum tags (0x10), the 24-entry sub-block TOC + scattered
        /// size fields (0x18..0x98), and the header tail. Carried as
        /// opaque metadata — the sub-block *payloads* are rebuilt fresh
        /// from their artifacts, and the inter-block gaps + unused tail
        /// are zeroed.
        let headerRegion: String
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
        guard let slotABytes = fileSystem.readFile(at: slotAFile)?.allData else {
            throw XDSaveOpsErrors.missingSlot(file: slotAFile, .init())
        }
        guard let slotBBytes = fileSystem.readFile(at: slotBFile)?.allData else {
            throw XDSaveOpsErrors.missingSlot(file: slotBFile, .init())
        }

        // Sub-block count comes from the registered section list, not a
        // hardcoded/persisted number — one source of truth.
        let layout = xdEngine.data.saveSlotLayout.with(subBlockCount: xdEngine.data.saveSections.count)
        let slotA = try XDSaveSlot(raw: decryptedPlaintext(of: slotABytes, decrypted: decrypted, logger: logger), layout: layout)
        let slotB = try XDSaveSlot(raw: decryptedPlaintext(of: slotBBytes, decrypted: decrypted, logger: logger), layout: layout)

        // The live save is the slot with the higher save counter — XD
        // ping-pongs writes between the two slots, bumping the counter
        // each save. Dump only that one; ties favour A.
        let latestIsA = slotA.header.counter >= slotB.header.counter
        let latest = latestIsA ? slotA : slotB
        let latestLetter = latestIsA ? "A" : "B"

        try dumpOneSlot(
            slot: latest,
            physicalSlot: latestLetter,
            slotFolder: outputFolder.folder(latestSlotFolderName),
            overwrite: overwrite,
            xdEngine: xdEngine,
            fileSystem: fileSystem,
            logger: logger
        )

        let topLevel = SaveMetadata(
            decrypted: decrypted,
            latestSlot: latestLetter,
            slotA: .init(counter: slotA.header.counter, magic: slotA.header.magic),
            slotB: .init(counter: slotB.header.counter, magic: slotB.header.magic)
        )
        try fileSystem.encodeJSON(
            topLevel,
            to: outputFolder.file(saveMetadataFilename),
            overwrite: overwrite
        )

        logger?.log(.info("XD save dump: latest is slot \(latestLetter) (counter \(latest.header.counter)) — dumped to \(latestSlotFolderName)/"))
        logger?.log(.taskStatus(taskName: "Dump XD Save", status: .completed(true)))
    }

    /// Decrypts an encrypted slot (or passes through an already-plain
    /// one), returning the plaintext bytes ready for `XDSaveSlot`.
    private static func decryptedPlaintext(
        of slotBytes: GoDData,
        decrypted: Bool,
        logger: Logger?
    ) throws -> GoDData {
        if decrypted { return slotBytes }
        let copy = GoDData(byteStream: slotBytes.rawBytes, byteOrder: .big)
        let ok = try XDSaveCipher.decrypt(slot: copy)
        if !ok {
            logger?.log(.info("XD slot decrypt: running-sum tags did not match — slot may be corrupt"))
        }
        return copy
    }

    private static func dumpOneSlot(
        slot: XDSaveSlot,
        physicalSlot: String,
        slotFolder: Folder,
        overwrite: Bool,
        xdEngine: XDEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        // raw-slot.bin holds the *plaintext* slot — kept purely as a
        // read-only reference/diff artifact. Build never reads it; it
        // rebuilds each sub-block from its artifact and carries only the
        // header region.
        try fileSystem.writeFile(
            slot.raw,
            at: slotFolder.file(rawSlotFilename),
            overwrite: overwrite
        )

        // Capture the full header region (seed + TOC + size fields) so
        // the build can rebuild from scratch without touching raw-slot.
        let headerRegion = slot.raw.read(atAddress: 0, length: UInt(slot.layout.subBlockBaseOffset)) ?? slot.raw
        let headerRegionBase64 = Data(headerRegion.rawBytes).base64EncodedString()

        // Walk the engine's section list. The array's position is
        // the in-slot TOC index; XD reads each section's physical
        // offset and length from the slot itself, so the engine
        // spec just provides name + type.
        var entries: [SlotMetadata.SectionEntry] = []
        for index in 0..<slot.layout.subBlockCount {
            let offset = slot.subBlockOffset(at: index)
            let length = slot.subBlockSize(at: index)
            let spec = (index < xdEngine.data.saveSections.count)
                ? xdEngine.data.saveSections[index]
                : .binary(name: "Section\(index)")

            guard let bytes = slot.subBlockBytes(at: index) else {
                // Zero-size sections aren't dumped at all — match
                // PKHeX's behavior of leaving them implicit.
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
                length: length,
                bin: binFilename,
                json: jsonFilename
            ))
        }

        let slotMetadata = SlotMetadata(
            header: slot.header,
            physicalSlot: physicalSlot,
            headerRegion: headerRegionBase64,
            decrypted: true,
            sections: entries
        )
        try fileSystem.encodeJSON(
            slotMetadata,
            to: slotFolder.file(slotMetadataFilename),
            overwrite: overwrite
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
            // JSON is emitted *only* when the struct tiles the section
            // exactly — that's what makes the JSON a lossless, single
            // editable artifact for the whole section (padding round-
            // trips as uint8 arrays). A struct that's shorter or longer
            // than the section would drop or overrun bytes, so we dump
            // the full `.bin` instead and flag it: extend the struct's
            // padding to make the section editable.
            guard bytes.length == definition.length else {
                logger?.log(.info("Save section '\(spec.name)': struct '\(typeName)' is \(definition.length) bytes but the section is \(bytes.length) — extend the struct's padding to make it editable; dumping .bin for now"))
                return nil
            }
            let parsed = StructData(definition: definition, data: bytes)
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
            // Exact tiling only — the row run must cover the whole
            // section so rebuild reproduces it byte-for-byte.
            guard count > 0, count * entrySize == bytes.length else {
                logger?.log(.info("Save section '\(spec.name)': table \(count) × \(entrySize) != section \(bytes.length) bytes — dumping .bin instead"))
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
