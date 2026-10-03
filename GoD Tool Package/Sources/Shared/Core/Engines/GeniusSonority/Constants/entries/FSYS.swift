import GoDFoundation

extension GeniusSonorityEngine.Data {
    public struct FSYS: Codable {
        /// A constant byte run the game writes inside each entry-metadata
        /// block, past the fields `FSYSFileMetaData` models. It carries no
        /// data — it's the packer's filler — but reproducing it is what
        /// makes a repacked archive byte-identical to the original.
        public struct MetaDataFill: Codable, Equatable {
            /// Offset of the run within the entry-metadata block.
            public var offset: Int
            public var length: Int
            public var byte: Int

            public init(offset: Int, length: Int, byte: Int) {
                self.offset = offset
                self.length = length
                self.byte = byte
            }
        }

        public private(set) var magicBytes = "FSYS"
        public internal(set) var fileMetaDataPadding = 0x40 // 0x20 in Colosseum

        /// Alignment of the regions inside a struct-typed data-table entry
        /// (see `FSYSRegistry.DataTableMetadata`). The entry array is padded
        /// up to this before the trailing name/relocation tables. A property
        /// of the FSYS layer since the reassembly lives here, not per-entry.
        /// Optional so older serialized engines still decode; `nil` means the
        /// `dataTableRegionAlignmentValue` fallback.
        public internal(set) var dataTableRegionAlignment: Int? = nil

        /// The effective region alignment, with the format's default when the
        /// engine doesn't pin one.
        public var dataTableRegionAlignmentValue: Int { dataTableRegionAlignment ?? 0x10 }

        /// Filler the game's packer leaves in each entry-metadata block.
        /// Colosseum writes 12 bytes of `0x11` at +0x34 (verified constant
        /// across 1028 entries in 299 US archives); XD zeroes the whole
        /// region, so it leaves this `nil`.
        public internal(set) var fileMetaDataFill: MetaDataFill? = nil


        /// Suffixes to strip from extracted filenames and use as extension instead.
        /// e.g. `["pool", "proj", "sdir", "rel"]` will rename `common_rel` → `common.rel`
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

        /// Archives that are a self-contained oddity rather than a member of
        /// one of the categories above — test and debug data, the bonus-disc
        /// menus, the leftover Colosseum battle maps.
        ///
        /// Everything they hold goes to one folder of their own under
        /// `miscArchivesBaseFolder`, whatever its file type. They carry
        /// their own variants of files the real maps and menus also ship
        /// (`worldmap`'s map snapshots, the cave archives' Poké Ball models),
        /// so scattering them by type drops them on top of the versions the
        /// game actually uses.
        public internal(set) var miscFsysNames: [String] = []

        /// Cutscene and camera-demo archives. Each stages a place the game
        /// already ships and brings its own build of that place's files, so
        /// like `miscFsysNames` the whole archive goes to a folder of its own
        /// rather than scattering by type onto the live versions.
        public internal(set) var sceneFsysNames: [String] = []

        // MARK: - Header Fields

        /// Whether the archive's own header carries the group ID, or leaves
        /// the word zero.
        ///
        /// The disc's table of contents is the only authority on what an
        /// archive's group ID *is* (`FSYSRegistry.groupID`); this is purely
        /// about whether the header repeats it. The three games disagree, and
        /// the disagreement is total rather than a matter of stray outliers:
        /// XD US populates the word in 2,533 of its 2,540 archives, while
        /// Battle Revolution leaves it zero in **all 1,095** of its own and
        /// reads the ID from the table instead. Writing the table's value into
        /// a PBR header would therefore change every archive on the disc away
        /// from the game's own convention, which is why this is engine data
        /// and not a fixed rule.
        ///
        /// Optional so engine folders serialized before this existed decode;
        /// `writesGroupIDInHeaderValue` supplies the default.
        public internal(set) var writesGroupIDInHeader: Bool? = nil

        /// The effective setting. Defaults to `true` — a header that repeats
        /// the ID is the Genius Sonority norm, and Colosseum and XD both do it.
        public var writesGroupIDInHeaderValue: Bool { writesGroupIDInHeader ?? true }

        // MARK: - Platform Directories

