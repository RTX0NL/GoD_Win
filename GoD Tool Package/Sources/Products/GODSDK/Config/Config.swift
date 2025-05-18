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
        case coloXDDump(config: ColoXD.DumpConfig)
        case coloXDBuild(config: ColoXD.BuildConfig)
    }
    
    let name: String
    let description: String?
    let settingsFile: File?
    private(set) var rootFolder: Folder
    let operations: [OperationConfig<Operations>]
    
    static func decodeFromFile(_ file: File, fileSystem: FileSystemTree) throws -> GoddessConfig {
        var config: GoddessConfig = try fileSystem.decodeJSON(from: file)
        if let parentFolder = file.parentFolder {
            config.rootFolder = parentFolder.folder(config.rootFolder)
        }
        return config
    }
}
