import Foundation
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

        let saveMeta: XDSaveOps.SaveMetadata =
            try fileSystem.decodeJSON(from: inputFolder.file(saveMetadataFilename))
        let slotFolder = inputFolder.folder(latestSlotFolderName)
        let slotMeta: XDSaveOps.SlotMetadata =
            try fileSystem.decodeJSON(from: slotFolder.file(slotMetadataFilename))

        // Decode the captured 0xA8 header region — carries the cipher
        // seed, the sub-block TOC, and the size fields.
        guard let headerData = Data(base64Encoded: slotMeta.headerRegion) else {
            throw XDSaveOpsErrors.invalidHeaderRegion(.init())
        }
        let headerRegion = GoDData(byteStream: [UInt8](headerData), byteOrder: .big)

        // Rebuild every sub-block from its artifact (JSON when it exists,
        // else the raw `.bin`), hard-checking each against the size the
        // dump recorded. Nothing about the sub-block bytes is inherited
        // from a raw slot — this is a from-scratch rebuild.
        var sections: [Int: GoDData] = [:]
        for entry in slotMeta.sections {
            let bytes = try reconstructSection(
                entry: entry,
                slotFolder: slotFolder,
                engine: xdEngine,
                fileSystem: fileSystem
            )
            guard bytes.length == entry.length else {
                throw XDSaveOpsErrors.sectionSizeMismatch(
                    index: entry.index, name: entry.name,
                    expected: entry.length, actual: bytes.length, .init()
                )
            }
            sections[entry.index] = bytes
        }

        // Assemble the plaintext slot from scratch: header region + fresh
        // sub-blocks at their TOC offsets, inter-block gaps and unused
        // tail zeroed (see XDSaveSlot.assembled). Then re-encrypt.
        let layout = xdEngine.data.saveSlotLayout.with(subBlockCount: xdEngine.data.saveSections.count)
        let plaintext = try XDSaveSlot.assembled(headerRegion: headerRegion, sections: sections, layout: layout)
        let slotBytes = try encryptIfNeeded(plaintext, decrypted: decrypted)

        // Replace ONLY the latest physical slot. The other slot's
        // original encrypted bytes remain in the unpacked GCI and pass
        // through to the GCI rebuild untouched.
        let latestFilename = saveMeta.latestSlot == "B"
            ? GCIOps.slotBFilename
            : GCIOps.slotAFilename
        fileSystem.writeFile(slotBytes, at: unpackedFolder.file(latestFilename), overwrite: overwrite)

        logger?.log(.info("XD save build: rebuilt \(slotMeta.sections.count) sub-blocks from scratch (gaps zeroed); wrote latest slot \(saveMeta.latestSlot) → \(latestFilename) (other slot untouched)"))
        logger?.log(.taskStatus(taskName: "Build XD Save", status: .completed(true)))
    }

    /// Rebuilds one section's bytes from its dumped artifact. When the
    /// dump wrote a JSON sidecar (struct/table sections that tile
    /// exactly), that JSON is the source of truth and is re-encoded
    /// through the struct definition; otherwise the raw `.bin` slice
    /// is used verbatim. Padding round-trips through the JSON as uint8
    /// arrays, so struct sections are fully covered.
    private static func reconstructSection(
        entry: XDSaveOps.SlotMetadata.SectionEntry,
        slotFolder: Folder,
        engine: XDEngine,
        fileSystem: FileSystemTree
    ) throws -> GoDData {
        if let jsonName = entry.json {
            let jsonFile = slotFolder.file(jsonName)
            guard let jsonBytes = fileSystem.readFile(at: jsonFile) else {
                throw XDSaveOpsErrors.missingArtifact(file: jsonFile, .init())
            }
            guard let structName = entry.structType,
                  let definition = try? engine.getStruct(structName) as StructDefinition else {
                throw XDSaveOpsErrors.missingStructBinding(index: entry.index, name: entry.name, .init())
            }
            switch entry.type {
            case .struct:
                let parsed = try StructData(definition: definition, json: jsonBytes)
                return GoDData(byteStream: parsed.data.rawBytes, byteOrder: .big)
            case .table:
                // The dump writes a JSON array of struct objects. Decode
                // each element through `StructData(definition:json:)` and
                // concatenate — same entry point as the `.struct` path.
                let root = try JSONSerialization.jsonObject(with: jsonBytes.data)
                guard let elements = root as? [Any] else {
                    throw XDSaveOpsErrors.missingArtifact(file: jsonFile, .init())
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
                throw XDSaveOpsErrors.missingArtifact(file: binFile, .init())
            }
            return binBytes
        }
        throw XDSaveOpsErrors.missingArtifact(file: slotFolder.file(entry.name), .init())
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