        /// Disc directories holding console platform data rather than game
        /// content — libraries the console's SDK ships, which every title on
        /// the platform carries its own copy of.
        ///
        /// Their files don't route by file type at all. A platform directory
        /// mirrors its disc path under `platformBaseFolder`, so
        /// `hb/HomeButton2/homeBtn.arc` becomes
        /// `/Platform/hb/HomeButton2/homeBtn.arc.json`. Two reasons: these
        /// aren't the game's assets and don't belong beside them, and a disc
        /// commonly ships several versions of one library side by side under
        /// sibling directories, so the directory is what tells two otherwise
        /// identically named files apart.
        ///
        /// A directory nested inside a listed one counts as well, so listing
        /// `hb` catches every `hb/HomeButtonN` without naming them.
        ///
        /// Optional so engine folders serialized before this existed decode.
        public internal(set) var platformDirectories: [String]? = nil

        /// Where platform files mirror their disc path — a sibling of
        /// `/Assets`, not a folder inside it, because platform data isn't a
        /// category of game asset. Optional for back-compatible decode;
        /// `platformBaseFolderValue` supplies the default.
        public internal(set) var platformBaseFolder: Folder? = nil

        /// The effective platform folder, with the default when the engine
        /// doesn't pin one.
        public var platformBaseFolderValue: Folder { platformBaseFolder ?? "/Platform" }

        /// Whether a disc-relative directory is one of `platformDirectories`,
        /// or sits inside one. `nil` and `[]` both mean the game declares no
        /// platform data, which is the Colosseum and XD case — the GameCube
        /// has no equivalent of the Home Menu.
        public func isPlatformDirectory(_ directory: String) -> Bool {
            guard let platformDirectories else { return false }
            return platformDirectories.contains {
                directory == $0 || directory.hasPrefix($0 + "/")
            }
        }

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

        /// Where a `miscFsysNames` archive's own folder is created, a sibling
        /// of the menu and model folders rather than a category of its own.
        public internal(set) var miscArchivesBaseFolder: Folder = "/Assets/Misc"

        /// Where a `sceneFsysNames` archive's own folder is created.
        public internal(set) var sceneArchivesBaseFolder: Folder = "/Assets/Scenes"

        public internal(set) var battlefieldModelsFolder: Folder = "/Assets/Models/Battlefields"

        public internal(set) var battlefieldScriptsFolder: Folder = "/Assets/Scripts/Battlefields"

        /// MSG files from map FSYS archives
        public internal(set) var msgMapFolder: Folder = "/Data/Text/Messages/Maps"

        /// MSG files from menu FSYS archives
        public internal(set) var msgMenuFolder: Folder = "/Data/Text/Messages/Menus"

        /// MSG files from all other FSYS archives
        public internal(set) var msgMiscFolder: Folder = "/Data/Text/Messages/Misc"

        /// Folder for images from common FSYS archives
        public internal(set) var commonImagesFolder: Folder = "/Assets/Images/Common"

        /// Per-file routing overrides within specific FSYS archives.
        /// Maps `archiveName -> [entryName -> targetFolder]`.
        /// Checked before all other routing for exact filename matches.
        public internal(set) var archiveFileOverrides: [String: [String: Folder]] = [:]

        // MARK: - Per-archive subfolder routing (PBR)

        /// Routes an entire FSYS archive's contents into a per-archive
        /// subfolder — used where one archive is a self-contained set (a
        /// Pokémon model, a move effect, a battlefield) that should stay
        /// grouped rather than scattered by file type.
        public struct ArchiveSubfolderRoute: Codable, Equatable {
            /// Archive-name prefix that selects this route (e.g. `pkx_`).
            public var matchPrefix: String
            /// Folder the per-archive subfolder is created under.
            public var baseFolder: Folder
            /// Prefix removed from the archive name to name the subfolder,
            /// so `pkx_025` with `stripPrefix: "pkx_"` becomes `025`. Nil
            /// keeps the whole archive name.
            public var stripPrefix: String?

            public init(matchPrefix: String, baseFolder: Folder, stripPrefix: String?) {
                self.matchPrefix = matchPrefix
                self.baseFolder = baseFolder
                self.stripPrefix = stripPrefix
            }
        }

