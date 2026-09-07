import GoDFoundation
import GoDEngine
import ScriptDecompiler

public extension ColosseumEngine {
    struct Data: Codable {
        /// Script built-in function definitions keyed by function ID (as string)
        public var scriptBuiltInFunctions: [String: ScriptFunctionDef]

        /// Filesystem paths (relative to the engine folder) for the
        /// bundled reference resources: REL typemap, symbol indexes, and
        /// per-region DOL symbol maps. See `XDEngine.Data.Resources` for
        /// the shape rationale.
        public var resources: Resources

        /// Save-data sections inside a Colo save slot, in physical
        /// order from the slot body. Position in the array is the
        /// section's logical index (used by `sectionStructTypes`).
        ///
        /// Colo has no in-slot TOC like XD — sections sit at fixed
        /// offsets dictated by the engine itself. Since the array is
        /// sequential with no gaps, each section's offset is the
        /// cumulative sum of preceding sections' lengths added to
        /// the body base (`bodyBaseOffset` below). Each section's
        /// length comes from its struct binding via
        /// `sectionStructTypes` → `engine.structs`. Both offset and
        /// length are therefore derivable from `saveSections` +
        /// `sectionStructTypes` + the registered structs alone.
        ///
        /// Defaults reproduce PKHeX's `SAV3Colosseum.cs` partition,
        /// extended with two opaque placeholders for the regions
        /// PKHeX doesn't name: `BattleData` (the gap between PCBox
        /// and Daycare) and `Tail` (the trailing region after
        /// StrategyMemo, up to the cipher's 0x20-byte hash trailer).
        public var saveSections: [SaveSectionSpec] = Self.defaultSaveSections

        static let defaultSaveSections: [SaveSectionSpec] = [
            .structInstance(name: "Config"),       // 0 — slot+0x08, len 0x70    → ColoSaveConfig
            .structInstance(name: "Trainer"),      // 1 — slot+0x78, len 0xB18   → ColoSaveTrainer (OT + party of 6)
            .structInstance(name: "PCBox"),        // 2 — slot+0xB90, len 0x6DEC → ColoSavePCBox (3 boxes × 30)
            .structInstance(name: "PCItemsAndMail"),// 3 — slot+0x797C, len 0x7F4 → ColoSavePCItemsMailbox (PC items + PDA mailbox)
            .structInstance(name: "Daycare"),      // 4 — slot+0x8170, len 0x140 → ColoSaveDaycare
            .structInstance(name: "StrategyMemo"), // 5 — slot+0x82B0, len 0x1774  → ColoSaveStrategyMemo (500 entries)
            .structInstance(name: "Tail"),         // 6 — slot+0x9A24, len 0x145DC → ColoSaveTail (fully decomposed)
        ]

        /// Body-base offset — where the first section starts in the
        /// slot. The 8 bytes before it (`slot[0..0x08]`) are the
        /// slot's plaintext header (magic + counter).
        public var bodyBaseOffset: Int = 0x08

        /// Section index → registered struct definition name. Every
        /// Colo section binds to a struct so its length can be
        /// derived. See `XDEngine.Data.sectionStructTypes` for the
        /// mod-authoring rationale.
        public var sectionStructTypes: [Int: String] = Self.defaultSectionStructTypes

        static let defaultSectionStructTypes: [Int: String] = [
            0: "ColoSaveConfig",
            1: "ColoSaveTrainer",
            2: "ColoSavePCBox",
            3: "ColoSavePCItemsMailbox",
            4: "ColoSaveDaycare",
            5: "ColoSaveStrategyMemo",
            6: "ColoSaveTail",
        ]

