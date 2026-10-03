import GoDFoundation

/// Dedicated dump/build operations for `common.rel` — the shared
/// game-data REL shipped by Colosseum and XD. The configs are thin:
/// they point at the REL file, the project's game engine folder
/// (Colosseum or XD), and the Dolphin engine folder. Typemap and
/// symbol-map paths are read from the game engine's `Data.Resources`
/// at run time so the user only specifies them once (in the engine
/// folder), not per-operation.
enum CommonRelDump {
    struct Config: Codable {
        /// Path to the extracted `common.rel`. The default project
        /// setup routes this to `Unpacked/Assets/Data/Common/common.rel`.
        let relPath: File
        let outputFolder: Folder
        let overwrite: Bool
        /// Folder of the project's Dolphin engine (used for cross-module
        /// symbol resolution against the DOL).
        let dolphinEngine: Folder
        /// Folder of the project's game engine — XD or Colosseum.
        /// Read for `commonRelSymbolMap`, `commonRelTypeMap`, and
        /// `dolSymbolMap` paths via `Data.Resources`.
        let gameEngine: Folder
        /// Engine folders whose structs and enums resolve the typemap's
        /// chunk types, combined in order (game definitions first, then the
        /// shared sets they reference). Absent = just `gameEngine`, which
        /// resolves its own structs but not, say, a Pokemon enum they name.
        let engines: [Folder]?

        init(
            relPath: File,
            outputFolder: Folder,
            overwrite: Bool,
            dolphinEngine: Folder,
            gameEngine: Folder,
            engines: [Folder]? = nil
        ) {
            self.relPath = relPath
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.dolphinEngine = dolphinEngine
            self.gameEngine = gameEngine
            self.engines = engines
        }
    }
}

enum CommonRelBuild {
    struct Config: Codable {
        /// Folder containing the disassembly artifacts: the `<relName>.rel.json`
        /// manifest and the chunk files it points at.
        let inputFolder: Folder
        /// Stem used to locate `<relName>.rel.json` inside `inputFolder`.
        /// Defaults to `"common"` when omitted via the convenience init.
        let relName: String
        let outputPath: File
        let overwrite: Bool
        /// Engine folders whose structs resolve the disassembly's typed
        /// table chunks, game definitions first — the same list the dump
        /// used. Absent = none, which is only enough for an untyped dump.
        let engines: [Folder]?

        init(
            inputFolder: Folder,
            relName: String = "common",
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
