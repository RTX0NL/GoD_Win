import GoDFoundation

extension ColoXD {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case buildColosseum(
                fstRegistry: File,
                outputFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                geniusSonorityEngine: Folder
            )
            case buildXD(
                fstRegistry: File,
                outputFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                geniusSonorityEngine: Folder
            )
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
