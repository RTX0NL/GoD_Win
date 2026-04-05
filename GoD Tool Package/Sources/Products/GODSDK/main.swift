//
//  main.swift
//  
//
//  Created by Stars Momodu on 04/06/2024.
//

import GoDFoundation
import Structs
import GameCube
import Dolphin
import Wii
import GeniusSonority

// For development, uncomment and set args:
//let mode = RunModes.development(args: [
//    "/Users/stars/Documents/GoD Tool/XD.iso",
//    "/Users/stars/Documents/GoD Tool/XD project/Config/Dump-Config.json",
//    "/Users/stars/Documents/GoD Tool/XD project/Config/Build-Config.json",
//])

let mode = RunModes.commandLine

do {
    let arguments = mode.arguments
    guard arguments.count > 0 else {
        print("No input files provided. Exiting program.")
        exit(EXIT_FAILURE)
    }
    
    let fileSystem = FileSystem.shared
    for inputFile in arguments.map({ File($0) }) {
        guard inputFile.path != Bundle.main.executablePath else {
            continue
        }
        switch inputFile.fileType {
        case "iso", "gcm":
            try Project.setup(iso: inputFile)
        case "json":
            let config = try GoddessConfig.decodeFromFile(inputFile, fileSystem: fileSystem)
            
            fileSystem.changeDirectory(config.rootFolder)
            let settings: GoddessSettings = try config.settingsFile.flatMap { file in
                return try fileSystem.decodeJSON(from: file)
            } ?? GoddessSettings.default
            
            let logger = PrintLogger(verbose: settings.verbose)
            
            try config.operations
                .enabledEntries
                .forEach { operation in
                    fileSystem.changeDirectory(config.rootFolder)
                    switch operation {
                    case .gamecubeDump(let dumpConfig):
                        try Gamecube.dump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .gamecubeBuild(let buildConfig):
                        try Gamecube.build(config: buildConfig, settings: settings, fileSystem: fileSystem)
                    case .wiiDump(let dumpConfig):
                        try WiiOps.dump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .wiiBuild(let buildConfig):
                        try WiiOps.build(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .coloXDDump(let dumpConfig):
                        try ColoXD.dump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .coloXDBuild(let buildConfig):
                        try ColoXD.build(config: buildConfig, settings: settings, fileSystem: fileSystem)
                    case .pbrDump(let dumpConfig):
                        try PBROps.dump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .dolDisassembly(let disasmConfig):
                        try DolDisassembly.disassemble(config: disasmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .dolAssembly(let asmConfig):
                        try DolAssembly.assemble(config: asmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    }
                }
        
        // Temporary
        case "fsys":
            let gsEngine = GeniusSonorityEngine.defaultEngine(for: .galeOfDarkness)
            let inputData = fileSystem.readFile(at: inputFile)!
            let fsys = try FSYSArchive(data: inputData, engine: gsEngine)
            fsys.entries.forEach { entry in
                print(entry.filename, entry.data.length.hexString())
            }
            let recreated = try fsys.data(groupID: 0x5742, engine: gsEngine)
            let outputFile = inputFile.parentFolder!.file(inputFile.fileName.withoutExtension + " dupe." + inputFile.fileType)
            fileSystem.writeFile(recreated, at: outputFile, overwrite: true)
           
            
        default:
            print("Unsupported file type '\(inputFile.fileType)' for file \(inputFile)")
        }
    }
} catch let error {
    print(error)
}
