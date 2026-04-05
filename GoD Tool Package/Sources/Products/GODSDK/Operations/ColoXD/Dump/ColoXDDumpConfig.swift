import GoDFoundation

extension ColoXD {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            case dumpColosseum(
                fstFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                geniusSonorityEngine: Folder
            )
            case dumpXD(
                fstFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                geniusSonorityEngine: Folder
            )
            case unpackFSYS(
                fsysFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                geniusSonorityEngine: Folder
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
