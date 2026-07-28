import GoDFoundation
import Colosseum

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
            /// Dump one asset format's files into editable artifacts.
            ///
            /// Replaces the per-format `dumpX` / `dumpXs` pairs: the format is
            /// a parameter, and `input` covers both a single file and a folder
            /// to walk, which is all those pairs differed by.
            case dumpAssets(
                format: AssetFormat,
                input: AssetPath,
                outputFolder: Folder,
                overwrite: Bool
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
