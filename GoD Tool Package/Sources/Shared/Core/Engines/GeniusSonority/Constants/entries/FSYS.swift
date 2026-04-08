import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct FSYS: Codable {
        public private(set) var magicBytes = "FSYS"
        public internal(set) var fileMetaDataPadding = 0x40 // 0x20 in Colosseum but value is only aesthetic
        public private(set) var fileExtensionSuffixes = [
            "pool",
            "proj",
            "sdir",
            "rel"
        ]

        public internal(set) var fileTypeReplacements = [String: String]() // replace the file extension for the final file name

        /// Suffixes to strip from extracted filenames (before the extension).
        /// e.g. `["_col", "_cam", "_scd"]` will rename `B1_1_col.ccd` → `B1_1.ccd`
        public internal(set) var fileNameSuffixReplacements: [String] = ["_col", "_cam", "_scd"]

        public private(set) var GSfsysFile = File("/files/GSfsys.toc")

        /// Fallback folder for file types not in `fileTypeFolders`
        public internal(set) var defaultFolder: Folder = "/Assets/Misc"

        /// Maps a file type string (e.g. "msg", "gtx") to its destination folder during dump
        public internal(set) var fileTypeFolders: [String: Folder] = FSYS.defaultFileTypeFolders

        /// Maps an FSYS archive name to per-file-type folder overrides.
        /// e.g. `["poke_face": ["gtx": "/Assets/Images/Pokemon/Faces"]]`
        /// Checked before `fileTypeFolders` during folder resolution.
        public internal(set) var archiveFileTypeFolders: [String: [String: Folder]] = [:]

        /// Folder where FSYS archive registry JSON files are written during dump
        public internal(set) var archivesFolder: Folder = "/Archives"

        /// Folder where relocatable modules are written during dump
        public internal(set) var relocatableModulesFolder: Folder = "/Data/Relocatable Modules"

        /// Folder where disassembled code is written
        public internal(set) var codeFolder: Folder = "/Code"

        // MARK: - FSYS Category Lists

        /// FSYS archives identified as game maps (populated per-game in defaultEngine)
        public internal(set) var mapFsysNames: [String] = []

        /// FSYS archives identified as menus (populated per-game in defaultEngine)
        public internal(set) var menuFsysNames: [String] = []

        /// FSYS archives identified as battlefields (populated per-game in defaultEngine)
        public internal(set) var battlefieldFsysNames: [String] = []

        /// FSYS archives containing shared/common game data
        public internal(set) var commonFsysNames: [String] = []

        /// FSYS archives whose images route to the character images folder
        public internal(set) var characterImageFsysNames: [String] = []

        // MARK: - Language Routing

        /// Language suffix → subfolder name mapping for localized FSYS archives
        public internal(set) var languageSuffixes: [String: String] = [
            "_fr": "French",
            "_ge": "German",
            "_it": "Italian",
            "_sp": "Spanish",
        ]

        // MARK: - Category-Specific Target Folders

        /// Folder for character images (from chara_big, chara_small, etc.)
        public internal(set) var characterImagesFolder: Folder = "/Assets/Images/Characters"

        /// Base folder for menu images; the FSYS name is appended as a subfolder
        public internal(set) var menuImagesBaseFolder: Folder = "/Assets/Images/Menus"

        /// Folder for battlefield models
        public internal(set) var battlefieldModelsFolder: Folder = "/Assets/Models/Battlefields"

        /// Folder for battlefield scripts
        public internal(set) var battlefieldScriptsFolder: Folder = "/Assets/Scripts/Battlefields"

        /// MSG files from map FSYS archives
        public internal(set) var msgMapFolder: Folder = "/Assets/Text/Messages/Maps"

        /// MSG files from menu FSYS archives
        public internal(set) var msgMenuFolder: Folder = "/Assets/Text/Messages/Menus"

        /// MSG files from all other FSYS archives
        public internal(set) var msgMiscFolder: Folder = "/Assets/Text/Messages/Misc"

        /// Folder for images from common FSYS archives
        public internal(set) var commonImagesFolder: Folder = "/Assets/Images/Common"

        /// Per-file routing overrides within specific FSYS archives.
        /// Maps `archiveName -> [entryName -> targetFolder]`.
        /// Checked before all other routing for exact filename matches.
        public internal(set) var archiveFileOverrides: [String: [String: Folder]] = [:]

        // MARK: - Default File Type Folders

        public static let defaultFileTypeFolders: [String: Folder] = [
            "mdat": "/Assets/Models/Maps",
            "dat":  "/Assets/Models/Characters And Objects",
            "col":  "/Assets/Models/Maps",
            "samp": "/Assets/Sounds/Sequenced",
            "msg":  "/Assets/Text/Messages",
            "fnt":  "/Assets/Text/Fonts",
            "scd":  "/Assets/Scripts",
            "dats": "/Assets/Models/Characters And Objects",
            "gtx":  "/Assets/Images/Misc",
            "cam":  "/Assets/Models/Cameras",
            "pkx":  "/Assets/Models/Battle Models",
            "wzx":  "/Assets/Models/Effects",
            "isd":  "/Assets/Sounds/Streamed",
            "ish":  "/Assets/Sounds/Streamed",
            "thh":  "/Assets/Videos",
            "thd":  "/Assets/Videos",
            "gsw":  "/Assets/Flash Menus",
            "atx":  "/Assets/Images/Misc",
            "pool": "/Assets/Sounds/Streamed",
            "proj": "/Assets/Sounds/Streamed",
            "sdir": "/Assets/Sounds/Sequenced",
            "gpt1": "/Assets/Models/Particles",
            "rel":  "/Data/Relocatable Modules",
            "drel": "/Data/Relocatable Modules",
        ]
    }
}
