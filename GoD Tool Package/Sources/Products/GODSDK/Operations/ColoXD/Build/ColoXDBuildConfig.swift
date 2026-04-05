import GoDFoundation

extension ColoXD {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case packFSYS(
                registryFile: File,
                outputFile: File,
                sourceFolder: Folder,
                overwrite: Bool,
                geniusSonorityEngine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
