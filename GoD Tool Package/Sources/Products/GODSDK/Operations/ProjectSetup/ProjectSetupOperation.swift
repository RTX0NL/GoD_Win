import GoDFoundation
import GoDEngine
import Dolphin
import GameCube
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
        let sourceFolder = Folder("/Source")
        let configFolder = Folder("/Config")
        let settingsFolder = Folder("/Settings")
        let enginesFolder = Folder("/Engines")
        let scriptsFolder = Folder("/Scripts")
        
        guard let isoData = fileSystem.readFile(at: isoInputFile) else {
            throw ProjectSetupErrors.isoNotFound(isoInputFile, .init())
        }
        guard let gameID = isoData.readString(atAddress: 0, format: .utf8, maxCharacters: 4) else {
            throw ProjectSetupErrors.invalidGameID(.init())
        }
        
        let isColosseum = PokemonColosseum.gameIDs.contains(gameID)
        let isXD = PokemonXD.gameIDs.contains(gameID)
        let isGeniusSonority = isColosseum || isXD
        
        let projectFolders = [
            buildFolder, isoFolder, contentsFolder,
            configFolder, settingsFolder, enginesFolder, scriptsFolder
        ]
        .conditionalAppend(isColosseum || isXD, contents: [sourceFolder])
        
        projectFolders.forEach { folder in
            projectFileSystem.createFolder(at: folder, overwrite: true)
        }
        
        let isoOutputFile = isoFolder.file(isoInputFile.fileName)
        projectFileSystem.writeFile(isoData, at: isoOutputFile, overwrite: false)
        
        let settings = GoddessSettings.default
        let settingsFile = settingsFolder.file("Settings.json")
        try projectFileSystem.encodeJSON(settings, to: settingsFile, overwrite: false)
        
        let gamecubeEngine = try GamecubeEngine.defaults()
        let dolphinEngine = try DolphinEngine.defaults()
        
        var gsGame: GSGame?
        if isColosseum {
            gsGame = .colosseum
        } else if isXD {
            gsGame = .galeOfDarkness
        }
        
        var gsEngine = GeniusSonorityEngine.defaultEngine(for: gsGame ?? .colosseum)
        if (isGeniusSonority) {
            let gsfsysFile = gsEngine.data.fsys.GSfsysFile
            
            if gsGame == .battleRevolution {
                
            } else {
                let isoFileSystem = try? GamecubeISO(data: isoData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
                if let tocData = isoFileSystem?.readFile(at: gsfsysFile),
                   let toc = try? FsysTOC(tocData: tocData, engine: gsEngine) {
                    gsEngine = try GeniusSonorityEngine(data: gsEngine.data, enums: gsEngine.enums, structs: gsEngine.structs, toc: toc)
                }
            }
            
        }
        
        let engines: [any Engine] = [
            gamecubeEngine,
            dolphinEngine
        ]
        .conditionalAppend(isGeniusSonority, contents: [gsEngine])
        
        engines.forEach { engine in
            engine.write(to: projectFileSystem, in: enginesFolder, overwrite: false)
        }
        
        let buildConfig = GoddessConfig(
            name: "Build ISO",
            description: "Config for building ISO from Contents folder",
            settingsFile: settingsFile.prefixed("."),
            rootFolder: "..",
            operations: [
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
            ]
        )
        
        let dumpConfig = GoddessConfig(
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
                                            outputFolder: sourceFolder.prefixed("."),
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
                                            outputFolder: sourceFolder.prefixed("."),
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
                    ]
                )
            )
                               
        
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
                \(executablePath.replacingOccurrences(of: " ", with: "\\ ")) \(Folder("..").file(config).path.replacingOccurrences(of: " ", with: "\\ "))
                """
                let file = projectFolder.folder("Scripts").file(config.fileName.replacingOccurrences(of: "-Config.json", with: ".sh"))
                fileSystem.writeFile(script.data(format: .utf8), at: file, overwrite: false)
                fileSystem.setExecutable(file: file)
            }
            
        }
    }
}
