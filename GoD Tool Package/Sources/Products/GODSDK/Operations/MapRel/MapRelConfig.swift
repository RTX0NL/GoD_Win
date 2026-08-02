import GoDFoundation

/// Map REL files (one per game map) carry per-map data tables — entry
/// points, characters, group data — referenced via the same pointer
/// indices across every map *within a game*. Two ops cover the
/// per-file and batch cases. The typemap lives next to the engine,
/// not the operation, since one game = one map layout (with the
/// Colosseum exception split into Type 1 / Type 2 — see below).
///
/// Filtering modes on the batch op:
///   - `.all`              dump every `.rel` in the folder
///   - `.onlyPrefixes`     only files whose name starts with one of these
///   - `.excludePrefixes`  skip files whose name starts with one of these
///   - `.coloType1`        Colo-only: angle-sentinel detection emits
///                          only Type 1 maps (legacy `XGMapRel.swift:35-53`)
///   - `.coloType2`        Colo-only: same detection emits only Type 2 maps
enum MapRelDump {

    enum Filter: Codable, Equatable {
        case all
        case onlyPrefixes([String])
        case excludePrefixes([String])
        case coloType1
        case coloType2
    }

    /// Dump a single `.rel` map file using a caller-supplied typemap.
    struct SingleConfig: Codable {
        let relPath: File
        let outputFolder: Folder
        let overwrite: Bool
        /// Typemap for this map's layout. Caller picks Type 1, Type 2,
        /// or the unified XD typemap based on which flavor of REL this is.
        let typeMapPath: File
        let dolphinEngine: Folder
        let gameEngine: Folder
        /// Engine folders whose structs and enums resolve the typemap's
        /// chunk types, combined in order. Absent = just `gameEngine`.
        let engines: [Folder]?

        init(
            relPath: File,
            outputFolder: Folder,
            overwrite: Bool,
            typeMapPath: File,
            dolphinEngine: Folder,
            gameEngine: Folder,
            engines: [Folder]? = nil
        ) {
            self.relPath = relPath
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.typeMapPath = typeMapPath
            self.dolphinEngine = dolphinEngine
            self.gameEngine = gameEngine
            self.engines = engines
        }
    }

    /// Batch — scan a folder of `.rel` map files and dump matching ones.
    /// Each map's disassembly lands in a per-map subfolder under
    /// `outputFolder` (named after the REL stem, so `B1_1.rel` →
    /// `<outputFolder>/B1_1/`).
    struct BatchConfig: Codable {
        let relsFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool
        let typeMapPath: File
        let dolphinEngine: Folder
        let gameEngine: Folder
        let filter: Filter
        /// Engine folders whose structs and enums resolve the typemap's
        /// chunk types, combined in order. Absent = just `gameEngine`.
        let engines: [Folder]?

        init(
            relsFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool,
            typeMapPath: File,
            dolphinEngine: Folder,
            gameEngine: Folder,
            filter: Filter,
            engines: [Folder]? = nil
        ) {
            self.relsFolder = relsFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.typeMapPath = typeMapPath
            self.dolphinEngine = dolphinEngine
            self.gameEngine = gameEngine
            self.filter = filter
            self.engines = engines
        }
    }
}

enum MapRelBuild {
    /// Build a single map `.rel` from a disassembly folder.
    struct SingleConfig: Codable {
        let inputFolder: Folder
        let relName: String
        let outputPath: File
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

    /// Batch — every per-map subfolder under `inputFolder` produces one
    /// rebuilt `.rel` written into `outputFolder` with the subfolder's
    /// name (so `inputFolder/B1_1/` → `outputFolder/B1_1.rel`).
    struct BatchConfig: Codable {
        let inputFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool

        init(
            inputFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool = true
        ) {
            self.inputFolder = inputFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
        }
    }
}
