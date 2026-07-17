import GoDFoundation
import GoDEngine
import Dolphin
import GameCube
import Wii
import PBR
import GeniusSonority
import Colosseum
import XD
import Pokemon

enum Project {
    /// Resolves the on-disk DOL symbol map path for the active game,
    /// reading the single `dolSymbolMap` field from the game engine's
    /// `Data.Resources`. Returns nil when neither XD nor Colosseum is
    /// active — the op consumer should treat a missing path as "no
    /// symbol resolution available" rather than failing.
    static func dolSymbolMapFile(
        isXD: Bool,
        isColosseum: Bool,
        enginesFolder: Folder
    ) -> File? {
        if isXD, let engine = try? XDEngine.defaults() {
            return enginesFolder.folder(engine.name).file(engine.data.resources.dolSymbolMap.path).prefixed(".")
        }
        if isColosseum, let engine = try? ColosseumEngine.defaults() {
            return enginesFolder.folder(engine.name).file(engine.data.resources.dolSymbolMap.path).prefixed(".")
        }
        return nil
    }

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

        guard let rawInput = fileSystem.readFile(at: isoInputFile) else {
            throw ProjectSetupErrors.isoNotFound(isoInputFile, .init())
        }

        // Pre-decode compressed disc image formats to a raw ISO before
        // the rest of setup runs. This lets a user drop a `.ciso` /
        // `.nkit.iso` / `.rvz` at the same entry point as a raw ISO.
        let detected = DiscImageFormat.detect(in: rawInput)
        let isoData: GoDData
        switch detected {
        case .gamecubeISO, .wiiISO, .unknown:
            // Unknown falls through as "treat as raw ISO" — the game-ID
            // read below will fail with a useful error if it isn't.
            isoData = rawInput
        case .ciso:
            isoData = try CISOConverter.dump(ciso: rawInput)
        case .nkitGC:
            isoData = try NKitGCConverter.dump(nkit: rawInput)
        case .nkitWii, .wiaOrRVZ:
            // Format detected but the decoder isn't wired up yet. Fail
            // loudly rather than trying to parse the compressed bytes
            // as a raw disc image.
            throw ProjectSetupErrors.unsupportedInputFormat(
                format: detected.description, file: isoInputFile, .init()
            )
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

        // Normalise the in-project filename to a `.iso` extension if
        // we decoded from a compressed variant — the bytes we just
        // wrote are raw disc data, regardless of the source filename.
        let outputFilename: String = {
            if detected == .gamecubeISO || detected == .wiiISO || detected == .unknown {
                return isoInputFile.fileName
            }
            return isoInputFile.fileName.withoutExtensions + ".iso"
        }()
        let isoOutputFile = isoFolder.file(outputFilename)
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

        // The Pokémon engine ships canonical species/move/item/ability/
        // nature/type enums plus the combined Trainer struct. Every GS
        // game (Colo/XD/PBR) consumes it for name↔id resolution.
        if isGeniusSonority {
            engines.append(try PokemonEngine.defaults())
        }

        engines.forEach { engine in
            engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }

        // Write the region-matched DOL symbol map into the engine's
        // declared `dolSymbolMap` slot. The engine itself carries only
        // the region-neutral path; the bytes that land there are chosen
        // here based on the ROM's game ID.
        if isXD,
           let regionalMap = PokemonXD.symbolMapData(for: gameID),
           let xdEngine = try? XDEngine.defaults() {
            let mapPath = enginesFolder.folder(xdEngine.name)
                .file(xdEngine.data.resources.dolSymbolMap.path)
            projectFileSystem.writeFile(regionalMap, at: mapPath, overwrite: true)
        }
        if isColosseum,
           let regionalMap = PokemonColosseum.symbolMapData(for: gameID),
           let coloEngine = try? ColosseumEngine.defaults() {
            let mapPath = enginesFolder.folder(coloEngine.name)
                .file(coloEngine.data.resources.dolSymbolMap.path)
            projectFileSystem.writeFile(regionalMap, at: mapPath, overwrite: true)
        }

        // common.rel pointer-index → label name varies by region for
        // Colosseum (StringTable*/Script live at different indices per
        // build). The bundle ships one map per region; pick the matching
        // one and write it to the engine's region-neutral path. XD's
        // common.rel layout is region-stable so it stays bundled by
        // `XDEngine.bundledResources()`.
        if isColosseum,
           let regionalSymbols = PokemonColosseum.commonRelSymbolMapData(for: gameID),
           let coloEngine = try? ColosseumEngine.defaults() {
            let symbolPath = enginesFolder.folder(coloEngine.name)
                .file(coloEngine.data.resources.commonRelSymbolMap.path)
            projectFileSystem.writeFile(regionalSymbols, at: symbolPath, overwrite: true)
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
            // FSYS unpack puts raw .atx files under /Unpacked/Assets/Images/Misc.
            let atxFolder = unpackedFolder.folder("Assets").folder("Images").folder("Misc")
            // Per-ATX project subfolders (each with `<name>.atx.json` + frame PNGs).
            let atxSourceFolder = sourceFolder.folder("Animations").folder("ATX")
            // common.rel is routed to /Assets/Data/Common by the
            // GeniusSonority engine override (not /Data/Relocatable Modules)
            // so the dedicated dump/build ops can target it directly.
            let commonRelFile = unpackedFolder.folder("Assets").folder("Data").folder("Common").file("common.rel")
            // Disassembled source for common.rel — sits alongside the
            // DOL disassembly output under /Source/Code.
            let commonRelSourceFolder = sourceFolder.folder("Code").folder("common_rel")
            // Map .rel files all sit under the relocatable-modules folder.
            // Map disassembly source lands under /Source/Code/maps/.
            let relocatableModulesFolder = unpackedFolder.folder("Data").folder("Relocatable Modules")
            let mapsSourceFolder = sourceFolder.folder("Code").folder("maps")
            // Colosseum splits maps into Type 1 / Type 2 layouts; XD
            // routes "unused" leftover-Colo maps to a separate folder.
            let mapsSourceFolderType1 = sourceFolder.folder("Code").folder("maps_type1")
            let mapsSourceFolderType2 = sourceFolder.folder("Code").folder("maps_type2")
            let unusedMapsSourceFolder = sourceFolder.folder("Code").folder("maps_unused")

            if isColosseum, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                // Rebuild common.rel from /Source/Code/common_rel back to
                // its Unpacked location *before* the FSYS pack, so the
                // packed archive picks up edits. Disabled by default
                // until the typed-chunk reassembly path lands.
                buildOperations.append(
                    OperationConfig(
                        operation: .commonRelBuild(
                            config: CommonRelBuild.Config(
                                inputFolder: commonRelSourceFolder.prefixed("."),
                                relName: "common",
                                outputPath: commonRelFile.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
                // Rebuild Colosseum maps from both type folders, writing
                // each rebuilt `.rel` back into the shared relocatable-
                // modules folder where the FSYS packer expects them.
                buildOperations.append(
                    OperationConfig(
                        operation: .mapRelsBuild(
                            config: MapRelBuild.BatchConfig(
                                inputFolder: mapsSourceFolderType1.prefixed("."),
                                outputFolder: relocatableModulesFolder.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
                buildOperations.append(
                    OperationConfig(
                        operation: .mapRelsBuild(
                            config: MapRelBuild.BatchConfig(
                                inputFolder: mapsSourceFolderType2.prefixed("."),
                                outputFolder: relocatableModulesFolder.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
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
                                    operation: .buildATXs(
                                        jsonFolder: atxSourceFolder.prefixed("."),
                                        outputFolder: atxFolder.prefixed("."),
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
                    OperationConfig(
                        operation: .commonRelBuild(
                            config: CommonRelBuild.Config(
                                inputFolder: commonRelSourceFolder.prefixed("."),
                                relName: "common",
                                outputPath: commonRelFile.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
                // Rebuild XD maps from both the regular and the
                // unused-Colo folders. Both feed into the shared
                // relocatable-modules folder; the FSYS packer pulls
                // from there during the FSYS rebuild step.
                buildOperations.append(
                    OperationConfig(
                        operation: .mapRelsBuild(
                            config: MapRelBuild.BatchConfig(
                                inputFolder: mapsSourceFolder.prefixed("."),
                                outputFolder: relocatableModulesFolder.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
                buildOperations.append(
                    OperationConfig(
                        operation: .mapRelsBuild(
                            config: MapRelBuild.BatchConfig(
                                inputFolder: unusedMapsSourceFolder.prefixed("."),
                                outputFolder: relocatableModulesFolder.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
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
                                    operation: .buildATXs(
                                        jsonFolder: atxSourceFolder.prefixed("."),
                                        outputFolder: atxFolder.prefixed("."),
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

            // Assemble dump operations as a typed local — the chained
            // `.conditionalAppend(...)` builder is too deep for Swift's
            // type-checker to handle inline alongside the surrounding
            // `GoddessConfig(...)` literal.
            let dumpOps: [OperationConfig<GoddessConfig.Operations>] = [
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
                                        ),
                                        OperationConfig(
                                            operation: .dumpATXs(
                                                atxFolder: atxFolder.prefixed("."),
                                                outputFolder: atxSourceFolder.prefixed("."),
                                                overwrite: false
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
                                        ),
                                        OperationConfig(
                                            operation: .dumpATXs(
                                                atxFolder: atxFolder.prefixed("."),
                                                outputFolder: atxSourceFolder.prefixed("."),
                                                overwrite: false
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
                    isColosseum || isXD,
                    contents: [
                        OperationConfig(
                            operation: .commonRelDump(
                                config: CommonRelDump.Config(
                                    relPath: commonRelFile.prefixed("."),
                                    outputFolder: commonRelSourceFolder.prefixed("."),
                                    overwrite: false,
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    // Engine names are stable instance
                                    // properties (see XDEngine/ColosseumEngine).
                                    // Hardcode here to avoid triggering
                                    // engine-default initialization (some
                                    // sub-tables construct Folders that
                                    // depend on inputs we don't have here).
                                    gameEngine: enginesFolder
                                        .folder(isXD ? "XD Engine" : "Colosseum Engine")
                                        .prefixed(".")
                                )
                            ),
                            enabled: .yes
                        )
                    ]
                )
                .conditionalAppend(
                    isColosseum,
                    contents: [
                        // Colosseum maps come in two layouts. The legacy
                        // parser detects them at runtime via an angle
                        // sentinel; until that runtime-classifier is
                        // ported, project setup ships both ops disabled
                        // and the user opts in once the per-game prefix
                        // list is known. Output folders are split so
                        // both ops can run independently.
                        OperationConfig(
                            operation: .mapRelsDump(
                                config: MapRelDump.BatchConfig(
                                    relsFolder: relocatableModulesFolder.prefixed("."),
                                    outputFolder: mapsSourceFolderType1.prefixed("."),
                                    overwrite: false,
                                    typeMapPath: enginesFolder.folder("Colosseum Engine").file("Resources/map_rel_typemap_type1.json").prefixed("."),
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: enginesFolder.folder("Colosseum Engine").prefixed("."),
                                    filter: .coloType1
                                )
                            ),
                            enabled: .no
                        ),
                        OperationConfig(
                            operation: .mapRelsDump(
                                config: MapRelDump.BatchConfig(
                                    relsFolder: relocatableModulesFolder.prefixed("."),
                                    outputFolder: mapsSourceFolderType2.prefixed("."),
                                    overwrite: false,
                                    typeMapPath: enginesFolder.folder("Colosseum Engine").file("Resources/map_rel_typemap_type2.json").prefixed("."),
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: enginesFolder.folder("Colosseum Engine").prefixed("."),
                                    filter: .coloType2
                                )
                            ),
                            enabled: .no
                        )
                    ]
                )
                .conditionalAppend(
                    isXD,
                    contents: [
                        // XD: dump the regular maps (excluding the
                        // leftover Colo-format ones), then dump the
                        // unused-prefix maps to a separate folder with
                        // no typemap. Disabled by default until users
                        // opt into map disassembly.
                        OperationConfig(
                            operation: .mapRelsDump(
                                config: MapRelDump.BatchConfig(
                                    relsFolder: relocatableModulesFolder.prefixed("."),
                                    outputFolder: mapsSourceFolder.prefixed("."),
                                    overwrite: false,
                                    typeMapPath: enginesFolder.folder("XD Engine").file("Resources/map_rel_typemap.json").prefixed("."),
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: enginesFolder.folder("XD Engine").prefixed("."),
                                    // Default unused-Colo prefixes from
                                    // XDEngine.Data.unusedColosseumMapPrefixes;
                                    // hardcoded here for the same reason
                                    // as the engine-name string above.
                                    filter: .excludePrefixes(["B1_", "M1_"])
                                )
                            ),
                            enabled: .no
                        ),
                        OperationConfig(
                            operation: .mapRelsDump(
                                config: MapRelDump.BatchConfig(
                                    relsFolder: relocatableModulesFolder.prefixed("."),
                                    outputFolder: unusedMapsSourceFolder.prefixed("."),
                                    overwrite: false,
                                    typeMapPath: enginesFolder.folder("XD Engine").file("Resources/map_rel_typemap.json").prefixed("."),
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: enginesFolder.folder("XD Engine").prefixed("."),
                                    filter: .onlyPrefixes(["B1_", "M1_"])
                                )
                            ),
                            enabled: .no
                        )
                    ]
                )
                + [
                    OperationConfig(
                        operation: .dolDisassembly(
                            config: DolDisassembly.Config(
                                dolPath: contentsFolder.folder("sys").file("main.dol").prefixed("."),
                                outputFolder: sourceFolder.folder("Code").prefixed("."),
                                // DOL symbol maps now live under the game
                                // engine's Resources folder (copied there
                                // by `Engine.write`/`bundledResources()`).
                                // Resolve the path for this game ID via
                                // the game engine's `Data.Resources`.
                                symbolMapPath: dolSymbolMapFile(
                                    isXD: isXD,
                                    isColosseum: isColosseum,
                                    enginesFolder: enginesFolder
                                ),
                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                            )
                        ),
                        enabled: .yes
                    )
                ]

            dumpConfig = GoddessConfig(
                name: "Dump ISO",
                description: "Config for dumping ISO files to Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: dumpOps
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
