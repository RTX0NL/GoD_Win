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
        }
        let operations: [OperationConfig<Operations>]
    }
}
