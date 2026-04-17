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
            case dumpFonts(
                fontsFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpFlashMenus(
                flashMenusFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpFlashMenu(
                gswFile: File,
                outputFolder: Folder,
                overwrite: Bool
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
