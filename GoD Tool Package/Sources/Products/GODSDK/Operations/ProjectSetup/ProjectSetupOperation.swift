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
    static func setup(iso isoInputFile: File) throws {
        // Streamed: setup reads a few headers out of the disc image and then
        // copies it, neither of which needs it resident.
        try setup(iso: isoInputFile, fileSystem: StreamedFileSystem())
    }

    /// Testable seam: same as `setup(iso:)` but over any `FileSystemTree`,
    /// so the generated project layout and config files can be asserted
    /// against an `InMemoryFST` without touching disk.
    static func setup(iso isoInputFile: File, fileSystem: FileSystemTree) throws {
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

        // Pre-decode container and compressed disc image formats to a raw
        // ISO before the rest of setup runs. This lets a user drop a `.ciso`
        // / `.wbfs` / `.nkit.iso` at the same entry point as a raw ISO.
        let detected = DiscImageFormat.detect(in: rawInput)
        // A raw image stays a readable and is never held. CISO and NKit
        // decode to a buffer; a WBFS stays a readable too — its disc is a
        // block map over the container, and the view resolves reads
        // through it, so nothing is unpacked up front.
        let isoData: GoDReadable
        switch detected {
        case .gamecubeISO, .wiiISO, .unknown:
            // Unknown falls through as "treat as raw ISO" — the game-ID
            // read below will fail with a useful error if it isn't.
            isoData = rawInput
        case .ciso:
            guard let whole = rawInput.allData else {
                throw ProjectSetupErrors.isoNotFound(isoInputFile, .init())
            }
            isoData = try CISOConverter.dump(ciso: whole)
        case .nkitGC:
            guard let whole = rawInput.allData else {
                throw ProjectSetupErrors.isoNotFound(isoInputFile, .init())
            }
            isoData = try NKitGCConverter.dump(nkit: whole)
        case .wbfs:
            isoData = try WBFSFile(binary: rawInput).firstDiscImage()
        case .nkitWii:
            // The GameCube NKit decoder restores trailing junk; a Wii NKit
            // also needs its partitions re-hashed and re-encrypted, which
            // no code here does yet. Say exactly that rather than parse
            // the shrunk bytes as a disc.
            throw ProjectSetupErrors.unsupportedInputFormat(
                format: detected.description,
                reason: "restoring a Wii NKit needs partition re-hashing and re-encryption on top of the "
                    + "junk regeneration the GameCube decoder does, and that path doesn't exist yet. "
                    + "Convert it to a plain .iso with NKit or wit first.",
                file: isoInputFile, .init()
            )
        case .wiaOrRVZ:
            // The header and group table parse; the payload is zstd /
            // bzip2 / LZMA-compressed and there is no decompressor in the
            // package for any of the three.
            throw ProjectSetupErrors.unsupportedInputFormat(
                format: detected.description,
                reason: "its data is zstd/bzip2/LZMA-compressed and GoD-Tool has no decompressor for those "
                    + "yet (the header and group table parse, the data does not). "
                    + "Convert it to a plain .iso with Dolphin or wit first.",
                file: isoInputFile, .init()
            )
        }

        guard let gameID = isoData.readString(atAddress: 0, format: .utf8, maxCharacters: 4) else {
            throw ProjectSetupErrors.invalidGameID(.init())
        }

        // Detect disc type
        let wiiMagic: UInt32 = isoData.readSafely(atAddress: 0x18)
        let isWii = wiiMagic == 0x5D1C9EA3

        // Everything that varies per game lives in its profile; setup only
        // asks whether there is one. `gsGame` is separate because PBR is a
        // Genius Sonority title without a GameCube-side profile.
        let profile = GameProfile.profile(forGameID: gameID)
        let isPBR = PokemonBattleRevolution.gameIDs.contains(gameID)
        let gsGame: GSGame? = profile?.gsGame ?? (isPBR ? .battleRevolution : nil)
        let isGeniusSonority = gsGame != nil

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

        var settings = GoddessSettings.default
        if isWii {
            settings.wiiCommonKeyFile = "../wii-common-key.txt"
        }
        
        let settingsFile = settingsFolder.file("Settings.json")
        try projectFileSystem.encodeJSON(settings, to: settingsFile, overwrite: false)

        let dolphinEngine = try DolphinEngine.defaults()

        var engines: [any Engine] = [dolphinEngine]

        // Files the Genius Sonority engine says carry typed data sections,
        // beyond the DOL and common.rel (which have their own ops). Captured
        // here because the engine is scoped to the disc-type branch below.
        var chunkTypeMapRoutes: [GeniusSonorityEngine.Data.ChunkTypeMapRoute] = []

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
                chunkTypeMapRoutes = gsEngine.data.chunkTypeMapRoutes
                let gsfsysFile = gsEngine.data.fsys.GSfsysFile

                let isoFileSystem = try? GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
                if let tocData = isoFileSystem?.readFile(at: gsfsysFile)?.allData,
                   let toc = try? FsysTOC(tocData: tocData, engine: gsEngine) {
                    gsEngine = try GeniusSonorityEngine(data: gsEngine.data, enums: gsEngine.enums, structs: gsEngine.structs, toc: toc)
                }
                engines.append(gsEngine)
            }
        }

        // Game-specific struct engine
        if let profile {
            engines.append(try profile.makeEngine())
        }

        // PBR is a Wii title with no GameCube-side `GameProfile`, so its
        // engine is added directly. It owns the `common.fsys` data-table
        // definitions — the container header, the Pokémon model body map,
        // and the per-table entry structs.
        if isPBR {
            engines.append(try PBREngine.defaults())
        }

        // The Pokémon engine ships the species/move/item/nature/type enums
        // plus the combined Trainer struct. Every GS game (Colo/XD/PBR)
        // consumes it for name↔id resolution.
        //
        // Keyed to the disc's game, because the three numbered lists differ
        // per title — Deoxys is species 410 in Colosseum and XD but 386 in
        // Battle Revolution. Installing the wrong one would put confident,
        // wrong names in every abstracted column.
        if let game = gsGame.flatMap({ PokemonEngine.Game(rawValue: $0.rawValue) }) {
            engines.append(try PokemonEngine.defaultEngine(for: game))
        } else if isGeniusSonority {
            engines.append(try PokemonEngine.defaults())
        }

        try engines.forEach { engine in
            try engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }

        // Engines carry region-neutral resource paths; which bytes land in
        // them depends on the disc's region, so the profile resolves that.
        if let profile {
            let engineFolder = enginesFolder.folder(profile.engineName)
            for resource in profile.regionalResources(gameID) {
                try projectFileSystem.writeFile(
                    resource.data, at: engineFolder.file(resource.path.path), overwrite: true
                )
            }
        }

        // Engines whose structs and enums resolve typed data chunks in the
        // DOL and the RELs. Disassembly and assembly combine these into one
        // engine, in this order, so the game's own definitions win and the
        // shared sets they reference — Genius Sonority file/group enums,
        // Pokemon species/move/item enums — resolve behind them.
        //
        // Order matters: Colosseum and XD both declare `CharacterModel`, at
        // different sizes, so the game engine has to come first.
        let typedDataEngines: [Folder] = {
            var folders = [Folder]()
            if let profile {
                folders.append(enginesFolder.folder(profile.engineName).prefixed("."))
            }
            if isGeniusSonority, let game = gsGame {
                folders.append(
                    enginesFolder.folder(GeniusSonorityEngine.defaultEngine(for: game).name).prefixed(".")
                )
                folders.append(enginesFolder.folder(PokemonEngine.engineName).prefixed("."))
            }
            return folders
        }()

        // Build config generation
        let buildConfig: GoddessConfig
        let dumpConfig: GoddessConfig

        if isWii {
            let wiiEngine = try WiiEngine.defaults()
            let wiiEngineName = wiiEngine.name

            // Where the FSYS unpack drops PBR's fonts, and where their
            // editable artifacts live. Both `.FNT` and `.f3d` land here.
            let pbrFontsFolder = unpackedFolder.folder("Data").folder("Text").folder("Fonts")
            let pbrFontsSourceFolder = sourceFolder.folder("Text").folder("Fonts")

            var buildOperations: [OperationConfig<GoddessConfig.Operations>] = []

            // PBR fonts, rebuilt from their editable artifacts *before* the
            // FSYS repack below, so an edited font is what gets packed.
            // Disabled by default like every other asset step — a user opts
            // in once they've actually edited something.
            if isPBR {
                buildOperations.append(
                    OperationConfig(
                        operation: .pbrFontsBuild(
                            config: PBRFontBuild.BatchConfig(
                                fontsFolder: pbrFontsSourceFolder.prefixed("."),
                                outputFolder: pbrFontsFolder.prefixed("."),
                                overwrite: true
                            )
                        ),
                        enabled: .no
                    )
                )
            }

            // PBR: repack the unpacked project tree (FSYS archives, including
            // the typed common.fsys/deck.fsys tables) back into the DATA
            // partition's files before the disc is re-encrypted below.
            if isPBR, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                buildOperations.append(
                    OperationConfig(
                        operation: .pbrBuild(
                            config: PBROps.BuildConfig(
                                operations: [
                                    OperationConfig(
                                        operation: .packPBR(
                                            unpackedFolder: unpackedFolder.prefixed("."),
                                            // Same FSYS root the dump read from.
                                            fstFolder: contentsFolder.folder("DATA").prefixed("."),
                                            overwrite: true,
                                            geniusSonorityEngine: enginesFolder.folder(gsEngine.name).prefixed("."),
                                            pbrEngine: enginesFolder.folder(PBREngine.defaultName).prefixed("."),
                                            engines: []
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

            // Rebuild main.dol from its disassembly under /Source/Code back
            // into the DATA partition before the disc is re-encrypted below.
            // Ships disabled, like every other rebuild step: a user opts in
            // once they have edited the source.
            let wiiDolFile = contentsFolder.folder("DATA").folder("sys").file("main.dol")
            buildOperations.append(
                OperationConfig(
                    operation: .dolAssembly(
                        config: DolAssembly.Config(
                            codeFolder: sourceFolder.folder("Code")
                                .folder(DolDisassembler.outputFolderName(for: wiiDolFile)).prefixed("."),
                            outputDolPath: wiiDolFile.prefixed("."),
                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed(".")
                        )
                    ),
                    enabled: .no
                )
            )

            buildOperations.append(
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
                                        size: wiiEngine.data.disc.maxDiscCapacity
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
                description: "Config for encrypting and building Wii ISO from Contents folder",
                settingsFile: settingsFile.prefixed("."),
                rootFolder: "..",
                operations: buildOperations
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
                                            // Wii game files live in the DATA
                                            // partition, so the FSYS root is
                                            // Contents/DATA (not Contents).
                                            fstFolder: contentsFolder.folder("DATA").prefixed("."),
                                            outputFolder: unpackedFolder.prefixed("."),
                                            overwrite: false,
                                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                            geniusSonorityEngine: enginesFolder.folder(gsEngine.name).prefixed(".")
                                        ),
                                        enabled: .yes
                                    ),
                                    // Type common.fsys's data tables into
                                    // editable JSON + CSV, folding the rebuild
                                    // metadata into the archive registry.
                                    OperationConfig(
                                        operation: .dumpCommonTables(
                                            unpackedFolder: unpackedFolder.prefixed("."),
                                            overwrite: false,
                                            japanese: PokemonBattleRevolution.usesJapaneseTableOrder(gameID: gameID),
                                            pbrEngine: enginesFolder.folder(PBREngine.defaultName).prefixed(".")
                                        ),
                                        enabled: .yes
                                    )
                                ]
                            )
                        ),
                        enabled: .yes
                    )
                )

                // PBR fonts to editable artifacts. Ships disabled: the unpack
                // above has to run first, and a user opts in when they want
                // to edit fonts rather than paying for ~150 atlas encodes on
                // every dump.
                dumpOperations.append(
                    OperationConfig(
                        operation: .pbrFontsDump(
                            config: PBRFontDump.BatchConfig(
                                fontsFolder: pbrFontsFolder.prefixed("."),
                                outputFolder: pbrFontsSourceFolder.prefixed("."),
                                overwrite: false
                            )
                        ),
                        enabled: .no
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
            // Each game splits its maps differently — Colosseum by Type 1 /
            // Type 2 layout, XD by regular vs leftover-Colosseum — so the
            // subfolder names come from the profile's map plans.
            let mapsSourceRoot = sourceFolder.folder("Code")
            // Where the game engine serialized to. Named by the engine type
            // itself rather than a literal, so the two can't drift apart.
            let gameEngineFolder = enginesFolder.folder(profile?.engineName ?? "")

            // One asset step per format on each side, all disabled until the
            // user opts in. Each format has its own operation, so the pairs
            // are listed rather than mapped over — the config a user reads
            // names the format it acts on.
            let msgVariant = profile?.msgVariant ?? "xd"
            let assetBuildSteps: [OperationConfig<ColoXD.BuildConfig.Operations>] = [
                OperationConfig(operation: .buildFlashMenus(
                    projectsFolder: flashMenusSourceFolder.prefixed("."),
                    outputFolder: flashMenusFolder.prefixed("."),
                    overwrite: true
                ), enabled: .no),
                OperationConfig(operation: .buildFonts(
                    fontsFolder: fontsSourceFolder.prefixed("."),
                    outputFolder: fontsFolder.prefixed("."),
                    overwrite: true
                ), enabled: .no),
                OperationConfig(operation: .buildMessages(
                    jsonFolder: messagesSourceFolder.prefixed("."),
                    outputFolder: messagesFolder.prefixed("."),
                    overwrite: true
                ), enabled: .no),
                OperationConfig(operation: .buildATXs(
                    jsonFolder: atxSourceFolder.prefixed("."),
                    outputFolder: atxFolder.prefixed("."),
                    overwrite: true
                ), enabled: .no),
            ]

            let assetDumpSteps: [OperationConfig<ColoXD.DumpConfig.Operations>] = [
                OperationConfig(operation: .dumpFlashMenus(
                    flashMenusFolder: flashMenusFolder.prefixed("."),
                    outputFolder: flashMenusSourceFolder.prefixed("."),
                    overwrite: false
                ), enabled: .no),
                OperationConfig(operation: .dumpFonts(
                    fontsFolder: fontsFolder.prefixed("."),
                    outputFolder: fontsSourceFolder.prefixed("."),
                    overwrite: false
                ), enabled: .no),
                OperationConfig(operation: .dumpMessages(
                    messagesFolder: messagesFolder.prefixed("."),
                    outputFolder: messagesSourceFolder.prefixed("."),
                    overwrite: false,
                    variant: msgVariant
                ), enabled: .no),
                OperationConfig(operation: .dumpATXs(
                    atxFolder: atxFolder.prefixed("."),
                    outputFolder: atxSourceFolder.prefixed("."),
                    overwrite: false
                ), enabled: .no),
            ]

            // One chain for every Genius Sonority GameCube game. The two
            // blocks this replaces were identical apart from the FSYS
            // operation case and which map-rel source folders they used,
            // both of which the profile supplies.
            if let profile, let game = gsGame {
                let gsEngine = GeniusSonorityEngine.defaultEngine(for: game)
                let dolphinEngineFolder = enginesFolder.folder(dolphinEngine.name).prefixed(".")
                let gsEngineFolder = enginesFolder.folder(gsEngine.name).prefixed(".")

                // Rebuild common.rel from /Source/Code/common_rel back to its
                // Unpacked location *before* the FSYS pack, so the packed
                // archive picks up edits. Ships disabled, like the DOL
                // assembly: a user opts in once they have edited something.
                buildOperations.append(
                    OperationConfig(
                        operation: .commonRelBuild(
                            config: CommonRelBuild.Config(
                                inputFolder: commonRelSourceFolder.prefixed("."),
                                relName: "common",
                                outputPath: commonRelFile.prefixed("."),
                                overwrite: true,
                                engines: typedDataEngines
                            )
                        ),
                        enabled: .no
                    )
                )

                // Each map plan rebuilds from its own source folder into the
                // shared relocatable-modules folder, where the FSYS packer
                // picks the `.rel`s up.
                for plan in profile.mapPlans {
                    buildOperations.append(
                        OperationConfig(
                            operation: .mapRelsBuild(
                                config: MapRelBuild.BatchConfig(
                                    inputFolder: mapsSourceRoot.folder(plan.sourceFolderName).prefixed("."),
                                    outputFolder: relocatableModulesFolder.prefixed("."),
                                    overwrite: true,
                                    engines: typedDataEngines
                                )
                            ),
                            enabled: .no
                        )
                    )
                }

                let fsysBuild: ColoXD.BuildConfig.Operations
                switch profile.family {
                case .colosseum:
                    fsysBuild = .buildColosseum(
                        fstRegistry: unpackedFolder.file("FST.json").prefixed("."),
                        outputFolder: contentsFolder.prefixed("."),
                        overwrite: true,
                        dolphinEngine: dolphinEngineFolder,
                        geniusSonorityEngine: gsEngineFolder
                    )
                case .galeOfDarkness:
                    fsysBuild = .buildXD(
                        fstRegistry: unpackedFolder.file("FST.json").prefixed("."),
                        outputFolder: contentsFolder.prefixed("."),
                        overwrite: true,
                        dolphinEngine: dolphinEngineFolder,
                        geniusSonorityEngine: gsEngineFolder
                    )
                }

                buildOperations.append(
                    OperationConfig(
                        operation: .coloXDBuild(
                            config: ColoXD.BuildConfig(
                                operations: assetBuildSteps + [
                                    OperationConfig(operation: fsysBuild, enabled: .yes)
                                ]
                            )
                        ),
                        enabled: .yes
                    )
                )
            }

            // Rebuild main.dol from /Source/Code/main back into Build/Contents
            // before the ISO is packed. Ships disabled, like the REL rebuilds:
            // a user opts in once they have edited the disassembly. The symbol
            // and type maps mirror the dump's so typed chunks resolve the same
            // way on the way back in.
            let dolFile = contentsFolder.folder("sys").file("main.dol")
            buildOperations.append(
                OperationConfig(
                    operation: .dolAssembly(
                        config: DolAssembly.Config(
                            codeFolder: sourceFolder.folder("Code")
                                .folder(DolDisassembler.outputFolderName(for: dolFile)).prefixed("."),
                            outputDolPath: dolFile.prefixed("."),
                            symbolMapPath: profile.map { profile in
                                gameEngineFolder.file(profile.dolSymbolMapResource.path).prefixed(".")
                            },
                            dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                            typeMapPath: profile?.dolTypeMapResource.map { resource in
                                gameEngineFolder.file(resource.path).prefixed(".")
                            },
                            engines: profile?.dolTypeMapResource == nil ? nil : typedDataEngines
                        )
                    ),
                    enabled: .no
                )
            )

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
            // One step per file the Genius Sonority engine says carries typed
            // data sections. `common.rel` and the DOL have their own ops (they
            // need a symbol index and cross-module resolution); everything else
            // is a plain REL plus a type map, so covering another file is a
            // line of engine data rather than another branch here.
            //
            // Built before the config literal because the type-checker can't
            // handle it inline alongside the rest of the chain.
            let typedChunkFileSteps: [OperationConfig<GoddessConfig.Operations>] = profile.map { profile in
                chunkTypeMapRoutes.map { route in
                    let config = RelDisassembly.Config(
                        relPath: unpackedFolder.file(route.file.path).prefixed("."),
                        outputFolder: sourceFolder.folder("Code").folder(route.sourceFolderName).prefixed("."),
                        dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                        typeMapPath: enginesFolder.folder(profile.engineName).file(route.typeMap.path).prefixed("."),
                        engines: typedDataEngines
                    )
                    return OperationConfig(
                        operation: GoddessConfig.Operations.relDisassembly(config: config),
                        enabled: route.enabledByDefault ? .yes : .no
                    )
                }
            } ?? []

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
                    profile != nil,
                    // One FSYS dump chain for every Genius Sonority GameCube
                    // game. The blocks this replaces differed only in the
                    // operation case and the message variant.
                    contents: profile.map { profile in
                        let gsEngineName = GeniusSonorityEngine.defaultEngine(for: profile.gsGame).name
                        let fsysDump: ColoXD.DumpConfig.Operations
                        switch profile.family {
                        case .colosseum:
                            fsysDump = .dumpColosseum(
                                fstFolder: contentsFolder.prefixed("."),
                                outputFolder: unpackedFolder.prefixed("."),
                                overwrite: false,
                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                geniusSonorityEngine: enginesFolder.folder(gsEngineName).prefixed(".")
                            )
                        case .galeOfDarkness:
                            fsysDump = .dumpXD(
                                fstFolder: contentsFolder.prefixed("."),
                                outputFolder: unpackedFolder.prefixed("."),
                                overwrite: false,
                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                geniusSonorityEngine: enginesFolder.folder(gsEngineName).prefixed(".")
                            )
                        }
                        return [OperationConfig(
                            operation: .coloXDDump(
                                config: ColoXD.DumpConfig(
                                    operations: [
                                        OperationConfig(operation: fsysDump, enabled: .yes)
                                    ] + assetDumpSteps
                                )
                            ),
                            enabled: .yes
                        )]
                    } ?? []
                )
                .conditionalAppend(
                    profile != nil,
                    contents: profile.map { profile in
                        [OperationConfig(
                            operation: .commonRelDump(
                                config: CommonRelDump.Config(
                                    relPath: commonRelFile.prefixed("."),
                                    outputFolder: commonRelSourceFolder.prefixed("."),
                                    overwrite: false,
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: enginesFolder.folder(profile.engineName).prefixed("."),
                                    engines: typedDataEngines
                                )
                            ),
                            enabled: .yes
                        )]
                    } ?? []
                )
                .conditionalAppend(!typedChunkFileSteps.isEmpty, contents: typedChunkFileSteps)
                .conditionalAppend(
                    profile != nil,
                    // One dump op per map plan. Colosseum's two layouts and
                    // XD's regular/leftover split are the same shape, so the
                    // plan supplies the output folder, typemap and filter.
                    //
                    // All of these ship disabled: Colosseum's runtime
                    // Type 1 / Type 2 classifier isn't ported yet, and XD's
                    // map disassembly is opt-in.
                    contents: (profile?.mapPlans ?? []).map { plan in
                        OperationConfig(
                            operation: .mapRelsDump(
                                config: MapRelDump.BatchConfig(
                                    relsFolder: relocatableModulesFolder.prefixed("."),
                                    outputFolder: mapsSourceRoot.folder(plan.sourceFolderName).prefixed("."),
                                    overwrite: false,
                                    typeMapPath: gameEngineFolder.file(plan.typeMapResource.path).prefixed("."),
                                    dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                    gameEngine: gameEngineFolder.prefixed("."),
                                    filter: plan.filter,
                                    engines: typedDataEngines
                                )
                            ),
                            enabled: .no
                        )
                    }
                )
                + [
                    OperationConfig(
                        operation: .dolDisassembly(
                            config: DolDisassembly.Config(
                                dolPath: contentsFolder.folder("sys").file("main.dol").prefixed("."),
                                outputFolder: sourceFolder.folder("Code").prefixed("."),
                                // Symbol and type maps live in the game
                                // engine's Resources folder, at paths the
                                // engine declares. A game without a profile
                                // has neither, and disassembles as raw hex.
                                symbolMapPath: profile.map { profile in
                                    gameEngineFolder.file(profile.dolSymbolMapResource.path).prefixed(".")
                                },
                                dolphinEngine: enginesFolder.folder(dolphinEngine.name).prefixed("."),
                                typeMapPath: profile?.dolTypeMapResource.map { resource in
                                    gameEngineFolder.file(resource.path).prefixed(".")
                                },
                                // A type map's chunk types resolve against the
                                // combined engine, game definitions first.
                                engines: profile?.dolTypeMapResource == nil
                                    ? nil
                                    : typedDataEngines
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
        try fileSystem.createFolder(at: projectFolder, overwrite: false)
        try fileSystem.importFST(projectFileSystem, from: Folder("/"), to: projectFolder, overwrite: false)

        // The disc image is copied straight into the finished project rather
        // than staged in `projectFileSystem`, which is an `InMemoryFST` — a
        // 4.7 GB image put there would be resident for the whole of setup and
        // then copied again on the way out. `writeFile` takes a `GoDReadable`,
        // so this streams from the source file to the destination.
        try fileSystem.writeFile(
            isoData,
            at: projectFolder.file(isoOutputFile.path),
            overwrite: false
        )

        try LauncherScript.write(
            for: [buildConfigFile, dumpConfigFile],
            in: projectFolder,
            fileSystem: fileSystem
        )
    }
}
