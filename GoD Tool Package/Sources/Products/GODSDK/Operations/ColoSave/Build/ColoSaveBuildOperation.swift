import GoDFoundation
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
            case let .buildColosseumSave(inputFolder, unpackedFolder, overwrite, decrypted, _):
                // Engine path is plumbed through for future
                // section-JSON-driven repacking.
                try buildColosseumSave(
                    inputFolder: inputFolder,
                    unpackedFolder: unpackedFolder,
                    overwrite: overwrite,
                    decrypted: decrypted,
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
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Build Colo Save", status: .started))

        for i in 0..<ColoSaveCardFile.slotCount {
            let plaintextPath = inputFolder.folder(slotFolderName(i)).file(rawSlotFilename)
            guard let plaintext = fileSystem.readFile(at: plaintextPath) else {
                throw ColoSaveOpsErrors.missingSlot(file: plaintextPath, .init())
            }
            let outBytes: GoDData
            if decrypted {
                // Caller is keeping the data plaintext (e.g. for an
                // external tool to encrypt). Pass through unchanged.
                outBytes = plaintext
            } else {
                let copy = GoDData(byteStream: plaintext.rawBytes, byteOrder: .big)
                try ColoSaveCipher.encrypt(slot: copy)
                outBytes = copy
            }
            fileSystem.writeFile(
                outBytes,
                at: unpackedFolder.file(GCIOps.coloSlotFilename(i)),
                overwrite: overwrite
            )
        }

        logger?.log(.taskStatus(taskName: "Build Colo Save", status: .completed(true)))
    }
}
