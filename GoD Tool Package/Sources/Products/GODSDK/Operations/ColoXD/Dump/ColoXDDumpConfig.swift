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
//            case decodeXD(fstFolder: Folder, outputFolder: Folder, projectFolder: Folder, overwrite: Bool)
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
