import GoDFoundation

extension XDSaveOps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            /// Reassemble a Pokémon XD save from per-slot folders back
            /// into `slot-a.bin` and `slot-b.bin` under `unpackedFolder`.
            ///
            /// Today this works by reading each slot's `raw-slot.bin`
            /// verbatim — sub-block edits aren't applied yet because
            /// the TOC repack + header-digest recompute path lands
            /// alongside the stream cipher. When that arrives, this op
            /// will pick up edited `.json` / `.bin` sub-block files
            /// and patch them into the raw slot before re-encrypting.
            case buildXDSave(
                inputFolder: Folder,
                unpackedFolder: Folder,
                overwrite: Bool,
                decrypted: Bool,
                xdEngine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
