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
    ///   /Settings/Settings.json
    ///   /Config/Save-Dump-Config.json
    ///   /Config/Save-Build-Config.json
    ///
    /// The slot-level dump (decryption + sub-block JSON under
    /// `/Source/Save/Slot 1` etc.) is added by the per-game ops in a
    /// later pass; the configs generated here just chain the GCI
    /// envelope dump/build for now.
    static func setup(gci gciInputFile: File) throws {
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

        guard let raw = fileSystem.readFile(at: gciInputFile) else {
            throw ProjectSetupErrors.gciNotFound(gciInputFile, .init())
        }

        let parsed = try GCIFile(data: raw, name: gciInputFile.fileName.withoutExtensions)

        let gamecode = parsed.header.gamecode
        let gamecodePrefix = String(gamecode.prefix(3))
        let isXD = gamecodePrefix == "GXX"
        let isColosseum = gamecodePrefix == "GC6"
        guard isXD || isColosseum else {
            throw ProjectSetupErrors.unrecognisedGCIGamecode(gamecode, .init())
        }

        // Mirror the GCI input into the project under its original name.
        // The rebuild target writes to a `<stem>_rebuilt.<ext>` sibling
        // so the original mirror stays intact and a user can diff the
        // two files to validate cipher / packing correctness.
        let gciOutputFile = saveFolder.file(gciInputFile.fileName)
        projectFileSystem.writeFile(raw, at: gciOutputFile, overwrite: false)

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
        engines.append(try PokemonEngine.defaults())

        engines.forEach { engine in
            engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }

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
            // Per-slot folder structure under /Source/Save. The
            // cipher decrypts incoming slots so the user can edit
            // raw-slot.bin directly; build re-encrypts before the
            // gciBuild step runs. Sub-block .bin edits don't survive
            // the build path yet (TOC repack TBD) — only edits to
            // raw-slot.bin do.
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
            // Cipher is wired (PKHeX-aligned SHA-1 XOR cascade);
            // ops enabled by default. Sub-block JSON build doesn't
            // round-trip yet (raw-slot.bin is the source of truth).
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
        fileSystem.createFolder(at: projectFolder, overwrite: false)
        fileSystem.importFST(projectFileSystem, from: Folder("/"), to: projectFolder, overwrite: false)

        if let executablePath = Bundle.main.executablePath {
            [dumpConfigFile, buildConfigFile].forEach { config in
                let script =
                """
                #!/bin/zsh
                \(executablePath.replacingOccurrences(of: " ", with: "\\ ")) \(Folder("..").file(config.path).path.replacingOccurrences(of: " ", with: "\\ "))
                """
                let file = projectFolder.folder("Scripts").file(config.fileName.replacingOccurrences(of: "-Config.json", with: ".sh"))
                fileSystem.writeFile(script.data(format: .utf8), at: file, overwrite: false)
                fileSystem.setExecutable(file: file)
            }
        }
    }
}
