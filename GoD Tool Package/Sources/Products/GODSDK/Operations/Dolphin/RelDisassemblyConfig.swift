import GoDFoundation

enum RelDisassembly {
    struct Config: Codable {
        /// Path to the .rel file
        let relPath: File
        /// Where to write disassembled output
        let outputFolder: Folder
        /// Dolphin engine folder
        let dolphinEngine: Folder
        /// Optional symbol index JSON (maps relocation pointer indices to names)
        let symbolIndexPath: File?
        /// Optional DOL symbol map for cross-module resolution
        let dolSymbolMapPath: File?
        /// Optional type map for typed data section export
        let typeMapPath: File?

        init(
            relPath: File,
            outputFolder: Folder,
            dolphinEngine: Folder,
            symbolIndexPath: File? = nil,
            dolSymbolMapPath: File? = nil,
            typeMapPath: File? = nil
        ) {
            self.relPath = relPath
            self.outputFolder = outputFolder
            self.dolphinEngine = dolphinEngine
            self.symbolIndexPath = symbolIndexPath
            self.dolSymbolMapPath = dolSymbolMapPath
            self.typeMapPath = typeMapPath
        }
    }
}