        public struct Resources: Codable {
            /// Region-neutral path. The actual bytes are region-specific
            /// (see legacy `CMRelIndexes.swift:108-126`) and selected by
            /// `ProjectSetup` based on the ROM's game ID.
            public var commonRelSymbolMap: File = "Resources/common_rel_symbols.json"
            public var commonRelTypeMap: File = "Resources/common_rel_typemap.json"
            public var mapRelSymbolMap: File = "Resources/map_rel_symbols.json"
            /// Colosseum ships two map REL layouts. Type 1 = the standard
            /// format (entry-point indices 1/2, character indices 3/4);
            /// Type 2 = the alternate format (indices 0/1 and 5/6) that
            /// the legacy parser detects via the angle-sentinel check at
            /// `XGMapRel.swift:35-53`. Each gets its own typemap so the
            /// disassembler can resolve labels independently.
            public var mapRelTypeMapType1: File = "Resources/map_rel_typemap_type1.json"
            public var mapRelTypeMapType2: File = "Resources/map_rel_typemap_type2.json"
            public var pocketMenuSymbolMap: File = "Resources/pocket_menu_symbols.json"
            /// Relative path of the DOL symbol map. No map is bundled
            /// yet for Colosseum; `ProjectSetup` writes a region-matched
            /// map here once one lands in the bundle.
            public var dolSymbolMap: File = "Resources/dol.map"
            /// Typed regions within the main.dol data sections. Region-neutral
            /// path; `ProjectSetup` writes the ROM's own map here, because
            /// every chunk is identified by address and the data sections move
            /// between builds.
            public var dolTypeMap: File = "Resources/dol_typemap.json"

            public init(
                commonRelSymbolMap: File = "Resources/common_rel_symbols.json",
                commonRelTypeMap: File = "Resources/common_rel_typemap.json",
                mapRelSymbolMap: File = "Resources/map_rel_symbols.json",
                mapRelTypeMapType1: File = "Resources/map_rel_typemap_type1.json",
                mapRelTypeMapType2: File = "Resources/map_rel_typemap_type2.json",
                pocketMenuSymbolMap: File = "Resources/pocket_menu_symbols.json",
                dolSymbolMap: File = "Resources/dol.map",
                dolTypeMap: File = "Resources/dol_typemap.json"
            ) {
                self.commonRelSymbolMap = commonRelSymbolMap
                self.commonRelTypeMap = commonRelTypeMap
                self.mapRelSymbolMap = mapRelSymbolMap
                self.mapRelTypeMapType1 = mapRelTypeMapType1
                self.mapRelTypeMapType2 = mapRelTypeMapType2
                self.pocketMenuSymbolMap = pocketMenuSymbolMap
                self.dolSymbolMap = dolSymbolMap
                self.dolTypeMap = dolTypeMap
            }
        }

        public init(
            scriptBuiltInFunctions: [String: ScriptFunctionDef]? = nil,
            resources: Resources = Resources(),
            saveSections: [SaveSectionSpec]? = nil,
            bodyBaseOffset: Int = 0x08,
            sectionStructTypes: [Int: String]? = nil
        ) {
            self.scriptBuiltInFunctions = scriptBuiltInFunctions ?? Self.defaultBuiltInFunctions
            self.resources = resources
            self.saveSections = saveSections ?? Self.defaultSaveSections
            self.bodyBaseOffset = bodyBaseOffset
            self.sectionStructTypes = sectionStructTypes ?? Self.defaultSectionStructTypes
        }

        /// Look up a function name by ID
        public func builtInName(for id: Int) -> String? {
            scriptBuiltInFunctions[String(id)]?.name
        }

        /// All function names keyed by integer ID
        public var builtInNamesByID: [Int: String] {
            var result = [Int: String]()
            for (key, def) in scriptBuiltInFunctions {
                if let id = Int(key) {
                    result[id] = def.name
                }
            }
            return result
        }
    }
}

// MARK: - Default Built-In Functions (from legacy CMScriptBuiltInFunctions.swift)

