import GoDFoundation
import GoDEngine
import Dolphin
import GameCube
import Wii
import PBR
import GeniusSonority
import Colosseum
import XD

enum Project {
    static func setup(iso isoInputFile: File) throws {
        let fileSystem = FileSystem.shared
        let projectFileSystem = InMemoryFST()

        let buildFolder = Folder("/Build")
        let isoFolder = buildFolder.folder("/ISO")
        let contentsFolder = buildFolder.folder("/Contents")
        let unpackedFolder = buildFolder.folder("/Unpacked")
        let sourceFolder = Folder("/Source")
        let configFolder = Folder("/Config")
        let settingsFolder = Folder("/Settings")
        let enginesFolder = Folder("/Engines")

        guard let isoData = fileSystem.readFile(at: isoInputFile) else {
            throw ProjectSetupErrors.isoNotFound(isoInputFile, .init())
        }
        isoData.setByteOrder(.big)
        guard let gameID = isoData.readString(atAddress: 0, format: .utf8, maxCharacters: 4) else {
            throw ProjectSetupErrors.invalidGameID(.init())
        }

        // Detect disc type
        let wiiMagic: UInt32 = isoData.readSafely(atAddress: 0x18)
        let isWii = wiiMagic == 0x5D1C9EA3

        let isColosseum = PokemonColosseum.gameIDs.contains(gameID)
        let isXD = PokemonXD.gameIDs.contains(gameID)
        let isPBR = PokemonBattleRevolution.gameIDs.contains(gameID)
        let isGeniusSonority = isColosseum || isXD || isPBR

        // Folders are created on-demand when files are written into them,
        // so we don't precreate empty directories here. Operations and
        // writeFile calls will create whatever they need.

        let isoOutputFile = isoFolder.file(isoInputFile.fileName)
        projectFileSystem.writeFile(isoData, at: isoOutputFile, overwrite: false)

        var settings = GoddessSettings.default
        if isWii {
            settings.wiiCommonKeyFile = "../wii-common-key.txt"
        }
        
        let settingsFile = settingsFolder.file("Settings.json")
        try projectFileSystem.encodeJSON(settings, to: settingsFile, overwrite: false)

        let dolphinEngine = try DolphinEngine.defaults()

        var engines: [any Engine] = [dolphinEngine]

        // Game-specific engine setup
        var gsGame: GSGame?
        if isColosseum {
            gsGame = .colosseum
        } else if isXD {
            gsGame = .galeOfDarkness
        } else if isPBR {
            gsGame = .battleRevolution
        }

        if isWii {
            let wiiEngine = try WiiEngine.defaults()
            engines.append(wiiEngine)

            if isGeniusSonority, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                engines.append(gsEngine)
            }
        } else {
            // GameCube disc
            let gamecubeEngine = try GamecubeEngine.defaults()
            engines.append(gamecubeEngine)

            if isGeniusSonority, let game = gsGame {
                var gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                let gsfsysFile = gsEngine.data.fsys.GSfsysFile

                let isoFileSystem = try? GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
                if let tocData = isoFileSystem?.readFile(at: gsfsysFile),
                   let toc = try? FsysTOC(tocData: tocData, engine: gsEngine) {
                    gsEngine = try GeniusSonorityEngine(data: gsEngine.data, enums: gsEngine.enums, structs: gsEngine.structs, toc: toc)
                }
                engines.append(gsEngine)
            }
        }

        // Game-specific struct engine
        if isXD {
            engines.append(try XDEngine.defaults())
        } else if isColosseum {
            engines.append(try ColosseumEngine.defaults())
        }

        engines.forEach { engine in
            engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }

        // Write bundled symbol map for XD games
        if isXD, let symbolMapData = PokemonXD.symbolMapData(for: gameID) {
            let symbolMapFile = enginesFolder.folder(dolphinEngine.name).file(gameID + ".map")
            projectFileSystem.writeFile(symbolMapData, at: symbolMapFile, overwrite: false)
        }

