import GoDFoundation

extension GCIOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            /// Split a `.gci` save into a manifest + raw region binaries.
            ///
            /// Outputs in `outputFolder`:
            ///   - `<name>.gci.json`      — header manifest (DEntry fields)
            ///   - `banner.bin`           — 0x2000 banner / icon area
            ///   - `header0.bin`          — 0x2000 first card-header sector
            ///   - `header1.bin`          — 0x2000 second card-header sector
            ///   - `slot-a.bin`           — 0x28000 encrypted slot A
            ///   - `slot-b.bin`           — 0x28000 encrypted slot B
            ///
            /// The slot bins are still encrypted at this stage; later
            /// game-specific dump ops decrypt them and emit per-sub-block
            /// JSON.
            case dumpGCI(
                gciFile: File,
                outputFolder: Folder,
                overwrite: Bool
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
