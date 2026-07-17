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
        case "iso", "gcm", "ciso", "wia", "rvz":
            // Raw `.iso`/`.gcm` pass straight through; compressed
            // variants are auto-decoded inside `Project.setup`.
            try Project.setup(iso: inputFile)
        case "gci":
            try Project.setup(gci: inputFile)
        case "fsys":
            try Project.unpack(fsys: inputFile)
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
                    case .relAssembly(let relConfig):
                        try RelAssembly.assemble(config: relConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .commonRelDump(let cfg):
                        try CommonRelDump.dump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .commonRelBuild(let cfg):
                        try CommonRelBuild.build(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .mapRelDump(let cfg):
                        try MapRelDump.dump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .mapRelBuild(let cfg):
                        try MapRelBuild.build(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .mapRelsDump(let cfg):
                        try MapRelDump.dump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .mapRelsBuild(let cfg):
                        try MapRelBuild.build(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .cisoDump(let cisoConfig):
                        try CISODump.dump(config: cisoConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .cisoBuild(let cisoConfig):
                        try CISOBuild.build(config: cisoConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .gciDump(let gciConfig):
                        try GCIOps.dump(config: gciConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .gciBuild(let gciConfig):
                        try GCIOps.build(config: gciConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .xdSaveDump(let xdConfig):
                        try XDSaveOps.dump(config: xdConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .xdSaveBuild(let xdConfig):
                        try XDSaveOps.build(config: xdConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .coloSaveDump(let coloConfig):
                        try ColoSaveOps.dump(config: coloConfig, settings: settings, fileSystem: fileSystem, logger: logger)
                    case .coloSaveBuild(let coloConfig):
                        try ColoSaveOps.build(config: coloConfig, settings: settings, fileSystem: fileSystem, logger: logger)
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
