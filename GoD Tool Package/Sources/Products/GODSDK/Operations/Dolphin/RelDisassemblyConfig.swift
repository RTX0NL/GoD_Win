import GoDFoundation

enum RelDisassembly {
    struct Config: Codable {
        let relPath: File
        let outputFolder: Folder
        let dolphinEngine: Folder
        /// Optional symbol index JSON (maps relocation pointer indices to names)
        let symbolIndexPath: File?
        /// Optional DOL symbol map for cross-module resolution
        let dolSymbolMapPath: File?
        /// Optional type map for typed data section export
        let typeMapPath: File?
        /// Engine folders whose structs resolve the type map's chunk types.
        /// Each should point at an engine folder containing `Structs/*.json`.
        /// Absent = none (type-map chunks fall back to the built-in XD structs).
        let engines: [Folder]?

        init(
            relPath: File,
            outputFolder: Folder,
            dolphinEngine: Folder,
            symbolIndexPath: File? = nil,
            dolSymbolMapPath: File? = nil,
            typeMapPath: File? = nil,
            engines: [Folder]? = nil
        ) {
            self.relPath = relPath
            self.outputFolder = outputFolder
            self.dolphinEngine = dolphinEngine
            self.symbolIndexPath = symbolIndexPath
            self.dolSymbolMapPath = dolSymbolMapPath
            self.typeMapPath = typeMapPath
            self.engines = engines
        }
    }
}
