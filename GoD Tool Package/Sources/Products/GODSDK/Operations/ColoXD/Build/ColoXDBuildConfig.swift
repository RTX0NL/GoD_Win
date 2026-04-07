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
            case buildFont(
                metadataFile: File,
                atlasFile: File,
                outputFile: File,
                overwrite: Bool
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
