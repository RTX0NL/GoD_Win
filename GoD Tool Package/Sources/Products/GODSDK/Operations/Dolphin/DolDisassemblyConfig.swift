import GoDFoundation

enum DolDisassembly {
    struct Config: Codable {
        let dolPath: File
        let outputFolder: Folder
        let symbolMapPath: File?
        let dolphinEngine: Folder
        /// Optional path to a type map file for typed data section export
        let typeMapPath: File?
        /// Engine folders whose structs resolve the type map's chunk types.
        /// Each should point at an engine folder containing `Structs/*.json`.
        /// Absent = none (type-map chunks fall back to the built-in XD structs).
        let engines: [Folder]?

        init(
            dolPath: File,
            outputFolder: Folder,
            symbolMapPath: File? = nil,
            dolphinEngine: Folder,
            typeMapPath: File? = nil,
            engines: [Folder]? = nil
        ) {
            self.dolPath = dolPath
            self.outputFolder = outputFolder
            self.symbolMapPath = symbolMapPath
            self.dolphinEngine = dolphinEngine
            self.typeMapPath = typeMapPath
            self.engines = engines
        }
    }
}
