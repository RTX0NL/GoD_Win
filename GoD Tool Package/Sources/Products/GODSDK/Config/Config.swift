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
        case pbrBuild(config: PBROps.BuildConfig)
        case dolDisassembly(config: DolDisassembly.Config)
        case dolAssembly(config: DolAssembly.Config)
        case relDisassembly(config: RelDisassembly.Config)
        case relAssembly(config: RelAssembly.Config)
        case commonRelDump(config: CommonRelDump.Config)
        case commonRelBuild(config: CommonRelBuild.Config)
        case relsDump(config: RelsDump.Config)
        case relsBuild(config: RelsBuild.Config)
        case cisoDump(config: CISODump.Config)
        case cisoBuild(config: CISOBuild.Config)
        case rvzDump(config: RVZDump.Config)
        case nkitDump(config: NKitDump.Config)
        case nkitBuild(config: NKitBuild.Config)
        case gciDump(config: GCIOps.DumpConfig)
        case gciBuild(config: GCIOps.BuildConfig)
        case xdSaveDump(config: XDSaveOps.DumpConfig)
        case xdSaveBuild(config: XDSaveOps.BuildConfig)
        case saveSectionsDump(config: SaveSectionsOps.DumpConfig)
        case saveSectionsBuild(config: SaveSectionsOps.BuildConfig)
        case coloSaveDump(config: ColoSaveOps.DumpConfig)
        case coloSaveBuild(config: ColoSaveOps.BuildConfig)
        case convert(config: Convert.Config)
        case nintendoArchiveDump(config: NintendoArchiveDump.SingleConfig)
        case nintendoArchiveBuild(config: NintendoArchiveBuild.SingleConfig)
        case nintendoArchivesDump(config: NintendoArchiveDump.BatchConfig)
        case nintendoArchivesBuild(config: NintendoArchiveBuild.BatchConfig)
        case pbrFontDump(config: PBRFontDump.SingleConfig)
        case pbrFontsDump(config: PBRFontDump.BatchConfig)
        case pbrFontBuild(config: PBRFontBuild.SingleConfig)
        case pbrFontsBuild(config: PBRFontBuild.BatchConfig)
        case pbrStringsDump(config: PBRStringsDump.Config)
        case pbrStringsBuild(config: PBRStringsBuild.Config)
        case compress(config: Compress.SingleConfig)
        case decompress(config: Decompress.SingleConfig)
        case compressFiles(config: Compress.BatchConfig)
        case decompressFiles(config: Decompress.BatchConfig)
        case runExecutable(config: RunExecutable.Config)
        case createPatch(config: CreatePatch.Config)
        case applyPatch(config: ApplyPatch.Config)
    }
    
    let name: String
    let description: String?
    let settingsFile: File?
    private(set) var rootFolder: Folder
    let operations: [OperationConfig<Operations>]
    
    static func decodeFromFile(_ file: File, fileSystem: FileSystemTree) throws -> GoddessConfig {
        var config: GoddessConfig = try fileSystem.decodeJSON(from: file)
        // A relative root is relative to the config file; an absolute one is
        // already where it means.
        if let parentFolder = file.parentFolder, !config.rootFolder.path.hasPrefix("/") {
            config.rootFolder = parentFolder.folder(config.rootFolder.path)
        }
        return config
    }
}
