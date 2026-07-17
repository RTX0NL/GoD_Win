import GoDFoundation
import Structs
import GoDEngine
import XD

extension XDSaveOps {

    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildXDSave(inputFolder, unpackedFolder, overwrite, decrypted, xdEnginePath):
                let xdEngine = try XDEngine(from: xdEnginePath, in: fileSystem)
                try buildXDSave(
                    inputFolder: inputFolder,
                    unpackedFolder: unpackedFolder,
                    overwrite: overwrite,
                    decrypted: decrypted,
                    xdEngine: xdEngine,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func buildXDSave(
        inputFolder: Folder,
        unpackedFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        xdEngine: XDEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Build XD Save", status: .started))

        let repackedA = try repackedSlotForBuild(
            slotFolder: inputFolder.folder(slot1FolderName),
            engine: xdEngine,
            fileSystem: fileSystem,
            logger: logger
        )
        let repackedB = try repackedSlotForBuild(
            slotFolder: inputFolder.folder(slot2FolderName),
            engine: xdEngine,
            fileSystem: fileSystem,
            logger: logger
        )

        let slotABytes = try encryptIfNeeded(repackedA, decrypted: decrypted)
        let slotBBytes = try encryptIfNeeded(repackedB, decrypted: decrypted)

        fileSystem.writeFile(
            slotABytes,
            at: unpackedFolder.file(GCIOps.slotAFilename),
            overwrite: overwrite
        )
        fileSystem.writeFile(
            slotBBytes,
            at: unpackedFolder.file(GCIOps.slotBFilename),
            overwrite: overwrite
        )

        logger?.log(.taskStatus(taskName: "Build XD Save", status: .completed(true)))
    }

    /// Reads `raw-slot.bin` as the canonical edit form, then for any
    /// section that has an edited `<idx>-<name>.json` sidecar runs
    /// it through `StructData(definition:json:)` to re-derive the
    /// section's bytes. The collected overrides flow into
    /// `XDSaveSlot.repacked(sectionOverrides:)` which preserves the
    /// load-time placement order while recomputing offsets from the
    /// (possibly-changed) section sizes. With no JSON edits the
    /// repack is a no-op and the output is byte-identical to
    /// `raw-slot.bin`.
    private static func repackedSlotForBuild(
        slotFolder: Folder,
        engine: XDEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> GoDData {
        let rawPath = slotFolder.file(rawSlotFilename)
        guard let raw = fileSystem.readFile(at: rawPath) else {
            throw XDSaveOpsErrors.missingSlot(file: rawPath, .init())
        }
        let slot = try XDSaveSlot(raw: raw)

        // Walk the engine's section list — for each index whose
        // section has a JSON sidecar on disk *and* the engine binds
        // a struct for it, decode the JSON into bytes and capture
        // as an override. Indices without JSON, or with `.binary`
        // type, fall through to whatever's already in raw-slot.bin.
        var overrides: [Int: GoDData] = [:]
        for index in 0..<XDSaveSlot.subBlockCount {
            guard index < engine.data.saveSections.count else { continue }
            let spec = engine.data.saveSections[index]
            guard spec.type != .binary else { continue }
            guard let structName = engine.data.sectionStructTypes[index] else { continue }

            let stem = String(format: "%02d-%@", index, spec.name)
            let jsonPath = slotFolder.file("\(stem).json")
            guard let jsonBytes = fileSystem.readFile(at: jsonPath) else { continue }

            do {
                let definition = try engine.getStruct(structName) as StructDefinition
                let parsed = try StructData(definition: definition, json: jsonBytes)
                // The struct may describe only the known prefix of
                // a section that's actually longer (XDSaveConfig is
                // 0x70 bytes; the on-card Config section can be
                // 0x88). Preserve the trailing bytes by copying
                // them from raw-slot.bin so unknown fields don't
                // get truncated and shift later sections. When the
                // struct length matches the section, the trailing
                // copy is a no-op.
                let originalSize = slot.subBlockSize(at: index)
                let structBytes = parsed.data
                let merged = GoDData(byteStream: structBytes.rawBytes, byteOrder: .big)
                if merged.length < originalSize,
                   let originalSection = slot.subBlockBytes(at: index),
                   merged.length < originalSection.length,
                   let trailing = originalSection.read(
                        atAddress: UInt(merged.length),
                        length: UInt(originalSection.length - merged.length)) {
                    merged.append(trailing)
                }
                overrides[index] = merged
                let reason = merged.length == structBytes.length
                    ? "matched struct length \(structBytes.length)"
                    : "padded struct \(structBytes.length) → section \(merged.length) with trailing raw bytes"
                logger?.log(.info("XD save build: section \(index) '\(spec.name)' from JSON (\(reason))"))
            } catch {
                logger?.log(.info("XD save build: section \(index) '\(spec.name)' JSON decode failed (\(error)) — keeping raw-slot bytes"))
            }
        }

        return try slot.repacked(sectionOverrides: overrides)
    }

    private static func encryptIfNeeded(_ plaintext: GoDData, decrypted: Bool) throws -> GoDData {
        if decrypted {
            return plaintext
        }
        let copy = GoDData(byteStream: plaintext.rawBytes, byteOrder: .big)
        try XDSaveCipher.encrypt(slot: copy)
        return copy
    }
}
