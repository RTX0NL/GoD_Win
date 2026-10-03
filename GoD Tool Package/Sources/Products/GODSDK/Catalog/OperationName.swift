//
//  OperationName.swift
//  GODOps
//
//  Every operation `GoddessConfig.Operations` can route, as a plain name.
//
//  An enum with associated values can't be enumerated, and the MCP server
//  has to say which operations exist without a hand-maintained string. So
//  the names live here, `CaseIterable`, and `Operations.name` is an
//  exhaustive switch: adding an operation without adding its name fails to
//  compile, and a name without an operation is caught by
//  `OperationCatalogTests`, which decodes every name as an operation key.
//

import Foundation

public enum OperationName: String, CaseIterable, Codable {
    case gamecubeDump
    case gamecubeBuild
    case wiiDump
    case wiiBuild
    case coloXDDump
    case coloXDBuild
    case pbrDump
    case pbrBuild
    case dolDisassembly
    case dolAssembly
    case relDisassembly
    case relAssembly
    case commonRelDump
    case commonRelBuild
    case relsDump
    case relsBuild
    case cisoDump
    case cisoBuild
    case gciDump
    case gciBuild
    case xdSaveDump
    case xdSaveBuild
    case saveSectionsDump
    case saveSectionsBuild
    case coloSaveDump
    case coloSaveBuild
    case convert
    case nintendoArchiveDump
    case nintendoArchiveBuild
    case nintendoArchivesDump
    case nintendoArchivesBuild
    case pbrFontDump
    case pbrFontsDump
    case pbrFontBuild
    case pbrFontsBuild
    case pbrStringsDump
    case pbrStringsBuild
    case compress
    case decompress
    case compressFiles
    case decompressFiles
    case runExecutable
    case createPatch
    case applyPatch
}

extension GoddessConfig.Operations {
    /// The case's name — the key it is spelled with in a config file.
    var name: OperationName {
        switch self {
        case .gamecubeDump: return .gamecubeDump
        case .gamecubeBuild: return .gamecubeBuild
        case .wiiDump: return .wiiDump
        case .wiiBuild: return .wiiBuild
        case .coloXDDump: return .coloXDDump
        case .coloXDBuild: return .coloXDBuild
        case .pbrDump: return .pbrDump
        case .pbrBuild: return .pbrBuild
        case .dolDisassembly: return .dolDisassembly
        case .dolAssembly: return .dolAssembly
        case .relDisassembly: return .relDisassembly
        case .relAssembly: return .relAssembly
        case .commonRelDump: return .commonRelDump
        case .commonRelBuild: return .commonRelBuild
        case .relsDump: return .relsDump
        case .relsBuild: return .relsBuild
        case .cisoDump: return .cisoDump
        case .cisoBuild: return .cisoBuild
        case .gciDump: return .gciDump
        case .gciBuild: return .gciBuild
        case .xdSaveDump: return .xdSaveDump
        case .xdSaveBuild: return .xdSaveBuild
        case .saveSectionsDump: return .saveSectionsDump
        case .saveSectionsBuild: return .saveSectionsBuild
        case .coloSaveDump: return .coloSaveDump
        case .coloSaveBuild: return .coloSaveBuild
        case .convert: return .convert
        case .nintendoArchiveDump: return .nintendoArchiveDump
        case .nintendoArchiveBuild: return .nintendoArchiveBuild
        case .nintendoArchivesDump: return .nintendoArchivesDump
        case .nintendoArchivesBuild: return .nintendoArchivesBuild
        case .pbrFontDump: return .pbrFontDump
        case .pbrFontsDump: return .pbrFontsDump
        case .pbrFontBuild: return .pbrFontBuild
        case .pbrFontsBuild: return .pbrFontsBuild
        case .pbrStringsDump: return .pbrStringsDump
        case .pbrStringsBuild: return .pbrStringsBuild
        case .compress: return .compress
        case .decompress: return .decompress
        case .compressFiles: return .compressFiles
        case .decompressFiles: return .decompressFiles
        case .runExecutable: return .runExecutable
        case .createPatch: return .createPatch
        case .applyPatch: return .applyPatch
        }
    }
}
