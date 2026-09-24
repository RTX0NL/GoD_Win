@_exported import GoDEngine
import GoDFoundation
import Structs

/// Which Genius Sonority title an engine instance serves.
///
/// Codable and stored on the engine's `Data` because the engine is
/// serialized into a project and reloaded later — `defaultEngine(for:)` is
/// not re-run at that point, so anything that varies per game has to survive
/// the round trip. The `.fnt` extension is the reason this matters: Colo/XD
/// and PBR use entirely different font formats under the same name, and the
/// only thing that distinguishes them is which game's archive they came from.
public enum GSGame: String, Codable, CaseIterable {
    case colosseum, galeOfDarkness, battleRevolution
}

public struct GeniusSonorityEngine: Engine {
    public typealias DataType = GeniusSonorityEngine.Data
    public typealias EnumsType = GeniusSonorityEngine.Enums
    public typealias StructsType = GeniusSonorityEngine.Structs

    public let name = "GeniusSonority Engine"
    public private(set) var data = GeniusSonorityEngine.Data()
    public private(set) var enums = GeniusSonorityEngine.Enums()
    public private(set) var structs = GeniusSonorityEngine.Structs()
    private(set) var definitions: [StructDefinition]!

    public init(data: Data, enums: Enums, structs: Structs) throws {
        self.data = data
        self.enums = enums
        self.structs = structs
        definitions = try structs.entries.map(\.name).map { structName in
            try getStruct(structName)
        }
    }

    public init(data: Data, enums: Enums, structs: Structs, toc: FsysTOC) throws {
        var enumList = enums.entries
        enumList.removeAll(where: {
            ["FsysGroupIDs"].contains($0.name)
        })
        enumList.append(toc.enumeration)
        try self.init(data: data, enums: Enums(unchecked: enumList), structs: structs)
        self.data.toc.unknown = toc.unknown
        self.data.toc.padding = toc.padding
        self.data.toc.junk1 = toc.junk1
        self.data.toc.junk2 = toc.junk2
        self.data.toc.junk3 = toc.junk3
    }

    public static func defaultEngine(for game: GSGame) -> GeniusSonorityEngine {
        defaultEngine(for: game, fsysTOC: nil)
    }

