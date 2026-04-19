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
            case buildFont(
                metadataFile: File,
                outputFile: File,
                overwrite: Bool
            )
            case buildFonts(
                fontsFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case buildFlashMenus(
                projectsFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case buildFlashMenu(
                metadataFile: File,
                outputFile: File,
                overwrite: Bool
            )
            case buildMessages(
                jsonFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case buildMessage(
                jsonFile: File,
                outputFile: File,
                overwrite: Bool
            )
            case buildATXs(
                projectsFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case buildATX(
                projectFolder: Folder,
                outputFile: File,
                overwrite: Bool
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
