import GoDFoundation

extension ColoSaveOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            /// Dump a Pokémon Colosseum save to per-slot folders.
            ///
            /// Mirrors `xdSaveDump` in shape — emits
            /// `Slot 1/raw-slot.bin`, `Slot 2/raw-slot.bin`, the slot
            /// header, one JSON/CSV/binary artifact per section of the
            /// engine's section layout, per-slot metadata, and a top-level
            /// `save-metadata.json`. `coloSaveBuild` rebuilds each slot
            /// from those sections.
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
