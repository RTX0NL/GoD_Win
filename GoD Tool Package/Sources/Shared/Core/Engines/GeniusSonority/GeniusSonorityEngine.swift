@_exported import GoDEngine
import GoDFoundation
import Structs

public enum GSGame {
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
        var structsList = GeniusSonorityEngine.Structs.allItems
        var enumList = GeniusSonorityEngine.Enums.allItems

        enumList.removeAll(where: {
            ["FileTypes", "FsysGroupIDs"].contains($0.name)
        })
        structsList.removeAll(where: {
            ["FsysTOCEntry"].contains($0.name)
        })

        switch game {
        case .colosseum:
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
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x201
            structsList.append(Structs.Defaults.fsysTOCEntryStructFull)
            enumList.append(Enums.Defaults.fileTypesColoXDEnum)
            enumList.append(fsysTOC?.enumeration ?? Enums.Defaults.fsysGroupIDsXDEnum)
            data.fsys.fileTypeReplacements = [
                "mdat": "dat"
            ]
        case .battleRevolution:
            data.fsys.fileMetaDataPadding = 0x40
            data.toc.unknown = 0x251
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
            break
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
    /// 1. Strip language suffix from archive name
    /// 2. Per-file override (archiveFileOverrides)
    /// 3. Character image FSYS override (gtx/atx only)
    /// 4. Menu FSYS image override (gtx/atx only)
    /// 5. Common FSYS image override (gtx/atx only)
    /// 6. Battlefield FSYS override (models → Battlefields, scripts → Battlefields)
    /// 7. MSG routing by FSYS category (map/menu/misc)
    /// 8. Archive-specific override by file type
    /// 9. Archive-specific override by entry file extension
    /// 10. Standard file type mapping (also checks entry file extension)
    /// 11. Default folder
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

        // 1. Per-file override for specific entries in specific archives
        if let archiveOverrides = fsys.archiveFileOverrides[baseName],
           let folder = archiveOverrides[entryName] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // 2. Character image FSYS
        if isImage && fsys.characterImageFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.characterImagesFolder, languageSubfolder: language)
        }

        // 3. Menu FSYS images
        if isImage && fsys.menuFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.menuImagesBaseFolder.folder(baseName), languageSubfolder: language)
        }

        // 4. Common FSYS images
        if isImage && fsys.commonFsysNames.contains(baseName) {
            return FolderResolution(folder: fsys.commonImagesFolder, languageSubfolder: language)
        }

        // 5. Battlefield FSYS
        if fsys.battlefieldFsysNames.contains(baseName) {
            if isModel {
                return FolderResolution(folder: fsys.battlefieldModelsFolder, languageSubfolder: language)
            }
            if fileType == "scd" {
                return FolderResolution(folder: fsys.battlefieldScriptsFolder, languageSubfolder: language)
            }
            // Other file types from battlefields fall through to standard routing
        }

        // 6. MSG routing by FSYS category
        if fileType == "msg" {
            if fsys.mapFsysNames.contains(baseName) || fsys.battlefieldFsysNames.contains(baseName) {
                return FolderResolution(folder: fsys.msgMapFolder, languageSubfolder: language)
            } else if fsys.menuFsysNames.contains(baseName) {
                return FolderResolution(folder: fsys.msgMenuFolder, languageSubfolder: language)
            } else {
                return FolderResolution(folder: fsys.msgMiscFolder, languageSubfolder: language)
            }
        }

        // 5. Archive-specific override matching file type
        if let archiveOverrides = fsys.archiveFileTypeFolders[baseName] {
            if let folder = archiveOverrides[fileType] {
                return FolderResolution(folder: folder, languageSubfolder: language)
            }
            // 6. Archive-specific override matching entry file extension
            if let entryExtension, entryExtension != fileType, let folder = archiveOverrides[entryExtension] {
                return FolderResolution(folder: folder, languageSubfolder: language)
            }
        }

        // 7. Standard file type mapping
        if let folder = fsys.fileTypeFolders[fileType] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // Check entry extension (handles pool/proj suffixed files)
        if let entryExtension, entryExtension != fileType, let folder = fsys.fileTypeFolders[entryExtension] {
            return FolderResolution(folder: folder, languageSubfolder: language)
        }

        // 8. Default
        return FolderResolution(folder: fsys.defaultFolder, languageSubfolder: language)
    }
}
