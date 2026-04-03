import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct FSYS: Codable {
        public private(set) var magicBytes = "FSYS"
        public internal(set) var fileMetaDataPadding = 0x40 // 0x20 in Colosseum but value is only aesthetic
        public private(set) var fileExtensionSuffixes = [
            "pool",
            "proj",
            "sdir"
        ]

        public internal(set) var fileTypeReplacements = [String: String]() // replace the file extension for the final file name

        public private(set) var GSfsysFile = File("/files/GSfsys.toc")

        /// Fallback folder for file types not in `fileTypeFolders`
        public internal(set) var defaultFolder: Folder = "/Assets/Misc"

        /// Maps a file type string (e.g. "msg", "gtx") to its destination folder during dump
        public internal(set) var fileTypeFolders: [String: Folder] = FSYS.defaultFileTypeFolders

        /// Maps an FSYS archive name to per-file-type folder overrides.
        /// e.g. `["poke_face": ["gtx": "/Assets/Images/pokemon/faces"]]`
        /// Checked before `fileTypeFolders` during folder resolution.
        public internal(set) var archiveFileTypeFolders: [String: [String: Folder]] = [:]

        public static let defaultFileTypeFolders: [String: Folder] = [
            "mdat": "/Assets/Models/Maps/models",
            "dat":  "/Assets/Models/characters-and-objects",
            "col":  "/Assets/Models/Maps/models",
            "samp": "/Assets/Sounds/sound_fonts",
            "msg":  "/Assets/Text/messages",
            "fnt":  "/Assets/Text/fonts",
            "scd":  "/Data/Maps",
            "dats": "/Assets/Models/characters-and-objects",
            "gtx":  "/Assets/Images",
            "cam":  "/Assets/Models/cameras",
            "pkx":  "/Assets/Models/battle_models",
            "wzx":  "/Assets/Models/effects",
            "isd":  "/Assets/Sounds/streamed",
            "ish":  "/Assets/Sounds/streamed",
            "thh":  "/Assets/Videos",
            "thd":  "/Assets/Videos",
            "gsw":  "/Assets/Flash-menus",
            "atx":  "/Assets/Images",
            "pool": "/Assets/Sounds/streamed",
            "proj": "/Assets/Sounds/streamed",
        ]
    }
}
