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
    static let slotHeaderFilename = "slot-header.bin"
    static let slotHeaderJSONFilename = "slot-header.json"
    /// Struct the slot header is decoded through when the engine has it.
    static let slotHeaderStructName = "XDSaveSlotHeader"

    /// Writes the slot header as JSON when the engine's struct tiles it
    /// exactly, else as raw bytes. Returns the filename written.
    ///
    /// The struct has to match the header length exactly for the JSON to
    /// be lossless — a shorter one would drop the tail and a longer one
    /// would overrun — so a mismatch falls back to `.bin` with a warning
    /// rather than dumping something that can't rebuild.
    static func emitSlotHeader<E: Engine>(
        _ headerRegion: GoDData,
        structName: String = XDSaveOps.slotHeaderStructName,
        slotFolder: Folder,
        engine: E,
        fileSystem: FileSystemTree,
        overwrite: Bool,
        logger: Logger?
    ) throws -> String {
        if let definition = try? engine.getStruct(structName) as StructDefinition,
           definition.length == headerRegion.length {
            let parsed = StructData(definition: definition, data: headerRegion)
            try fileSystem.encodeJSON(
                parsed, to: slotFolder.file(slotHeaderJSONFilename), overwrite: overwrite
            )
            return slotHeaderJSONFilename
        }
        logger?.log(.warning(
            "Slot header: no '\(structName)' struct of \(headerRegion.length) bytes "
            + "in the engine — dumping \(slotHeaderFilename), so the header is not editable by field"
        ))
        try fileSystem.writeFile(
            headerRegion, at: slotFolder.file(slotHeaderFilename), overwrite: overwrite
        )
        return slotHeaderFilename
    }

    static func readHeaderRegion<E: Engine>(
        slotMeta: SlotMetadata,
        slotFolder: Folder,
        engine: E,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        let filename = slotMeta.headerRegionFile
        let path = slotFolder.file(filename)
        guard let bytes = fileSystem.readFile(at: path)?.allData else {
            throw XDSaveOpsErrors.missingHeaderRegionFile(file: path, .init())
        }
        guard filename.hasSuffix(".json") else { return bytes }
        guard let definition = try? engine.getStruct(slotHeaderStructName) as StructDefinition else {
            throw XDSaveOpsErrors.missingHeaderStruct(name: slotHeaderStructName, .init())
        }
        let parsed = try StructData(definition: definition, json: bytes)
        return GoDData(byteStream: parsed.data.rawBytes, byteOrder: .big)
    }


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
            /// Whether the slot's four running-sum body tags matched on
            /// decrypt. `nil` when the input was already plaintext, so
            /// there was nothing to check. Colosseum's dump has recorded
            /// the equivalent since it was written; XD's did not, which
            /// is why a blank card used to dump as though it were a save.
            let checksumValid: Bool?
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
        /// File holding `slot[0x00..0xA8]` verbatim: the cipher seed
        /// (0x08), the checksum tags (0x10), the sub-block size and
        /// offset tables (0x20..0x80) and a few trailing words. This is
        /// real save data, so it is dumped as a file of its own; the
        /// sub-block *payloads* are rebuilt from their own artifacts,
        /// and the inter-block gaps and unused tail are filler the game
        /// re-randomises (measured 7.97 bits/byte, sharing nothing with
        /// live sections) and are not carried.
        var headerRegionFile: String
        let decrypted: Bool
        let sections: [SectionEntry]

        /// One per section that actually has bytes (zero-size
        /// sub-blocks are skipped). Most sections dump to *either*
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
        let (plainA, validA) = try decryptedPlaintext(
            of: slotABytes, decrypted: decrypted,
            checksumOffset: layout.checksumOffset, logger: logger, slot: "A"
        )
        let (plainB, validB) = try decryptedPlaintext(
            of: slotBBytes, decrypted: decrypted,
            checksumOffset: layout.checksumOffset, logger: logger, slot: "B"
        )
        let slotA = try XDSaveSlot(raw: plainA, layout: layout)
        let slotB = try XDSaveSlot(raw: plainB, layout: layout)

        // A freshly formatted memory-card file has both slots blank — the
        // decrypt produces garbage whose running-sum tags don't match, and
        // the sub-block TOC it yields is all zeroes, so the dump used to
        // emit an empty section list and the build failed much later with
        // "section 0 has no reconstructed bytes". Reject it here instead,
        // naming the real cause.
        if validA == false && validB == false {
            throw XDSaveOpsErrors.noValidSlot(file: slotAFile, .init())
        }

        // The live save is the slot with the higher save counter — XD
        // ping-pongs writes between the two slots, bumping the counter
        // each save. A slot whose checksum failed is never preferred over
        // one that passed, however high its counter: on a half-written or
        // partly blank card the intact slot is the one worth dumping.
        let latestIsA: Bool
        if validA == false, validB != false {
            latestIsA = false
        } else if validB == false, validA != false {
            latestIsA = true
        } else {
            latestIsA = slotA.header.counter >= slotB.header.counter  // ties favour A
        }
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
            slotA: .init(counter: slotA.header.counter, magic: slotA.header.magic, checksumValid: validA),
            slotB: .init(counter: slotB.header.counter, magic: slotB.header.magic, checksumValid: validB)
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
    /// one), returning the plaintext bytes ready for `XDSaveSlot` plus
    /// whether the body checksum validated (`nil` when the input was
    /// already plaintext, so there was nothing to check).
    private static func decryptedPlaintext(
        of slotBytes: GoDData,
        decrypted: Bool,
        checksumOffset: Int?,
        logger: Logger?,
        slot: String
    ) throws -> (GoDData, Bool?) {
        if decrypted { return (slotBytes, nil) }
        let copy = GoDData(byteStream: slotBytes.rawBytes, byteOrder: .big)
        // `nil` means the engine declares no checksum for this format,
        // so there was nothing to check — distinct from a check that
        // failed.
        let ok = try XDSaveCipher.decrypt(slot: copy, checksumOffset: checksumOffset)
        if ok == false {
            logger?.log(.warning("XD slot \(slot): running-sum tags did not match after decrypt — the slot is blank or corrupt"))
        } else if ok == nil {
            logger?.log(.info("XD slot \(slot): the engine declares no checksum offset, so the slot was not validated"))
        }
        return (copy, ok)
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

        // The header region is real save data — the cipher seed, the
        // checksum tags and the sub-block tables — so it is dumped as
        // its own editable artifact. JSON through the engine's struct
        // when that tiles it exactly, otherwise raw bytes; either way
        // the build reads it back from there and never touches
        // raw-slot.
        let headerRegion = slot.raw.read(atAddress: 0, length: UInt(slot.layout.subBlockBaseOffset)) ?? slot.raw
        let headerFile = try emitSlotHeader(
            headerRegion,
            structName: slotHeaderStructName,
            slotFolder: slotFolder,
            engine: xdEngine,
            fileSystem: fileSystem,
            overwrite: overwrite,
            logger: logger
        )

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
                // Report what was actually written. A `.struct`/`.table`
                // section that failed to tile and fell back to a `.bin` is
                // a binary section on disk, and saying otherwise made the
                // manifest contradict its own file list. `structType` is
                // kept either way — it still names the struct this section
                // *would* use, which is what a region fix needs to know.
                type: jsonFilename == nil ? .binary : spec.type,
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
            headerRegionFile: headerFile,
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
                logger?.log(.warning("Save section '\(spec.name)': no struct binding (engine.sectionStructTypes missing or struct '\(structTypeName ?? "<nil>")' unregistered) — dumping .bin, so this section is not editable"))
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
                logger?.log(.warning("Save section '\(spec.name)': struct '\(typeName)' is \(definition.length) bytes but the section is \(bytes.length) — dumping .bin, so this section is not editable. A region whose layout differs needs its own struct bound in the engine's sectionStructTypes."))
                return nil
            }
            let parsed = StructData(definition: definition, data: bytes)
            let filename = "\(stem).json"
            try fileSystem.encodeJSON(parsed, to: slotFolder.file(filename), overwrite: overwrite)
            return filename

        case .table:
            guard let typeName = structTypeName,
                  let definition = try? engine.getStruct(typeName) as StructDefinition else {
                logger?.log(.warning("Save section '\(spec.name)': no struct binding (engine.sectionStructTypes missing or struct '\(structTypeName ?? "<nil>")' unregistered) — dumping .bin, so this section is not editable"))
                return nil
            }
            let entrySize = definition.length
            guard entrySize > 0 else { return nil }
            let count = spec.count ?? (bytes.length / entrySize)
            // Exact tiling only — the row run must cover the whole
            // section so rebuild reproduces it byte-for-byte.
            guard count > 0, count * entrySize == bytes.length else {
                logger?.log(.warning("Save section '\(spec.name)': table \(count) × \(entrySize) != section \(bytes.length) bytes — dumping .bin, so this section is not editable. A region whose entry size differs needs its own struct bound in the engine's sectionStructTypes."))
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
