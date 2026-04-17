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
//    "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Config/Dump-Config.json",
//    "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Config/ColoXD-Dump-Only.json",
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
        guard inputFile.path != Bundle.main.executablePath, let fileType = inputFile.fileType else {
            continue
        }
        switch fileType {
        case "iso", "gcm":
            try Project.setup(iso: inputFile)
        case "json":
            let config = try GoddessConfig.decodeFromFile(inputFile, fileSystem: fileSystem)

            fileSystem.changeDirectory(config.rootFolder)
            let settings: GoddessSettings = (try? config.settingsFile.flatMap { file in
                return try fileSystem.decodeJSON(from: file)
            }) ?? GoddessSettings.default

            let logger = PrintLogger(verbose: settings.verbose)

            let enabledOps = config.operations.enabledEntries
            for (index, operation) in enabledOps.enumerated() {
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
                        try ColoXD.build(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .pbrDump(let dumpConfig):
                        try PBROps.dump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .dolDisassembly(let disasmConfig):
                        try DolDisassembly.disassemble(config: disasmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .dolAssembly(let asmConfig):
                        try DolAssembly.assemble(config: asmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .relDisassembly(let relConfig):
                        try RelDisassembly.disassemble(config: relConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    }
                    logger.log(.info("Operation \(index + 1)/\(enabledOps.count) completed"))
                }
        default:
            print("Unsupported file type '\(inputFile.fileType!)' for file \(inputFile)")
        }
    }
} catch let error {
    print(error)
}