    public static func defaultEngine(for game: GSGame, fsysTOC: FsysTOC?) -> GeniusSonorityEngine {
        var data = GeniusSonorityEngine.Data()
        data.game = game
        var structsList = GeniusSonorityEngine.Structs.allItems
        var enumList = GeniusSonorityEngine.Enums.allItems

        enumList.removeAll(where: {
            ["FileTypes", "FsysGroupIDs"].contains($0.name)
        })
        structsList.removeAll(where: {
            ["FsysTOCEntry"].contains($0.name)
        })

        // Every Genius Sonority game stores `(null)` for an entry whose name
        // the packer never filled in, so the unpack names those by archive +
        // index for all three rather than only for PBR. XD relies on it most:
        // without it ~1200 entries per disc share nine names and overwrite
        // each other on the way out.
        data.fsys.scrubbedFilenamePlaceholder = "(null)"

        switch game {
        case .colosseum:
            data.saveCard = Data.colosseumSaveCard
            data.fsys.fileMetaDataPadding = 0x20
            // Colosseum's packer leaves 12 bytes of 0x11 in every entry's
            // metadata padding. Verified constant across all 1028 entries
            // of the 299 US archives surveyed; XD leaves the region zero.
            data.fsys.fileMetaDataFill = .init(offset: 0x34, length: 12, byte: 0x11)
            data.toc.unknown = 0x104
            structsList.append(Structs.Defaults.fsysTOCEntryStructSmall)
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsColoEnum)
            data.fsys.fileTypeReplacements = [
                "mdat": "dat"
            ]
        case .galeOfDarkness:
            data.saveCard = Data.galeOfDarknessSaveCard
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x201
            // XD is the only game that ships an extra typed REL
            // (`tableres2.rel`, inside `common_dvdeth.fsys`).
            data.chunkTypeMapRoutes = Data.defaultXDChunkTypeMapRoutes
            structsList.append(Structs.Defaults.fsysTOCEntryStructFull)
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsXDEnum)
            data.fsys.fileTypeReplacements = [
                "mdat": "dat"
            ]
        case .battleRevolution:
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x251
            // PBR's packer checksums every compressed entry; Colo and XD
            // leave that header field zero.
            data.lzss.writesUncompressedChecksum = true
            structsList.append(Structs.Defaults.fsysTOCEntryStructFull)
            enumList.append(Enums.Defaults.fileTypesPBREnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsPBREnum)
            data.fsys.fileTypeReplacements = [
                "dckp": "bin",
                "dckt": "bin",
                "dcka": "bin",
            ]
        }

        // Per-game FSYS category lists and archive overrides
        switch game {
        case .colosseum:
            data.fsys.mapFsysNames = Data.FSYS.defaultColoMapFsysNames
            data.fsys.menuFsysNames = Data.FSYS.defaultColoMenuFsysNames
            data.fsys.battlefieldFsysNames = Data.FSYS.defaultColoBattlefieldFsysNames
            data.fsys.commonFsysNames = Data.FSYS.defaultColoCommonFsysNames
            data.fsys.miscFsysNames = Data.FSYS.defaultColoMiscFsysNames
            data.fsys.characterImageFsysNames = ["chara_big", "chara_small"]
            data.fsys.archiveFileTypeFolders = [
                "poke_face": ["gtx": "/Assets/Images/Pokemon/Faces"],
                "poke_body": ["gtx": "/Assets/Images/Pokemon/PC Box", "atx": "/Assets/Images/Pokemon/PC Box"],
            ]
            data.fsys.archiveFileOverrides = [
                "common": [
                    "DeckData_DarkPokemon": "/Data/Decks",
                    // common.rel is the source of truth for shared game
                    // tables (Pokemon, Moves, Trainers, etc.) — surface
                    // it next to the other shared data rather than under
                    // the generic relocatable-modules folder. The
                    // dedicated `commonRelDump` op reads from here.
                    "common": "/Assets/Data/Common",
                ],
            ]
        case .galeOfDarkness:
            data.fsys.mapFsysNames = Data.FSYS.defaultXDMapFsysNames
            data.fsys.menuFsysNames = Data.FSYS.defaultXDMenuFsysNames
            data.fsys.battlefieldFsysNames = Data.FSYS.defaultXDBattlefieldFsysNames
            data.fsys.commonFsysNames = Data.FSYS.defaultXDCommonFsysNames
            data.fsys.miscFsysNames = Data.FSYS.defaultXDMiscFsysNames
            data.fsys.sceneFsysNames = Data.FSYS.defaultXDSceneFsysNames
            data.fsys.characterImageFsysNames = ["chara_big", "chara_small"]
            data.fsys.archiveFileTypeFolders = [
                "poke_face": ["gtx": "/Assets/Images/Pokemon/Faces"],
                "poke_body": ["gtx": "/Assets/Images/Pokemon/PC Box", "atx": "/Assets/Images/Pokemon/PC Box"],
                "poke_dance": ["gtx": "/Assets/Images/Pokemon/Purify Chamber", "atx": "/Assets/Images/Pokemon/Purify Chamber"],
                "deck_archive": ["bin": "/Data/Decks"],
            ]
            data.fsys.archiveFileOverrides = [
                "common": [
                    "DeckData_DarkPokemon": "/Data/Decks",
                    "DeckData_DarkPokemon_EU": "/Data/Decks",
                    // common.rel hosts the shared game tables; route it
                    // to the data tree where the dedicated `commonRelDump`
                    // op picks it up.
                    "common": "/Assets/Data/Common",
                ],
            ]
        case .battleRevolution:
            data.fsys.fileTypeFolders = Data.FSYS.defaultPBRFileTypeFolders
            // The Wii Home Menu library, which is the console's, not the
            // game's. Mirrors its disc path under /Platform rather than
            // scattering by file type — see `platformDirectories`.
            data.fsys.platformDirectories = Data.FSYS.defaultPBRPlatformDirectories
            data.fsys.platformBaseFolder = "/Platform"
            // Every PBR archive leaves the header's group-ID word zero and
            // lets the table of contents carry the ID.
            data.fsys.writesGroupIDInHeader = false
            // Self-contained sets grouped one folder per archive.
            data.fsys.archiveSubfolderRoutes = [
                .init(matchPrefix: "pkx_",      baseFolder: "/Assets/Models/Pokemon", stripPrefix: "pkx_"),
                .init(matchPrefix: "wzx_waza_", baseFolder: "/Assets/Effects/Moves",   stripPrefix: "wzx_waza_"),
                .init(matchPrefix: "bf_",       baseFolder: "/Assets/Battlefields",    stripPrefix: "bf_"),
            ]
            data.fsys.archiveFileTypeFolders = [
                // The shared data tables; the typed-table dump reads them here.
                "common":       ["bin": "/Data/Common"],
                // Pokémon face icons and body sprites → their own image folders.
                "menu_face":    ["gtx": "/Assets/Images/Pokemon/Faces"],
                "menu_pokemon": ["gtx": "/Assets/Images/Pokemon/Sprites"],
            ]
            // Images that match no specific route group under their archive
            // name, e.g. common's textures → /Assets/Images/common.
            data.fsys.imagesFallbackBaseFolder = "/Assets/Images"
            // common.fsys (and deck.fsys) tables pad their regions to 0x10.
            data.fsys.dataTableRegionAlignment = 0x10
            // Messages sort by the language code in each MESG binary (+0x0C).
            data.fsys.messagesLanguageBaseFolder = "/Data/Text/Messages"
            data.fsys.messagesLanguageCodes = [
                "USUK": "English",
                "FRFR": "French",
                "GRGR": "German",
                "ITIT": "Italian",
                "SPSP": "Spanish",
                "JPJP": "Japanese",
            ]
        }

        let structs = GeniusSonorityEngine.Structs(unchecked: structsList)
        let enums = GeniusSonorityEngine.Enums(unchecked: enumList)
        return try! .init(data: data, enums: enums, structs: structs)
    }

    // MARK: - Folder Resolution

    /// Result of folder resolution, including optional language subfolder
    public struct FolderResolution {
        public let folder: Folder
        public let languageSubfolder: String?

        public var resolvedFolder: Folder {
            guard let lang = languageSubfolder else { return folder }
            return folder.folder(lang)
        }
    }

    /// Strips a known language suffix from an FSYS archive name.
    /// Returns (baseName, languageName?) e.g. ("pda_menu", "French") for "pda_menu_fr"
    private func stripLanguageSuffix(from name: String) -> (baseName: String, language: String?) {
        for (suffix, language) in data.fsys.languageSuffixes {
            if name.hasSuffix(suffix) {
                return (String(name.dropLast(suffix.count)), language)
            }
        }
        return (name, nil)
    }

    /// Resolves the destination folder for an extracted file based on its type,
    /// the entry filename, and the parent FSYS archive name.
    ///
    /// Resolution priority:
    /// 0. Fonts, always to the fonts folder (the font ops work over it)
    /// 1. Per-archive subfolder route (PBR model/effect sets)
    /// 2. Per-file override (archiveFileOverrides)
    /// 3. Misc / scene FSYS override (whole archive to its own folder)
    /// 4. Character image FSYS override (gtx/atx only)
    /// 5. Menu FSYS image override (gtx/atx only)
    /// 6. Menu FSYS flash-menu override (gsw only)
    /// 7. Common FSYS image override (gtx/atx only)
    /// 8. Battlefield FSYS override (models → Battlefields, scripts → Battlefields)
    /// 9. MSG routing by FSYS category (map/menu/misc)
    /// 10. Archive-specific override by file type
    /// 11. Archive-specific override by entry file extension
    /// 12. Image fallback
    /// 13. Standard file type mapping (also checks entry file extension)
    /// 14. Default folder
    public func resolveFolder(
        forFileType fileType: String,
        entryFilename: String,
        archiveName: String
    ) -> FolderResolution {
        let entryExtension = File(entryFilename).fileType
        // `entryFilename` here is a bare basename (no slashes) — e.g.
        // `common.rel`. `File(_).fileName` walks for the last slash and
        // returns "" when none is present, so use the raw filename
        // rather than going through `File` for the override-lookup key.
        let entryName = entryFilename.withoutExtensions
        let fsys = data.fsys
        let (baseName, language) = stripLanguageSuffix(from: archiveName)

        let isImage = fileType == "gtx" || fileType == "atx"
        let isModel = fileType == "dat" || fileType == "col" || fileType == "mdat" || fileType == "dats"

        // 0. A font is always filed under the fonts folder, whichever archive
        // it came from. `dumpFonts` and `pbrFontsDump` work over that one
        // folder, so a font routed into a per-archive folder by the rules
        // below would silently drop out of the font pipeline — 7 of XD US's
        // fonts and 1 of Colosseum's are in archives those rules catch. The
        // hazard those rules guard against, two builds of one file landing on
        // each other, is already handled for fonts: each carries its entry
        // index (see `projectFilename`) and the unpack splits whatever still
        // collides.
        if fileType == "fnt", let fontsFolder = fsys.fileTypeFolders["fnt"] {
            return FolderResolution(folder: fontsFolder, languageSubfolder: language)
        }

        // 1. Per-archive subfolder route: the whole archive is one set (a
        // Pokémon model, a move effect, a battlefield) and groups into a
        // single subfolder rather than scattering by file type. Optional
        // engine data — nil (Colo/XD) skips straight to the type routing.
        if let routes = fsys.archiveSubfolderRoutes,
           let route = routes.first(where: { baseName.hasPrefix($0.matchPrefix) }) {
            let subName: String
            if let strip = route.stripPrefix, baseName.hasPrefix(strip) {
                subName = String(baseName.dropFirst(strip.count))
            } else {
                subName = baseName
            }
            return FolderResolution(folder: route.baseFolder.folder(subName), languageSubfolder: language)
        }

        // 2. Per-file override for specific entries in specific archives
        if let archiveOverrides = fsys.archiveFileOverrides[baseName],
           let folder = archiveOverrides[entryName] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // 3. Misc FSYS: the whole archive goes to a folder of its own.
        //
        // These carry their own versions of files the real maps and menus
        // also ship, so routing them by type drops them on top of the ones
        // the game loads — `worldmap`'s map snapshots landed on `world_map`'s,
        // and the cave archives' Poké Ball models on `people_archive`'s.
        if fsys.miscFsysNames.contains(baseName) {
            return FolderResolution(
                folder: fsys.miscArchivesBaseFolder.folder(baseName),
                languageSubfolder: language
            )
        }

        // 3b. Scene FSYS: same treatment, own base folder. A cutscene stages
        // a place the game already ships and brings its own build of it —
        // `ending_Scene04` has its own `M6_out` map model, the move demos
        // their own `worldmap_menu.rel`.
        if fsys.sceneFsysNames.contains(baseName) {
            return FolderResolution(
                folder: fsys.sceneArchivesBaseFolder.folder(baseName),
                languageSubfolder: language
            )
        }

        // 4. Character image FSYS
        if isImage && fsys.characterImageFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.characterImagesFolder, languageSubfolder: language)
        }

        // 5. Menu FSYS images
        if isImage && fsys.menuFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.menuImagesBaseFolder.folder(baseName), languageSubfolder: language)
        }

        // 6. Menu FSYS flash menus — same reasoning as the images above, and
        // the same fix: two menu archives ship different `.gsw` under one
        // name (`bingo_bingo_bar_00` in both `bingo_menu` and `flashmenu`),
        // so each archive keeps its own folder instead of sharing one.
        if fileType == "gsw" && fsys.menuFsysNames.contains(baseName),
           let flashFolder = fsys.fileTypeFolders["gsw"] {
            return FolderResolution(folder: flashFolder.folder(baseName), languageSubfolder: language)
        }

        // 7. Common FSYS images
        if isImage && fsys.commonFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.commonImagesFolder, languageSubfolder: language)
        }

        // 8. Battlefield FSYS
        if fsys.battlefieldFsysNames.contains(baseName) {
            if isModel {
                return FolderResolution(folder: fsys.battlefieldModelsFolder, languageSubfolder: language)
            }
            if fileType == "scd" {
                return FolderResolution(folder: fsys.battlefieldScriptsFolder, languageSubfolder: language)
            }
            // Other file types from battlefields fall through to standard routing
        }

        // 9. MSG routing by FSYS category
        if fileType == "msg" {
            if fsys.mapFsysNames.contains(baseName) || fsys.battlefieldFsysNames.contains(baseName) {
                return FolderResolution(folder: fsys.msgMapFolder, languageSubfolder: language)
            } else if fsys.menuFsysNames.contains(baseName) {
                return FolderResolution(folder: fsys.msgMenuFolder, languageSubfolder: language)
            } else {
                return FolderResolution(folder: fsys.msgMiscFolder, languageSubfolder: language)
            }
        }

        // 10. Archive-specific override matching file type
        if let archiveOverrides = fsys.archiveFileTypeFolders[baseName] {
            if let folder = archiveOverrides[fileType] {
                return FolderResolution(folder: folder, languageSubfolder: language)
            }
            // 11. Archive-specific override matching entry file extension
            if let entryExtension, entryExtension != fileType, let folder = archiveOverrides[entryExtension] {
                return FolderResolution(folder: folder, languageSubfolder: language)
            }
        }

        // 12. Image fallback: an image that matched no specific route groups
        // under its archive name rather than a single shared folder.
        if isImage, !baseName.isEmpty, let base = fsys.imagesFallbackBaseFolder {
            return FolderResolution(folder: base.folder(baseName), languageSubfolder: language)
        }

        // 13. Standard file type mapping
        if let folder = fsys.fileTypeFolders[fileType] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // Check entry extension (handles pool/proj suffixed files)
        if let entryExtension, entryExtension != fileType, let folder = fsys.fileTypeFolders[entryExtension] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // 14. Default
        return FolderResolution(folder: fsys.defaultFolder, languageSubfolder: language)
    }

    /// The per-archive subfolder route whose prefix matches this archive, if
    /// any. Used by the unpack to decide subfolder grouping and whether the
    /// archive's textures stay raw.
    public func archiveSubfolderRoute(forArchive archiveName: String) -> Data.FSYS.ArchiveSubfolderRoute? {
        guard let routes = data.fsys.archiveSubfolderRoutes else { return nil }
        let (baseName, _) = stripLanguageSuffix(from: archiveName)
        return routes.first { baseName.hasPrefix($0.matchPrefix) }
    }

    /// Language-sorted destination folder for a MSG entry, derived from the
    /// 4-char language code the MESG binary stores at +0x0C (PBR). Returns nil
    /// when the engine isn't configured for language routing (Colo/XD) or the
    /// data isn't a recognisable MESG, so the caller falls back to category
    /// routing.
    public func messageLanguageFolder(forMessageData messageData: GoDData) -> Folder? {
        guard let base = data.fsys.messagesLanguageBaseFolder,
              let codes = data.fsys.messagesLanguageCodes,
              messageData.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) == "MESG",
              let code = messageData.readString(atAddress: 0x0C, format: .utf8, maxCharacters: 4)
        else { return nil }
        return base.folder(codes[code] ?? code)
    }

    /// The on-disk name for an extracted entry. An entry whose stored name is
    /// the engine's scrubbed placeholder is named after the archive it came
    /// from plus its index, which is unique within the archive and — because
    /// the archive stem is in it — across the disc; any other entry keeps its
    /// derived pretty `filename`.
    ///
    /// `indexed` gives a *named* entry the same index suffix. An entry name
    /// is only unique inside its own archive, and is usually the archive's
    /// own name rather than the file's, so it can't identify a file that is
    /// pooled across archives: on the XD US disc three names — `fight`,
    /// `world_map` and `M2_enter_1F` — are each claimed by two different
    /// fonts. The index distinguishes those without inventing a name.
    ///
    /// The archive's own stem is used, not the language-stripped base the
    /// folder routing works from: stripping makes `battle_disk_fr` and
    /// `battle_disk_ge` produce the same names, which clashes for 27 names on
    /// the XD US disc and 84 on PAL. With the stem, no name collides on any
    /// of the six GameCube discs, and no PBR archive carries a language
    /// suffix at all, so nothing there changes shape.
    public func projectFilename(
        forEntryNamed entryName: String,
        filename: String,
        index: Int,
        archiveName: String,
        indexed: Bool = false
    ) -> String {
        let placeholder = data.fsys.scrubbedFilenamePlaceholderValue
        let ext = File(filename).fileType.map { "." + $0 } ?? ""
        let suffix = "_" + String(format: "%03d", index) + ext
        // A nameless entry can still carry a full filename the packer did
        // fill in — 154 of XD US's do — and that real name beats anything
        // derived. The pretty `filename` already prefers it, so what decides
        // this is whether *that* came out as the placeholder too.
        guard entryName == placeholder, filename.withoutExtensions == placeholder else {
            return indexed ? filename.withoutExtensions + suffix : filename
        }
        return archiveName + suffix
    }
}
