import GoDFoundation

extension XDSaveOps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            /// Reassemble a Pokémon XD save from the dumped slot folder
            /// back into the latest slot under `unpackedFolder`.
            ///
            /// The rebuild is from scratch: every sub-block comes from its
            /// dumped artifact — the `.json` when the section is typed, the
            /// `.bin` otherwise — and is size-checked against what the dump
            /// recorded. `raw-slot.bin` is never read; it exists only as a
            /// reference for diffing. The slot is reassembled at the offsets
            /// its own header TOC declares, then re-encrypted.
            ///
            /// Only the latest slot is replaced. The other slot's original
            /// encrypted bytes pass through the GCI rebuild untouched.
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