        // Build config generation
        let buildConfig: GoddessConfig
        let dumpConfig: GoddessConfig

        if isWii {
            let wiiEngineName = "Wii Engine"

            buildConfig = GoddessConfig(
                name: "Build ISO",
                description: "Config for encrypting and building Wii ISO from Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: [
                    OperationConfig(
                        operation: .wiiBuild(
                            config: WiiOps.BuildConfig(
                                operations: [
                                    OperationConfig(
                                        operation: .encryptISO(
                                            fstPath: contentsFolder.prefixed("."),
                                            isoPath: isoOutputFile.prefixed("."),
                                            overwrite: true,
                                            wiiEngine: enginesFolder.folder(wiiEngineName).prefixed("."),
                                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                                        ),
                                        enabled: .yes
                                    ),
                                    OperationConfig(
                                        operation: .fillISO(
                                            isoPath: isoOutputFile.prefixed("."),
                                            size: 0x118240000
                                        ),
                                        enabled: .yes
                                    )
                                ]
                            )
                        ),
                        enabled: .yes
                    )
                ]
            )

            var dumpOperations: [OperationConfig<GoddessConfig.Operations>] = [
                OperationConfig(
                    operation: .wiiDump(
                        config: WiiOps.DumpConfig(
                            operations: [
                                OperationConfig(
                                    operation: .decryptISO(
                                        isoPath: isoOutputFile.prefixed("."),
                                        outputFolder: contentsFolder.prefixed("."),
                                        overwrite: false,
                                        wiiEngine: enginesFolder.folder(wiiEngineName).prefixed("."),
                                        dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            ]

            if isPBR, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                dumpOperations.append(
                    OperationConfig(
                        operation: .pbrDump(
                            config: PBROps.DumpConfig(
                                operations: [
                                    OperationConfig(
                                        operation: .dumpPBR(
                                            fstFolder: contentsFolder.prefixed("."),
                                            outputFolder: unpackedFolder.prefixed("."),
                                            overwrite: false,
                                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                            geniusSonorityEngine: enginesFolder.folder(gsEngine.name).prefixed(".")
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

            // DOL disassembly (Wii DOL format is the same as GameCube)
            dumpOperations.append(
                OperationConfig(
                    operation: .dolDisassembly(
                        config: DolDisassembly.Config(
                            dolPath: contentsFolder.folder("DATA").folder("sys").file("main.dol").prefixed("."),
                            outputFolder: sourceFolder.folder("Code").prefixed("."),
                            symbolMapPath: nil,
                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                        )
                    ),
                    enabled: .yes
                )
            )

            dumpConfig = GoddessConfig(
                name: "Dump ISO",
                description: "Config for decrypting and dumping Wii ISO files to Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: dumpOperations
            )

        } else {
            // GameCube disc — existing logic
            let gamecubeEngine = try GamecubeEngine.defaults()

            var buildOperations: [OperationConfig<GoddessConfig.Operations>] = []

            // FSYS unpack puts raw .gsw files here (per
            // GeniusSonority/Constants/entries/FSYS.swift gsw routing).
            let flashMenusFolder = unpackedFolder.folder("Assets").folder("Flash Menus")
            // Structured per-GSW project folders (metadata.json + textures/) live
            // under /Source so they're treated as editable source assets,
            // separate from the unpacked binary view of the FSYS contents.
            let flashMenusSourceFolder = sourceFolder.folder("Menus")
            // FSYS unpack puts raw .fnt files here.
            let fontsFolder = unpackedFolder.folder("Data").folder("Text").folder("Fonts")
            // Structured per-font project folders (atlas.pgm + metadata.json).
            let fontsSourceFolder = sourceFolder.folder("Text").folder("Fonts")
            // FSYS unpack puts raw .msg files under /Unpacked/Data/Text/Messages.
            let messagesFolder = unpackedFolder.folder("Data").folder("Text").folder("Messages")
            // Editable per-MSG JSON files.
            let messagesSourceFolder = sourceFolder.folder("Text").folder("Messages")

            if isColosseum, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                buildOperations.append(
                    OperationConfig(operation: .coloXDBuild(
                        config: ColoXD.BuildConfig(
                            operations: [
                                OperationConfig(
                                    operation: .buildFlashMenus(
                                        projectsFolder: flashMenusSourceFolder.prefixed("."),
                                        outputFolder: flashMenusFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildFonts(
                                        fontsFolder: fontsSourceFolder.prefixed("."),
                                        outputFolder: fontsFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildMessages(
                                        jsonFolder: messagesSourceFolder.prefixed("."),
                                        outputFolder: messagesFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildColosseum(
                                        fstRegistry: unpackedFolder.file("FST.json").prefixed("."),
                                        outputFolder: contentsFolder.prefixed("."),
                                        overwrite: true,
                                        dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                        geniusSonorityEngine: enginesFolder.folder(gsEngine.name).prefixed(".")
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

            if isXD, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                buildOperations.append(
                    OperationConfig(operation: .coloXDBuild(
                        config: ColoXD.BuildConfig(
                            operations: [
                                OperationConfig(
                                    operation: .buildFlashMenus(
                                        projectsFolder: flashMenusSourceFolder.prefixed("."),
                                        outputFolder: flashMenusFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildFonts(
                                        fontsFolder: fontsSourceFolder.prefixed("."),
                                        outputFolder: fontsFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildMessages(
                                        jsonFolder: messagesSourceFolder.prefixed("."),
                                        outputFolder: messagesFolder.prefixed("."),
                                        overwrite: true
                                    ),
                                    enabled: .no
                                ),
                                OperationConfig(
                                    operation: .buildXD(
                                        fstRegistry: unpackedFolder.file("FST.json").prefixed("."),
                                        outputFolder: contentsFolder.prefixed("."),
                                        overwrite: true,
                                        dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                        geniusSonorityEngine: enginesFolder.folder(gsEngine.name).prefixed(".")
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

            buildOperations.append(
                OperationConfig(
                    operation: .gamecubeBuild(
                        config: Gamecube.BuildConfig(
                            operations: [
                                OperationConfig(
                                    operation: .buildISO(
                                        fstPath: contentsFolder.prefixed("."),
                                        isoPath: isoOutputFile.prefixed("."),
                                        overwrite: true,
                                        dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                        gamecubeEngine: enginesFolder.folder(gamecubeEngine.name).prefixed(".")
                                    ),
                                    enabled: .yes
                                ),
                                OperationConfig(
                                    operation: .fillISO(
                                        isoPath: isoOutputFile.prefixed("."),
                                        size: gamecubeEngine.data.iso.maxDiscCapacity
                                    ),
                                    enabled: .yes
                                )
                            ]
                        )
                    ),
                    enabled: .yes
                )
            )

            buildConfig = GoddessConfig(
                name: "Build ISO",
                description: "Config for building ISO from Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: buildOperations
            )

            dumpConfig = GoddessConfig(
                name: "Dump ISO",
                description: "Config for dumping ISO files to Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: [
                    OperationConfig(
                        operation: .gamecubeDump(
                            config: Gamecube.DumpConfig(
                                operations: [
                                    OperationConfig(
                                        operation: .unpackISO(
                                            isoPath: isoOutputFile.prefixed("."),
                                            fstFolder: contentsFolder.prefixed("."),
                                            overwrite: false,
                                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                            gamecubeEngine: enginesFolder.folder(gamecubeEngine.name).prefixed(".")
                                        ),
                                        enabled: .yes
                                    )
                                ]
                            )
                        ),
                        enabled: .yes
                    )
                ]
                .conditionalAppend(
                        isColosseum,
                        contents: [
                            OperationConfig(operation: .coloXDDump(
                                config: ColoXD.DumpConfig(
                                    operations: [
                                        OperationConfig(
                                            operation: .dumpColosseum(
                                                fstFolder: contentsFolder.prefixed("."),
                                                outputFolder: unpackedFolder.prefixed("."),
                                                overwrite: false,
                                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                                geniusSonorityEngine: enginesFolder.folder(GeniusSonorityEngine.defaultEngine(for: .colosseum).name).prefixed(".")
                                            ),
                                            enabled: .yes
                                        ),
                                        OperationConfig(
                                            operation: .dumpFlashMenus(
                                                flashMenusFolder: flashMenusFolder.prefixed("."),
                                                outputFolder: flashMenusSourceFolder.prefixed("."),
                                                overwrite: false
                                            ),
                                            enabled: .no
                                        ),
                                        OperationConfig(
                                            operation: .dumpFonts(
                                                fontsFolder: fontsFolder.prefixed("."),
                                                outputFolder: fontsSourceFolder.prefixed("."),
                                                overwrite: false
                                            ),
                                            enabled: .no
                                        ),
                                        OperationConfig(
                                            operation: .dumpMessages(
                                                messagesFolder: messagesFolder.prefixed("."),
                                                outputFolder: messagesSourceFolder.prefixed("."),
                                                overwrite: false,
                                                variant: "colo"
                                            ),
                                            enabled: .no
                                        )
                                    ]
                                )
                            ),
                            enabled: .yes
                            )
                        ]
                    )
                .conditionalAppend(
                        isXD,
                        contents: [
                            OperationConfig(operation: .coloXDDump(
                                config: ColoXD.DumpConfig(
                                    operations: [
                                        OperationConfig(
                                            operation: .dumpXD(
                                                fstFolder: contentsFolder.prefixed("."),
                                                outputFolder: unpackedFolder.prefixed("."),
                                                overwrite: false,
                                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                                geniusSonorityEngine: enginesFolder.folder(GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness).name).prefixed(".")
                                            ),
                                            enabled: .yes
                                        ),
                                        OperationConfig(
                                            operation: .dumpFlashMenus(
                                                flashMenusFolder: flashMenusFolder.prefixed("."),
                                                outputFolder: flashMenusSourceFolder.prefixed("."),
                                                overwrite: false
                                            ),
                                            enabled: .no
                                        ),
                                        OperationConfig(
                                            operation: .dumpFonts(
                                                fontsFolder: fontsFolder.prefixed("."),
                                                outputFolder: fontsSourceFolder.prefixed("."),
                                                overwrite: false
                                            ),
                                            enabled: .no
                                        ),
                                        OperationConfig(
                                            operation: .dumpMessages(
                                                messagesFolder: messagesFolder.prefixed("."),
                                                outputFolder: messagesSourceFolder.prefixed("."),
                                                overwrite: false,
                                                variant: "xd"
                                            ),
                                            enabled: .no
                                        )
                                    ]
                                )
                            ),
                            enabled: .yes
                            )
                        ]
                    )
                + [
                    OperationConfig(
                        operation: .dolDisassembly(
                            config: DolDisassembly.Config(
                                dolPath: contentsFolder.folder("sys").file("main.dol").prefixed("."),
                                outputFolder: sourceFolder.folder("Code").prefixed("."),
                                symbolMapPath: enginesFolder.folder(dolphinEngine.name).file(gameID + ".map").prefixed("."),
                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                            )
                        ),
                        enabled: .yes
                    )
                ]
                )
        }

        let buildConfigFile = configFolder.file("Build-Config.json")
        try projectFileSystem.encodeJSON(buildConfig, to: buildConfigFile, overwrite: false)

        let dumpConfigFile = configFolder.file("Dump-Config.json")
        try projectFileSystem.encodeJSON(dumpConfig, to: dumpConfigFile, overwrite: false)

        let projectFolder = Folder(isoInputFile.path.withoutExtensions + " project")
        fileSystem.createFolder(at: projectFolder, overwrite: false)
        fileSystem.importFST(projectFileSystem, from: Folder("/"), to: projectFolder, overwrite: false)

        if let executablePath = Bundle.main.executablePath {
            [buildConfigFile, dumpConfigFile].forEach { config in
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
