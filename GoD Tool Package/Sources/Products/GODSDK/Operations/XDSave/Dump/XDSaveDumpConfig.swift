import GoDFoundation

extension XDSaveOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            /// Dump a Pokémon XD save to per-slot folders.
            ///
            /// `unpackedFolder` is the folder produced by `gciDump` —
            /// it must contain `slot-a.bin` and `slot-b.bin`. Output
            /// folder receives:
            ///
            ///   Slot 1/
            ///     ├── slot-metadata.json   — plaintext header fields
            ///     ├── raw-slot.bin         — full decrypted slot bytes (or
            ///     │                          encrypted, when `decrypted=false`)
            ///     ├── 00-gamedata.bin      — sub-block bytes (when extractable
            ///     │                          via TOC; only meaningful in the
            ///     │                          decrypted mode)
            ///     └── …other sub-blocks…
            ///   Slot 2/  — same shape
            ///   save-metadata.json         — top-level (counters, gamecode)
            ///
            /// `decrypted: true` means the slot bins are already
            /// plaintext (e.g. produced by an external tool like
            /// `gcitool`). When the additive stream cipher lands, this
            /// will become the default and the parser will decrypt
            /// in-place. Until then `decrypted: false` (the default)
            /// emits only `raw-slot.bin` + plaintext header — the
            /// per-sub-block extraction is skipped because the TOC
            /// itself is encrypted.
            case dumpXDSave(
                unpackedFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                decrypted: Bool,
                xdEngine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