        /// Per-archive subfolder routes, checked before type-based routing.
        /// Optional so existing serialized Colo/XD engines still decode.
        public internal(set) var archiveSubfolderRoutes: [ArchiveSubfolderRoute]? = nil

        /// Entry filename the game writes for unnamed entries. When an entry
        /// carries this name it's treated as unnamed, so the project name
        /// comes from the archive and the entry's index instead. Optional for
        /// back-compatible decode.
        public internal(set) var scrubbedFilenamePlaceholder: String? = nil

        /// The effective placeholder, with the packer's own value when the
        /// engine doesn't pin one.
        ///
        /// Genius Sonority's packer printed an absent filename through `%s`
        /// with a null pointer, so every game it built stores the literal
        /// `(null)` — all of PBR's entries, and 1105–2104 per XD disc
        /// (every streamed sound, the movies, the flash menus and some
        /// textures). The fallback is here rather than only in the engine
        /// defaults so an engine folder serialized before this was recorded
        /// still names those entries correctly.
        public var scrubbedFilenamePlaceholderValue: String {
            scrubbedFilenamePlaceholder ?? "(null)"
        }

        // MARK: - Message language routing (PBR)

        /// When set, MSG entries route to `<base>/<language>` using the
        /// language code embedded in the message binary rather than the
        /// category-based `msg*Folder` routing. PBR's MESG header stores a
        /// 4-char code at +0x0C (e.g. `USUK`); Colo/XD leave this nil and keep
        /// their category routing.
        public internal(set) var messagesLanguageBaseFolder: Folder? = nil

        /// Maps a message-binary language code to its folder name, e.g.
        /// `["USUK": "English"]`. An unmapped code falls back to the raw code.
        public internal(set) var messagesLanguageCodes: [String: String]? = nil

        /// When set, an image (`gtx`/`atx`) that matched no more specific route
        /// lands in `<base>/<archive name>` instead of a single shared folder,
        /// so each archive's images stay grouped. Optional — Colo/XD leave it
        /// nil and keep the flat `fileTypeFolders` image folder.
        public internal(set) var imagesFallbackBaseFolder: Folder? = nil

        // MARK: - Default File Type Folders

        public static let defaultFileTypeFolders: [String: Folder] = [
            "mdat": "/Assets/Models/Maps",
            "dat":  "/Assets/Models/Characters And Objects",
            "col":  "/Assets/Models/Maps",
            "samp": "/Assets/Sounds/Sequenced",
            "msg":  "/Data/Text/Messages",
            "fnt":  "/Data/Text/Fonts",
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

        /// PBR uses a different FileTypes namespace, so it gets its own
        /// type→folder defaults. Model archives (pkx/trainers) and effect
        /// archives (wzx_waza) are grouped per-archive by `archiveSubfolderRoutes`
        /// before these apply; these catch standalone entries and the
        /// non-grouped archives (menus, decks, text).
        public static let defaultPBRFileTypeFolders: [String: Folder] = [
            "sdr":  "/Assets/Models/Characters",
            "odr":  "/Assets/Models/Objects",
            "mdr":  "/Assets/Models/Materials",
            "gpd":  "/Assets/Effects/Particles",
            "gfl":  "/Assets/Effects/Lighting",
            "efsq": "/Assets/Effects",
            "gtx":  "/Assets/Images/Misc",
            "scd":  "/Assets/Scripts",
            "msg":  "/Data/Text/Messages",
            "fnt":  "/Data/Text/Fonts",
            "mnr":  "/Assets/Menus",
            "thh":  "/Assets/Videos",
            "thd":  "/Assets/Videos",
            "dckp": "/Data/Decks/Pokemon",
            "dckt": "/Data/Decks/Trainer",
            "dcka": "/Data/Decks/AI",
            "bin":  "/Assets/Misc",
            // Loose (non-FSYS) disc files under files/: PBR streams music as
            // standalone .brstm rather than packing it, plus a few DS-style
            // archives and Home-menu resources.
            "brstm": "/Assets/Sounds/Streamed",
            "brsar": "/Assets/Sounds",
            "narc":  "/Assets/Archives",
            "arc":   "/Assets/Archives",
        ]
    }
}
