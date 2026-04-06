import GoDFoundation

extension DolAssembly {
    struct Config: Codable {
        let codeFolder: Folder
        let outputDolPath: File
        let symbolMapPath: File?
        let dolphinEngine: Folder
        /// Optional path to a type map file for typed data section import
        let typeMapPath: File?
        /// Optional path to the BSS entry list file
        let bssEntryListPath: File?

        init(
            codeFolder: Folder,
            outputDolPath: File,
            symbolMapPath: File? = nil,
            dolphinEngine: Folder,
            typeMapPath: File? = nil,
            bssEntryListPath: File? = nil
        ) {
            self.codeFolder = codeFolder
            self.outputDolPath = outputDolPath
            self.symbolMapPath = symbolMapPath
            self.dolphinEngine = dolphinEngine
            self.typeMapPath = typeMapPath
            self.bssEntryListPath = bssEntryListPath
        }
    }
}
