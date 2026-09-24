import GoDFoundation

extension GCIOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            /// Split a `.gci` save into a manifest, its region binaries and
            /// the card's editable banner, icon and comments.
            ///
            /// Outputs in `outputFolder`:
            ///   - `gci-manifest.json` — directory entry, region list and a
            ///     description of the card metadata
            ///   - `<region>.bin`      — one per game-data region; a Pokémon
            ///     XD save gives `slot-a.bin` and `slot-b.bin`, and a save
            ///     with no declared shape gives `data.bin`. The metadata
            ///     region has no file: it is rebuilt from its artifacts
            ///   - `Card/banner.png`, `Card/icon-N.png` — the banner and
            ///     each live icon frame, paletted ones as indexed PNGs so
            ///     they re-encode exactly
            ///
            /// Region names are part of the contract with the per-game save
            /// operations, which read `slot-a.bin` and friends directly.
            /// The slot bins are still encrypted at this stage.
            case dumpGCI(
                gciFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                /// Engine folder declaring this game's save-card shape. When
                /// absent the shape is looked up from the gamecode, and a
                /// game with no declaration gets the derived layout.
                saveEngine: Folder? = nil
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
