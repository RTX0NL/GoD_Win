import GoDFoundation

enum RelAssembly {
    struct Config: Codable {
        /// Folder containing the disassembly artifacts: the `<relName>.rel.json`
        /// manifest and every `.s`, `.bin`, `.csv` and embedded-file chunk it
        /// points at. All of them are read — the manifest carries no bytes.
        let inputFolder: Folder
        /// Stem used to locate `<relName>.rel.json` inside `inputFolder`.
        let relName: String
        /// Where to write the assembled `.rel` bytes.
        let outputPath: File
        /// Overwrite an existing file at `outputPath`. Default `true`.
        let overwrite: Bool
        /// Engine folders whose structs resolve the manifest's table and
        /// struct chunk types, game definitions first. Needed only when the
        /// disassembly was typed; absent = none.
        let engines: [Folder]?

        init(
            inputFolder: Folder,
            relName: String,
            outputPath: File,
            overwrite: Bool = true,
            engines: [Folder]? = nil
        ) {
            self.inputFolder = inputFolder
            self.relName = relName
            self.outputPath = outputPath
            self.overwrite = overwrite
            self.engines = engines
        }
    }
}
