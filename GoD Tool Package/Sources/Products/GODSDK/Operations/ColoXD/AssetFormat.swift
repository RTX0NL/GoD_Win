//
//  AssetFormat.swift
//  GODOps
//
//  The asset format a `dumpAssets` / `buildAssets` operation works on.
//
//  Each supported format used to get four operation cases — `dumpX`, `dumpXs`,
//  `buildX`, `buildXs` — plus four handler methods and four routing tests, and
//  each dump/build pair re-implemented the same folder walk and the same
//  "read the manifest, resolve its companions, write the artifacts" dance.
//  Adding ISF audio and THP video cost eight cases between them.
//
//  The format is a parameter now. Two operations cover every format, and this
//  enum is where the per-format differences live: which files to look for,
//  what the rebuilt file is called, and any extra input a format needs (the
//  message variant, the script language and engine).
//

import Foundation
import GoDFoundation
import GeniusSonority
import Colosseum

extension ColoXD {

    /// What a `dumpAssets` / `buildAssets` operation is pointed at. A single
    /// file or a folder to walk — the batch and single-file operation pairs
    /// this replaces differed only in that.
    enum AssetPath: Codable, Equatable {
        case file(File)
        case folder(Folder)
    }

    enum AssetFormat: Codable, Equatable {
        case font
        case flashMenu
        /// The binary layout is shared between Colosseum and XD; only the
        /// string rendering differs, so the variant has to be supplied.
        case message(variant: String)
        case texture
        case audio
        /// Scripts decompile to source text, so they need the dialect to emit
        /// and the engine that declares the builtin signatures.
        case coloScript(language: ColoScriptLanguage, engine: Folder)

        /// Extension of the game-side binary this format is dumped from.
        var binaryExtension: String {
            switch self {
            case .font:        return "fnt"
            case .flashMenu:   return "gsw"
            case .message:     return "msg"
            case .texture:     return "atx"
            case .audio:       return "ish"
            case .coloScript:  return "scd"
            }
        }

        /// Suffix identifying the manifest a build reads back. Formats that
        /// rebuild from a plain `.json` (fonts, messages) use that; the ones
        /// with companion assets use a compound `<name>.<format>.json`.
        var manifestSuffix: String {
            switch self {
            case .font:        return ".json"
            case .flashMenu:   return ".json"
            case .message:     return ".json"
            case .texture:     return ".atx.json"
            case .audio:       return ".isf.json"
            case .coloScript:  return ""      // source text, not a manifest
            }
        }

        /// Whether a dump gives each input its own subfolder. Formats that
        /// emit companion assets beside their manifest need one so files from
        /// different inputs can't collide.
        var dumpsIntoPerFileFolder: Bool {
            switch self {
            case .flashMenu, .texture: return true
            case .font, .message, .audio, .coloScript: return false
            }
        }

        /// Human-readable name for log lines.
        var displayName: String {
            switch self {
            case .font:        return "font"
            case .flashMenu:   return "flash menu"
            case .message:     return "message"
            case .texture:     return "ATX texture"
            case .audio:       return "ISF audio"
            case .coloScript:  return "Colosseum script"
            }
        }
    }
}
