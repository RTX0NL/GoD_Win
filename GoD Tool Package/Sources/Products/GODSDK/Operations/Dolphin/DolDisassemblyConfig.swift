import GoDFoundation

enum DolDisassembly {
    struct Config: Codable {
        let dolPath: File
        let outputFolder: Folder
        let symbolMapPath: File?
        let dolphinEngine: Folder
        /// Optional path to a type map file for typed data section export
        let typeMapPath: File?

        init(
            dolPath: File,
            outputFolder: Folder,
            symbolMapPath: File? = nil,
            dolphinEngine: Folder,
            typeMapPath: File? = nil
        ) {
            self.dolPath = dolPath
            self.outputFolder = outputFolder
            self.symbolMapPath = symbolMapPath
            self.dolphinEngine = dolphinEngine
            self.typeMapPath = typeMapPath
        }
    }
}
