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
            /// Decodes each documented `common.fsys` data table into an
            /// editable header JSON + entry CSV (+ raw extras for byte-exact
            /// rebuild), driven by the PBR engine's table descriptors.
            case dumpCommonTables(
                fstFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                japanese: Bool,
                pbrEngine: Folder,
                geniusSonorityEngine: Folder
            )
        }
        let operations: [OperationConfig<Operations>]
    }
}
