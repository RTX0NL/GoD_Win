import GoDFoundation

extension ColoSaveOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            /// Dump a Pokémon Colosseum save to per-slot folders.
            ///
            /// Mirrors `xdSaveDump` in shape — emits
            /// `Slot 1/raw-slot.bin`, `Slot 2/raw-slot.bin`,
            /// per-slot metadata, and a top-level `save-metadata.json`.
            /// Sub-block extraction is not implemented yet (see
            /// `Documentation/File Formats/Colosseum/Colosseum Save File.md`),
            /// so the per-sub-block bins from the XD op aren't produced.
            case dumpColosseumSave(
                unpackedFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                decrypted: Bool,
                colosseumEngine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
