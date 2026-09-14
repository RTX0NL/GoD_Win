import GoDFoundation
import GoDEngine
import Dolphin
import GameCube
import GeniusSonority
import Colosseum
import XD
import Pokemon

extension Project {

    /// Project skeleton for a GameCube `.gci` save export. Detects the
    /// game from the GCI's gamecode field and lays out a save-editing
    /// project the same way `setup(iso:)` does for ROMs:
    ///
    ///   /Build/Save/<original>.gci
    ///   /Build/Save/Unpacked/   — gci-manifest.json + region bins
    ///                             (banner.bin, header0.bin, header1.bin,
    ///                              slot-a.bin, slot-b.bin)
    ///   /Engines/               — Dolphin + GameCube + GS + game-specific
    ///   /Engines/Version.txt    — the tool version that wrote the project
    ///   /Settings/Settings.json
    ///   /Config/Save-Dump-Config.json
    ///   /Config/Save-Build-Config.json
    ///
    /// The slot-level dump (decryption + sub-block JSON under
    /// `/Source/Save/Latest Slot`) is added by the per-game ops in a
    /// later pass; the configs generated here just chain the GCI
    /// envelope dump/build for now. Only the latest slot is dumped and,
    /// on rebuild, replaced — the other slot(s) pass through unchanged.
    static func setup(gci gciInputFile: File, toolVersion: String) throws {
        let fileSystem = FileSystem.shared
        let projectFileSystem = InMemoryFST()

        let buildFolder = Folder("/Build")
        let saveFolder = buildFolder.folder("/Save")
        let unpackedFolder = saveFolder.folder("/Unpacked")
        let sourceFolder = Folder("/Source")
        let saveSourceFolder = sourceFolder.folder("/Save")
        let configFolder = Folder("/Config")
        let settingsFolder = Folder("/Settings")
        let enginesFolder = Folder("/Engines")

        guard let raw = fileSystem.readFile(at: gciInputFile)?.allData else {
            throw ProjectSetupErrors.gciNotFound(gciInputFile, .init())
        }

        let parsed = try GCIFile(data: raw, name: gciInputFile.fileName.withoutExtensions)

        let gamecode = parsed.header.gamecode
        let gamecodePrefix = String(gamecode.prefix(3))
        let isXD = gamecodePrefix == "GXX"
        let isColosseum = gamecodePrefix == "GC6"
        guard isXD || isColosseum else {
            throw ProjectSetupErrors.unrecognizedGCIGamecode(gamecode, .init())
        }

        // Mirror the GCI input into the project under its original name.
        // The rebuild target writes to a `<stem>_rebuilt.<ext>` sibling
        // so the original mirror stays intact and a user can diff the
        // two files to validate cipher / packing correctness.
        let gciOutputFile = saveFolder.file(gciInputFile.fileName)
        try projectFileSystem.writeFile(raw, at: gciOutputFile, overwrite: false)

        let stem = gciInputFile.fileName.withoutExtensions
        let ext = gciInputFile.fileType ?? "gci"
        let gciRebuildFile = saveFolder.file("\(stem)_rebuilt.\(ext)")

        let settings = GoddessSettings.default
        let settingsFile = settingsFolder.file("Settings.json")
        try projectFileSystem.encodeJSON(settings, to: settingsFile, overwrite: false)

        let dolphinEngine = try DolphinEngine.defaults()
        let gamecubeEngine = try GamecubeEngine.defaults()
        var engines: [any Engine] = [dolphinEngine, gamecubeEngine]

        let gsGame: GSGame = isXD ? .galeOfDarkness : .colosseum
        engines.append(GeniusSonorityEngine.defaultEngine(for: gsGame))

        if isXD {
            engines.append(try XDEngine.defaults())
        } else if isColosseum {
            engines.append(try ColosseumEngine.defaults())
        }
        // Species/move/item ids are per-game, so key the engine to the save's
        // own title rather than shipping one game's numbering to both.
        engines.append(try PokemonEngine.defaultEngine(
            for: PokemonEngine.Game(rawValue: gsGame.rawValue) ?? .galeOfDarkness
        ))

        try engines.forEach { engine in
            try engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }
        try writeVersionStamp(toolVersion, to: projectFileSystem, in: enginesFolder)

        var dumpOperations: [OperationConfig<GoddessConfig.Operations>] = [
            OperationConfig(
                operation: .gciDump(
                    config: GCIOps.DumpConfig(
                        operations: [
                            OperationConfig(
                                operation: .dumpGCI(
                                    gciFile: gciOutputFile.prefixed("."),
                                    outputFolder: unpackedFolder.prefixed("."),
                                    overwrite: false
                                ),
                                enabled: .yes
                            )
                        ]
                    )
                ),
                enabled: .yes
            )
        ]

        var buildOperations: [OperationConfig<GoddessConfig.Operations>] = []

        if isXD {
            let xdEngine = try XDEngine.defaults()
            let xdEngineFolder = enginesFolder.folder(xdEngine.name).prefixed(".")
            // Dumps only the latest slot into /Source/Save/Latest Slot
            // (decrypted, as per-section JSON/.bin). Build reconstructs
            // that slot from scratch from the section artifacts, re-
            // encrypts, and replaces only the latest slot before the
            // gciBuild step; the other slot passes through untouched.
            dumpOperations.append(
                OperationConfig(
                    operation: .xdSaveDump(
                        config: XDSaveOps.DumpConfig(
                            operations: [
                                OperationConfig(
                                    operation: .dumpXDSave(
                                        unpackedFolder: unpackedFolder.prefixed("."),
                                        outputFolder: saveSourceFolder.prefixed("."),
                                        overwrite: false,
                                        decrypted: false,
                                        xdEngine: xdEngineFolder
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            )

            buildOperations.append(
                OperationConfig(
                    operation: .xdSaveBuild(
                        config: XDSaveOps.BuildConfig(
                            operations: [
                                OperationConfig(
                                    operation: .buildXDSave(
                                        inputFolder: saveSourceFolder.prefixed("."),
                                        unpackedFolder: unpackedFolder.prefixed("."),
                                        overwrite: true,
                                        decrypted: false,
                                        xdEngine: xdEngineFolder
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            )
        }

        if isColosseum {
            let coloEngine = try ColosseumEngine.defaults()
            let coloEngineFolder = enginesFolder.folder(coloEngine.name).prefixed(".")
            // Cipher is wired (PKHeX-aligned SHA-1 XOR cascade); ops
            // enabled by default. Dumps only the latest slot; build
            // reconstructs it from scratch from the section artifacts
            // and replaces only that slot, leaving the other two
            // untouched.
            dumpOperations.append(
                OperationConfig(
                    operation: .coloSaveDump(
                        config: ColoSaveOps.DumpConfig(
                            operations: [
                                OperationConfig(
                                    operation: .dumpColosseumSave(
                                        unpackedFolder: unpackedFolder.prefixed("."),
                                        outputFolder: saveSourceFolder.prefixed("."),
                                        overwrite: false,
                                        decrypted: false,
                                        colosseumEngine: coloEngineFolder
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            )

            buildOperations.append(
                OperationConfig(
                    operation: .coloSaveBuild(
                        config: ColoSaveOps.BuildConfig(
                            operations: [
                                OperationConfig(
                                    operation: .buildColosseumSave(
                                        inputFolder: saveSourceFolder.prefixed("."),
                                        unpackedFolder: unpackedFolder.prefixed("."),
                                        overwrite: true,
                                        decrypted: false,
                                        colosseumEngine: coloEngineFolder
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            )
        }

        // gciBuild always runs last — reads the `unpackedFolder`
        // region bins (potentially refreshed by xdSaveBuild) and
        // reassembles the .gci. Writes to `<stem>_rebuilt.gci` so the
        // mirrored original stays untouched.
        buildOperations.append(
            OperationConfig(
                operation: .gciBuild(
                    config: GCIOps.BuildConfig(
                        operations: [
                            OperationConfig(
                                operation: .buildGCI(
                                    inputFolder: unpackedFolder.prefixed("."),
                                    gciFile: gciRebuildFile.prefixed("."),
                                    overwrite: true
                                ),
                                enabled: .yes
                            )
                        ]
                    )
                ),
                enabled: .yes
            )
        )

        let dumpConfig = GoddessConfig(
            name: "Dump Save",
            description: "Split a Pokémon \(isXD ? "XD" : "Colosseum") .gci save into editable region bins",
            settingsFile: settingsFile.prefixed("."),
            rootFolder: "..",
            operations: dumpOperations
        )

        let buildConfig = GoddessConfig(
            name: "Build Save",
            description: "Reassemble a Pokémon \(isXD ? "XD" : "Colosseum") .gci save from region bins",
            settingsFile: settingsFile.prefixed("."),
            rootFolder: "..",
            operations: buildOperations
        )

        let dumpConfigFile = configFolder.file("Save-Dump-Config.json")
        try projectFileSystem.encodeJSON(dumpConfig, to: dumpConfigFile, overwrite: false)
        let buildConfigFile = configFolder.file("Save-Build-Config.json")
        try projectFileSystem.encodeJSON(buildConfig, to: buildConfigFile, overwrite: false)

        let projectFolder = Folder(gciInputFile.path.withoutExtensions + " save project")
        try fileSystem.createFolder(at: projectFolder, overwrite: false)
        try fileSystem.importFST(projectFileSystem, from: Folder("/"), to: projectFolder, overwrite: false)

        try LauncherScript.write(
            for: [dumpConfigFile, buildConfigFile],
            in: projectFolder,
            fileSystem: fileSystem
        )
    }
}
