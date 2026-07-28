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
            case buildGSfsysTOC(
                fstRegistry: File,
                outputFile: File,
                overwrite: Bool,
                geniusSonorityEngine: Folder
            )
            case buildFST(
                contentsFolder: Folder,
                outputFile: File,
                overwrite: Bool,
                dolphinEngine: Folder
            )
            case packFSYS(
                registryFile: File,
                outputFile: File,
                sourceFolder: Folder,
                overwrite: Bool,
                geniusSonorityEngine: Folder
            )
            /// Rebuild one asset format's binaries from its artifacts.
            /// The counterpart to `dumpAssets`; see it for why the format is a
            /// parameter rather than a case per format.
            case buildAssets(
                format: AssetFormat,
                input: AssetPath,
                outputFolder: Folder,
                overwrite: Bool
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
