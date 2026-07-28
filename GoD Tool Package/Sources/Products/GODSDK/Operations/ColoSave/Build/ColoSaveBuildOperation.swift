import Foundation
import GoDFoundation
import Structs
import GoDEngine
import Colosseum

extension ColoSaveOps {

    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildColosseumSave(inputFolder, unpackedFolder, overwrite, decrypted, enginePath):
                let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
                try buildColosseumSave(
                    inputFolder: inputFolder,
                    unpackedFolder: unpackedFolder,
                    overwrite: overwrite,
                    decrypted: decrypted,
                    engine: engine,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func buildColosseumSave(
        inputFolder: Folder,
        unpackedFolder: Folder,
        overwrite: Bool,
        decrypted: Bool,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Build Colo Save", status: .started))

        let saveMeta: ColoSaveOps.SaveMetadata =
            try fileSystem.decodeJSON(from: inputFolder.file(saveMetadataFilename))
        guard let latestIndex = saveMeta.latestSlotIndex else {
            throw ColoSaveOpsErrors.noLatestSlot(.init())
        }
        let slotFolder = inputFolder.folder(latestSlotFolderName)
        let slotMeta: ColoSaveOps.SlotMetadata =
            try fileSystem.decodeJSON(from: slotFolder.file(slotMetadataFilename))

        // Decode the captured header region (magic + counter).
        guard let headerData = Data(base64Encoded: slotMeta.headerRegion) else {
            throw ColoSaveOpsErrors.invalidHeaderRegion(.init())
        }
        let headerRegion = GoDData(byteStream: [UInt8](headerData), byteOrder: .big)

        // Reconstruct every section from its artifact (JSON when it
        // exists, else the raw `.bin`), hard-checking each against the
        // size the dump recorded. Nothing is inherited from a raw slot.
        var placements: [(offset: Int, bytes: GoDData)] = []
        for entry in slotMeta.sections {
            let bytes = try reconstructSection(
                entry: entry,
                slotFolder: slotFolder,
                engine: engine,
                fileSystem: fileSystem
            )
            guard bytes.length == entry.length else {
                throw ColoSaveOpsErrors.sectionSizeMismatch(
                    index: entry.index, name: entry.name,
                    expected: entry.length, actual: bytes.length, .init()
                )
            }
            placements.append((offset: entry.offset, bytes: bytes))
        }

        // Assemble the plaintext slot from scratch, then re-encrypt
        // (setChecksums regenerates the header checksum + body SHA-1).
        let plaintext = try ColosseumSaveSlot.assembled(headerRegion: headerRegion, placements: placements)
        let slotBytes: GoDData
        if decrypted {
            slotBytes = plaintext
        } else {
            let copy = GoDData(byteStream: plaintext.rawBytes, byteOrder: .big)
            try ColoSaveCipher.encrypt(slot: copy)
            slotBytes = copy
        }

        // Replace ONLY the latest slot. The other two slots' original
        // encrypted bytes remain in the unpacked GCI and pass through
        // to the GCI rebuild untouched.
        try fileSystem.writeFile(
            slotBytes,
            at: unpackedFolder.file(GCIOps.coloSlotFilename(latestIndex)),
            overwrite: overwrite
        )

        logger?.log(.info("Colo save build: rebuilt \(placements.count) sections from scratch; wrote latest slot \(latestIndex + 1) (other slots untouched)"))
        logger?.log(.taskStatus(taskName: "Build Colo Save", status: .completed(true)))
    }

    /// Rebuilds one section's bytes from its dumped artifact — JSON
    /// (re-encoded through the struct definition) when present, else the
    /// raw `.bin` slice verbatim.
    private static func reconstructSection(
        entry: ColoSaveOps.SlotMetadata.SectionEntry,
        slotFolder: Folder,
        engine: ColosseumEngine,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        if let jsonName = entry.json {
            let jsonFile = slotFolder.file(jsonName)
            guard let jsonBytes = fileSystem.readFile(at: jsonFile) else {
                throw ColoSaveOpsErrors.missingArtifact(file: jsonFile, .init())
            }
            guard let structName = entry.structType,
                  let definition = try? engine.getStruct(structName) as StructDefinition else {
                throw ColoSaveOpsErrors.missingStructBinding(index: entry.index, name: entry.name, .init())
            }
            switch entry.type {
            case .struct:
                let parsed = try StructData(definition: definition, json: jsonBytes)
                return GoDData(byteStream: parsed.data.rawBytes, byteOrder: .big)
            case .table:
                let root = try JSONSerialization.jsonObject(with: jsonBytes.data)
                guard let elements = root as? [Any] else {
                    throw ColoSaveOpsErrors.missingArtifact(file: jsonFile, .init())
                }
                var out: [UInt8] = []
                for element in elements {
                    let elementData = try JSONSerialization.data(withJSONObject: element)
                    let parsed = try StructData(
                        definition: definition,
                        json: GoDData(byteStream: [UInt8](elementData), byteOrder: .big)
                    )
                    out.append(contentsOf: parsed.data.rawBytes)
                }
                return GoDData(byteStream: out, byteOrder: .big)
            case .binary:
                break   // .binary sections never carry JSON — fall to .bin
            }
        }
        if let binName = entry.bin {
            let binFile = slotFolder.file(binName)
            guard let binBytes = fileSystem.readFile(at: binFile) else {
                throw ColoSaveOpsErrors.missingArtifact(file: binFile, .init())
            }
            return binBytes
        }
        throw ColoSaveOpsErrors.missingArtifact(file: slotFolder.file(entry.name), .init())
    }
}
