import GoDFoundation

extension PBROps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            case dumpPBR(
                fstFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                geniusSonorityEngine: Folder
            )
            /// Types the raw `common.fsys` data-table entries in an already
            /// unpacked project into editable header JSON + row CSV, folding
            /// the reassembly metadata into each entry of the archive's
            /// `common.fsys.json` registry. Runs after `dumpPBR`.
            case dumpCommonTables(
                unpackedFolder: Folder,
                overwrite: Bool,
                japanese: Bool,
                pbrEngine: Folder,
                /// Extra engine folders the entry structs resolve against,
                /// combined with `pbrEngine` in order. A table entry naming a
                /// species/move/item enum needs the Pokemon engine here —
                /// `getStruct` only consults one engine's own enums.
                engines: [Folder]? = nil
            )
        }
        let operations: [OperationConfig<Operations>]
    }
}