public extension ColosseumEngine.Data {
    static let defaultBuiltInFunctions: [String: ScriptFunctionDef] = {
        func f(_ name: String, _ params: [(String, ScriptParamType)] = [], ret: ScriptParamType? = nil) -> ScriptFunctionDef {
            ScriptFunctionDef(
                name: name,
                parameters: params.map { .init(name: $0.0, type: $0.1) },
                returnType: ret
            )
        }

        // Generated from the engine's native dispatch table (US DOL @0x802E1CF0)
        // merged with corpus usage evidence and legacy tool names — see
        // Documentation/File Formats/Colosseum/Script Builtin Functions.md.
        // Types are restricted to integer/float/bool/string; semantic ID
        // types (messages, flags, ...) are intentionally not encoded here.
        return [
            "1": f("taskUnknown1", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "2": f("randomNumberMod", [("max", .integer)], ret: .integer),
            "3": f("threadRunInBackground", [("function", .integer), ("arg1", .bool), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer), ("arg5", .integer)], ret: .integer),
            "4": f("systemUnknown4", [("arg0", .integer)]),
            "5": f("systemUnknown5", [("arg0", .integer)]),
            "6": f("threadWaitForCompletion", [("threadID", .integer)]),
            "7": f("dialogDisplaySilentMessage", [("msgID", .integer), ("unk1", .bool), ("unk2", .bool)]),
            "8": f("dialogWaitForMessage", [("unk", .bool)]),
            "9": f("dialogUnknown9", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "10": f("dialogUnknown10", [("arg0", .integer)]),
            "11": f("dialogDisplayYesNoMenu", ret: .integer),
            "12": f("dialogUnknown12", [("arg0", .integer), ("arg1", .integer)]),
            "13": f("dialogUnknown13", [("arg0", .integer)]),
            "14": f("dialogUnknown14", [("arg0", .integer)]),
            "15": f("dialogUnknown15", [("arg0", .integer), ("arg1", .integer)]),
            "16": f("sysUnknown16"),
            "17": f("sysUnknown17", [("arg0", .integer), ("arg1", .integer)]),
            "18": f("sysUnknown18"),
            "19": f("sysUnknown19", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "20": f("sysUnknown20"),
            "21": f("sysUnknown21"),
            "22": f("sysUnknown22", [("arg0", .integer), ("arg1", .integer)]),
            "23": f("dialogDisplayNameEntryMenu"),
            "24": f("dialogDisplayPCBoxMenu"),
            "25": f("openShopDialog", [("martID", .integer)]),
            "26": f("sysUnknown26"),
            "27": f("sysUnknown27"),
            "28": f("transitionBegin", [("transitionID", .integer), ("duration", .float)]),
            "29": f("transitionWait", [("unk", .bool)]),
            "30": f("playerUnknown30"),
            "31": f("playerProcessEvents"),
            "32": f("playerLockMovement"),
            "33": f("playerFreeMovement"),
            "34": f("triggerScriptFunction", [("function", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "35": f("menuUnknown35", [("arg0", .integer)]),
            "36": f("cameraUnknown36", [("arg0", .integer)]),
            "37": f("cameraUnknown37", [("arg0", .integer), ("arg1", .integer)]),
            "38": f("cameraUnknown38", [("arg0", .float), ("arg1", .float), ("arg2", .float)]),
            "39": f("cameraUnknown39", [("arg0", .float), ("arg1", .float), ("arg2", .float)]),
            "40": f("cameraSetPosition", [("x", .float), ("y", .float), ("z", .float)]),
            "41": f("cameraSetRotation", [("x", .float), ("y", .float), ("z", .float)]),
            "42": f("cameraPresetFromFile", [("groupID", .integer), ("fileID", .integer), ("unk1", .bool), ("unk2", .bool)]),
            "43": f("cameraUnknown43"),
            "44": f("cameraUnknown44"),
            "45": f("cameraUnknown45"),
            "46": f("cameraUnknown46", [("arg0", .bool)]),
            "47": f("characterHide", [("resourceID", .integer)]),
            "48": f("cameraUnknown48", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .float)]),
            "49": f("cameraUnknown49"),
            "50": f("characterSetVisibility", [("groupID", .integer), ("resourceID", .integer), ("visible", .bool)]),
            "51": f("characterSetAnimation", [("groupID", .integer), ("resourceID", .integer), ("animID", .integer), ("unk", .bool), ("repeat", .bool)]),
            "52": f("characterUnknown52", [("arg0", .integer), ("arg1", .integer)]),
            "53": f("characterWaitForAnimation", [("groupID", .integer), ("resourceID", .integer), ("unk", .bool)]),
            "54": f("characterTalk", [("groupID", .integer), ("resourceID", .integer), ("msgID", .integer)]),
            "55": f("characterEndSpeech", [("groupID", .integer), ("resourceID", .integer)]),
            "56": f("characterUnknown56", [("arg0", .integer), ("arg1", .integer)]),
            "57": f("characterUnknown57", [("arg0", .integer), ("arg1", .integer)]),
            "58": f("characterCheckWithinBounds", [("groupID", .integer), ("resourceID", .integer), ("x1", .float), ("y1", .float), ("x2", .float), ("y2", .float)], ret: .integer),
            "59": f("characterSetPosition", [("groupID", .integer), ("resourceID", .integer), ("x", .float), ("y", .float), ("z", .float)]),
            "60": f("characterRotateAroundAxes", [("groupID", .integer), ("resourceID", .integer), ("x", .float), ("y", .float), ("z", .float)]),
            "61": f("characterMoveToPosition", [("groupID", .integer), ("resourceID", .integer), ("x", .integer), ("y", .float), ("z", .float), ("arg5", .float)]),
            "62": f("characterWaitForMovement", [("groupID", .integer), ("resourceID", .integer), ("unk", .bool)]),
            "63": f("characterClearFlags", [("groupID", .integer), ("resourceID", .integer), ("flagBits", .integer)]),
            "64": f("characterSetFlags", [("groupID", .integer), ("resourceID", .integer), ("flagBits", .integer)]),
            "65": f("characterUnknown65", [("arg0", .integer), ("arg1", .integer)]),
            "66": f("characterMoveToPositionSlow", [("groupID", .integer), ("resourceID", .integer), ("x", .integer), ("y", .integer), ("z", .integer)]),
            "67": f("characterUnknown67", [("arg0", .integer), ("arg1", .integer)]),
            "68": f("characterTurnToAngle", [("groupID", .integer), ("resourceID", .integer), ("angle", .float)]),
            "69": f("characterUnknown69", [("arg0", .integer), ("arg1", .integer), ("arg2", .float)]),
            "70": f("characterAttachToCharacter", [("groupID", .integer), ("resourceID", .integer), ("targetGID", .integer), ("targetRID", .integer), ("unk", .integer)]),
            "71": f("characterUnknown71", [("arg0", .integer), ("arg1", .integer)]),
            "72": f("characterUnknown72", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "73": f("characterRunToPosition", [("groupID", .integer), ("resourceID", .integer), ("x", .float), ("y", .float), ("z", .float)]),
            "74": f("characterUnknown74", [("arg0", .integer), ("arg1", .integer), ("arg2", .bool)]),
            "75": f("characterUnknown75", [("arg0", .integer), ("arg1", .integer)]),
            "76": f("characterUnknown76", [("arg0", .integer), ("arg1", .integer)]),
            "77": f("characterUnknown77", [("arg0", .integer), ("arg1", .integer)]),
            "78": f("flagSetFalse", [("flag", .integer)]),
            "79": f("flagSetTrue", [("flag", .integer)]),
            "80": f("flagSetValue", [("flag", .integer), ("value", .integer)]),
            "81": f("flagCheckTrue", [("flag", .integer)], ret: .bool),
            "82": f("flagGetValue", [("flag", .integer)], ret: .integer),
            "83": f("pokemonUnknown83", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "84": f("pokemonUnknown84", [("arg0", .integer), ("arg1", .integer)]),
            "85": f("pokemonUnknown85", [("arg0", .integer), ("arg1", .integer)]),
            "86": f("pokemonUnknown86", [("arg0", .integer), ("arg1", .integer)]),
            "87": f("pokemonUnknown87", [("arg0", .integer), ("arg1", .integer)]),
            "88": f("taskUnknown88", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "89": f("taskUnknown89", [("arg0", .integer), ("arg1", .integer)]),
            "90": f("taskUnknown90", [("arg0", .integer), ("arg1", .integer)]),
            "91": f("taskUnknown91", [("arg0", .integer), ("arg1", .integer)]),
            "92": f("getCurrentRoomID", ret: .integer),
            "93": f("getCurrentGroupID", ret: .integer),
            "94": f("mapGetPreviousRoomID", ret: .integer),
            "95": f("mapWarpToRoom", [("roomID", .integer), ("entryPointID", .integer)]),
            "96": f("mapUnknown96", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "97": f("mapUnknown97", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "98": f("mapWarpToMenuRoom", [("roomID", .integer)]),
            "99": f("taskUnknown99"),
            "100": f("systemUnknown100", [("arg0", .integer), ("arg1", .integer)]),
            "101": f("systemUnknown101", [("arg0", .integer), ("arg1", .float), ("arg2", .float), ("arg3", .float)]),
            "102": f("battleStart", [("battleID", .integer)]),
            "103": f("battleGetResult", ret: .integer),
            "104": f("soundSetBGM", [("id", .integer), ("unk", .integer), ("volume", .integer)]),
            "105": f("soundPlaySFX", [("id", .integer), ("unk", .integer), ("volume", .integer)]),
            "106": f("soundUnknown106", [("arg0", .integer), ("arg1", .integer)]),
            "107": f("soundUnknown107", [("arg0", .integer), ("arg1", .float), ("arg2", .float), ("arg3", .float)]),
            "108": f("soundUnknown108"),
            "109": f("soundFadeBGM", [("volume", .integer), ("duration", .integer)]),
            "110": f("systemUnknown110"),
            "111": f("systemUnknown111", ret: .integer),
            "112": f("modelGetResourceID", [("fileID", .integer)], ret: .integer),
            "113": f("systemUnknown113", [("arg0", .integer)]),
            "114": f("systemUnknown114", [("arg0", .integer), ("arg1", .bool)]),
            "115": f("systemUnknown115", [("arg0", .integer), ("arg1", .integer), ("arg2", .bool), ("arg3", .bool)]),
            "116": f("systemUnknown116", [("arg0", .integer)]),
            "117": f("systemUnknown117", [("arg0", .integer), ("arg1", .bool)]),
            "118": f("characterSetProperty", [("resourceID", .integer), ("value", .bool)]),
            "119": f("playerReceiveItem", [("itemID", .integer), ("quantity", .integer)]),
            "120": f("systemUnknown120", [("arg0", .integer)], ret: .integer),
            "121": f("systemUnknown121"),
            "122": f("systemUnknown122", [("arg0", .integer)]),
            "123": f("playerCountPartyPokemon", ret: .integer),
            "124": f("systemUnknown124", ret: .integer),
            "125": f("mapUnknown125", [("arg0", .integer), ("arg1", .integer), ("arg2", .bool)]),
            "126": f("playerUnknown126", [("arg0", .bool), ("arg1", .bool)]),
            "127": f("cameraUnknown127", [("arg0", .float), ("arg1", .float), ("arg2", .float)]),
            "128": f("mapSetReturnMap", [("currentRoom", .integer), ("previousRoom", .integer), ("warpPointIndex", .integer)]),
            "129": f("systemUnknown129"),
            "130": f("soundUnknown130", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "131": f("characterSurpriseAnimation", [("groupID", .integer), ("resourceID", .integer), ("unk", .bool)]),
            "132": f("dialogSetMessageVar", [("varIndex", .integer), ("value", .integer)]),
            "133": f("systemUnknown133", [("arg0", .integer)]),
            "134": f("systemUnknown134", ret: .integer),
            "135": f("mapUnknown135"),
            "136": f("mapUnknown136"),
            "137": f("soundUnknown137", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "138": f("soundUnknown138", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer)]),
            "139": f("soundUnknown139", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer)]),
            "140": f("cameraUnknown140", [("arg0", .bool), ("arg1", .float), ("arg2", .float), ("arg3", .float), ("arg4", .float)]),
            "141": f("cameraUnknown141", [("arg0", .bool), ("arg1", .float), ("arg2", .float), ("arg3", .float), ("arg4", .float)]),
            "142": f("sysUnknown142", [("arg0", .integer)]),
            "143": f("mapUnknown143", [("arg0", .float)]),
            "144": f("mapWarpWithTransitions", [("beforeWarp", .integer), ("afterWarp", .integer)]),
            "145": f("battleUnknown145", [("arg0", .integer)]),
            "146": f("battleUnknown146", [("arg0", .integer)]),
            "147": f("cameraUnknown147", [("arg0", .float)]),
            "148": f("cameraUnknown148", [("arg0", .float)]),
            "149": f("cameraUnknown149", [("arg0", .float)]),
            "150": f("cameraUnknown150", [("arg0", .float)]),
            "151": f("characterFaceDirection", [("groupID", .integer), ("resourceID", .integer), ("direction", .bool)]),
            "152": f("battleStartWithOptions", [("battleID", .integer), ("unk1", .bool), ("unk2", .bool)]),
            "153": f("soundUnknown153", [("arg0", .integer)]),
            "154": f("characterUnknown154", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "155": f("characterUnknown155", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "156": f("cameraUnknown156", [("arg0", .integer), ("arg1", .float), ("arg2", .float), ("arg3", .float), ("arg4", .float)]),
            "157": f("sleep", [("arg0", .float)]),
            "158": f("sysUnknown158", [("arg0", .integer)], ret: .integer),
            "159": f("systemUnknown159", [("arg0", .integer)]),
            "160": f("cameraUnknown160", [("arg0", .bool)]),
            "161": f("mapUnknown161", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "162": f("mapUnknown162"),
            "163": f("useCologne", [("arg0", .integer), ("arg1", .integer)]),
            "164": f("characterUnknown164", [("arg0", .integer), ("arg1", .integer), ("arg2", .float), ("arg3", .float), ("arg4", .float), ("arg5", .float)]),
            "165": f("characterFaceCharacter", [("targetGID", .integer), ("targetRID", .integer), ("argGID", .integer), ("argRID", .integer), ("speed", .float)]),
            "166": f("systemUnknown166", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "167": f("systemUnknown167", [("arg0", .integer)]),
            "168": f("characterUnknown168", [("arg0", .bool), ("arg1", .integer)]),
            "169": f("characterUnknown169", [("arg0", .integer), ("arg1", .integer)], ret: .integer),
            "170": f("characterUnknown170", [("arg0", .integer), ("arg1", .integer), ("arg2", .float), ("arg3", .float), ("arg4", .float), ("arg5", .float), ("arg6", .float), ("arg7", .bool)], ret: .integer),
            "171": f("mapUnknown171", [("arg0", .integer)]),
            "172": f("characterUnknown172", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "173": f("pokemonUnknown173", [("arg0", .integer)]),
            "174": f("cutsceneUnknown174"),
            "175": f("characterUnknown175", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "176": f("characterUnknown176", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "177": f("characterUnknown177", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .float), ("arg5", .bool)]),
            "178": f("characterUnknown178", [("arg0", .integer), ("arg1", .integer), ("arg2", .float)]),
            "179": f("cameraUnknown179", [("arg0", .float), ("arg1", .bool)]),
            "180": f("getCurrentFloorID", ret: .integer),
            "181": f("characterTurnHeadTowards", [("argGID", .integer), ("argRID", .integer), ("targetGID", .integer), ("targetRID", .integer)]),
            "182": f("menuUnknown182", [("arg0", .integer)]),
            "183": f("systemUnknown183", [("arg0", .integer)]),
            "184": f("systemUnknown184"),
            "185": f("systemUnknown185", [("arg0", .integer)]),
            "186": f("systemUnknown186", [("arg0", .integer)]),
            "187": f("systemUnknown187", ret: .integer),
            "188": f("systemUnknown188", [("arg0", .integer)]),
            "189": f("pdaUpdateStrategyMemo", ret: .bool),
            "190": f("menuUnknown190", [("arg0", .integer), ("arg1", .integer)]),
            "191": f("mapTransformElement", [("fileID", .integer), ("unk1", .bool), ("unk2", .bool), ("unk3", .bool)]),
            "192": f("menuUnknown192", [("arg0", .integer)]),
            "193": f("menuUnknown193", [("arg0", .integer), ("arg1", .integer)]),
            "194": f("mapBeginRelicPurifications", [("unk1", .integer), ("unk2", .integer)]),
            "195": f("mapUnknown195", ret: .integer),
            "196": f("menuUnknown196", ret: .integer),
            "197": f("menuUnknown197", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer)]),
            "198": f("menuEnterTradingMenu"),
            "199": f("menuDisplayCustomMenu", [("msgIDs", .integer), ("length", .integer), ("x", .integer), ("y", .integer), ("startIndex", .bool)], ret: .integer),
            "200": f("menuUnknown200", ret: .integer),
            "201": f("sysUnknown201"),
            "202": f("sysUnknown202"),
            "203": f("mapUnknown203", [("arg0", .integer), ("arg1", .integer), ("arg2", .bool)]),
            "204": f("promptDNAKeyCode", [("sample1", .integer), ("sample2", .integer), ("sample3", .integer)], ret: .integer),
            "205": f("getDNASampleSpecies", [("sampleID", .integer)], ret: .integer),
            "206": f("sysUnknown206"),
            "207": f("menuUnknown207"),
            "208": f("promptDNASampleSelection"),
            "209": f("scriptCallByID", [("scriptID", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "210": f("characterUnknown210", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer)]),
            "211": f("systemUnknown211"),
            "212": f("sysUnknown212", ret: .integer),
            "213": f("sysUnknown213", ret: .integer),
            "214": f("mapUnknown214", [("arg0", .integer), ("arg1", .integer)]),
            "215": f("sysUnknown215", [("arg0", .integer), ("arg1", .integer)]),
            "216": f("menuUnknown216", [("arg0", .bool)]),
            "217": f("playerReceiveGiftPokemon", [("giftPokemonID", .integer)], ret: .integer),
            "218": f("soundPlayPokemonCry", [("pokemon", .integer)]),
            "219": f("systemUnknown219", [("arg0", .integer), ("arg1", .integer)]),
            "220": f("sysUnknown220", ret: .integer),
            "221": f("systemUnknown221", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
            "222": f("systemUnknown222", [("arg0", .integer), ("arg1", .integer)]),
            "223": f("systemUnknown223"),
            "224": f("dialogDisplayMessageWithOptions", [("msgID", .integer), ("unk1", .bool), ("unk2", .bool), ("unk3", .integer)], ret: .integer),
            "225": f("systemUnknown225", [("arg0", .bool)]),
            "226": f("systemUnknown226", [("arg0", .bool)], ret: .integer),
            "227": f("cutsceneUnknown227"),
            "228": f("soundGetCurrentBGM", ret: .integer),
            "229": f("systemUnknown229", [("arg0", .bool)]),
            "230": f("cutsceneUnknown230"),
            "231": f("characterUnknown231", [("arg0", .integer), ("arg1", .integer), ("arg2", .bool)]),
            "232": f("menuUnknown232", [("arg0", .integer), ("arg1", .integer)]),
            "233": f("systemUnknown233"),
            "234": f("systemUnknown234"),
            "235": f("menuShowSaveMenu", [("unk", .bool)], ret: .bool),
            "236": f("playerGetCouponsThisRun", ret: .integer),
            "237": f("systemUnknown237", [("arg0", .integer)]),
            "238": f("systemUnknown238", [("arg0", .integer)]),
            "239": f("playerGetCouponsLastArea", ret: .integer),
            "240": f("sysUnknown240"),
            "241": f("mapActivateParticleEffects"),
            "242": f("playerCountPurifiablePokemon", ret: .integer),
            "243": f("battleUnknown243", [("arg0", .integer), ("arg1", .integer)]),
            "244": f("cutsceneUnknown244", [("arg0", .float), ("arg1", .float), ("arg2", .float), ("arg3", .float), ("arg4", .float), ("arg5", .float)]),
            "245": f("sysUnknown245", [("arg0", .bool), ("arg1", .integer), ("arg2", .integer), ("arg3", .bool)], ret: .integer),
            "246": f("mapUnknown246", [("arg0", .integer), ("arg1", .integer), ("arg2", .integer)]),
        ]
    }()
}
