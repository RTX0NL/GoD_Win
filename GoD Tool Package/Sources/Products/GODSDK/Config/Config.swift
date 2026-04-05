//
//  File.swift
//  
//
//  Created by Stars Momodu on 08/06/2024.
//

import GoDFoundation

struct GoddessConfig: Codable {
    enum Operations: Codable {
        case gamecubeDump(config: Gamecube.DumpConfig)
        case gamecubeBuild(config: Gamecube.BuildConfig)
        case wiiDump(config: WiiOps.DumpConfig)
        case wiiBuild(config: WiiOps.BuildConfig)
        case coloXDDump(config: ColoXD.DumpConfig)
        case coloXDBuild(config: ColoXD.BuildConfig)
        case pbrDump(config: PBROps.DumpConfig)
        case dolDisassembly(config: DolDisassembly.Config)
        case dolAssembly(config: DolAssembly.Config)
    }
    
    let name: String
    let description: String?
    let settingsFile: File?
    private(set) var rootFolder: Folder
    let operations: [OperationConfig<Operations>]
    
    static func decodeFromFile(_ file: File, fileSystem: FileSystemTree) throws -> GoddessConfig {
        var config: GoddessConfig = try fileSystem.decodeJSON(from: file)
        if let parentFolder = file.parentFolder {
            config.rootFolder = parentFolder.folder(config.rootFolder.path)
        }
        return config
    }
}
