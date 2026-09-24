import GoDFoundation

extension SaveSectionsOps {

    struct DumpConfig: Codable {
        let operations: [OperationConfig<Operations>]

        enum Operations: Codable {
            /// Decompose every section the layout describes into typed
            /// artifacts, leaving the section's `.bin` in place.
            ///
            /// Artifacts go into a folder named after the binary's stem
            /// (`08-Flags.bin` → `08-Flags/`), one file per chunk plus one
            /// `gap-<offset>.bin` per unclaimed run, so nothing is lost even
            /// when a layout only describes part of a section.
            case dumpSaveSections(
                slotFolder: Folder,
                overwrite: Bool,
                layout: File,
                engines: [Folder],
                /// The flag descriptor table, needed only by `flags` chunks.
                /// Project setup installs the game's own into its engine
                /// folder and points here.
                flagsTable: File?
            )
        }
    }

    struct BuildConfig: Codable {
        let operations: [OperationConfig<Operations>]

        enum Operations: Codable {
            /// Recompose each described section's `.bin` from the artifacts,
            /// so the save build reads the edits. Runs *before* the save
            /// build, mirroring the dump order.
            case buildSaveSections(
                slotFolder: Folder,
                overwrite: Bool,
                layout: File,
                engines: [Folder],
                flagsTable: File?
            )
        }
    }
}
