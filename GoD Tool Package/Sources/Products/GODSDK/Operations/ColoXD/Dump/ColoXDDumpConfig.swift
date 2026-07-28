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
            case dumpMessages(
                messagesFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                variant: String        // "xd" or "colo"
            )
            case dumpMessage(
                msgFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                variant: String        // "xd" or "colo"
            )
            case dumpATXs(
                atxFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpATX(
                atxFile: File,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpAudios(
                audioFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpAudio(
                ishFile: File,
                isdFile: File,
                outputFolder: Folder,
                overwrite: Bool
            )
            case dumpColoScripts(
                scriptsFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                language: ColoScriptLanguage,
                gameEngine: Folder
            )
            case dumpColoScript(
                scdFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                language: ColoScriptLanguage,
                gameEngine: Folder
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
