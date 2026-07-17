import GoDFoundation

enum RelAssembly {
    struct Config: Codable {
        /// Folder containing the disassembly artifacts. Must hold a
        /// `<relName>.rel.json` — the canonical semantic REL model.
        /// Human-edited `.s` and chunk sidecars are ignored by the
        /// first iteration (parse-from-assembly is a follow-up).
        let inputFolder: Folder
        /// Stem used to locate `<relName>.rel.json` inside `inputFolder`.
        let relName: String
        /// Where to write the assembled `.rel` bytes.
        let outputPath: File
        /// Overwrite an existing file at `outputPath`. Default `true`.
        let overwrite: Bool

        init(
            inputFolder: Folder,
            relName: String,
            outputPath: File,
            overwrite: Bool = true
        ) {
            self.inputFolder = inputFolder
            self.relName = relName
            self.outputPath = outputPath
            self.overwrite = overwrite
        }
    }
}
