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
            .structInstance(name: "Config"),       // 0 — slot+0x08, len 0x70
            .binary(name: "Trainer1"),             // 1 — slot+0x78, len 0xB18
            .binary(name: "PCBox"),                // 2 — slot+0xB90, len 0x6DEC
            .binary(name: "BattleData"),           // 3 — slot+0x797C, len 0x7F4 (unknown)
            .binary(name: "Daycare"),              // 4 — slot+0x8170, len 0x140
            .binary(name: "StrategyMemo"),         // 5 — slot+0x82B0, len 0xB10
            .binary(name: "Tail"),                 // 6 — slot+0x8DC0, len 0x15240
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
            1: "ColoTrainer1",
            2: "ColoPCBox",
            3: "ColoBattleData",
            4: "ColoDaycare",
            5: "ColoStrategyMemo",
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

            public init(
                commonRelSymbolMap: File = "Resources/common_rel_symbols.json",
                commonRelTypeMap: File = "Resources/common_rel_typemap.json",
                mapRelSymbolMap: File = "Resources/map_rel_symbols.json",
                mapRelTypeMapType1: File = "Resources/map_rel_typemap_type1.json",
                mapRelTypeMapType2: File = "Resources/map_rel_typemap_type2.json",
                pocketMenuSymbolMap: File = "Resources/pocket_menu_symbols.json",
                dolSymbolMap: File = "Resources/dol.map"
            ) {
                self.commonRelSymbolMap = commonRelSymbolMap
                self.commonRelTypeMap = commonRelTypeMap
                self.mapRelSymbolMap = mapRelSymbolMap
                self.mapRelTypeMapType1 = mapRelTypeMapType1
                self.mapRelTypeMapType2 = mapRelTypeMapType2
                self.pocketMenuSymbolMap = pocketMenuSymbolMap
                self.dolSymbolMap = dolSymbolMap
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

        return [
            "2": f("randomNumberMod", [("max", .integer)], ret: .integer),
            "3": f("threadRunInBackground", [("function", .enumRef("ScriptFunction")), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)], ret: .integer),
            "6": f("threadWaitForCompletion", [("threadID", .integer)]),
            "7": f("dialogDisplaySilentMessage", [("msgID", .enumRef("MsgID")), ("unk1", .integer), ("unk2", .integer)]),
            "8": f("dialogWaitForMessage", [("unk", .bool)]),
            "11": f("dialogDisplayYesNoMenu", ret: .enumRef("YesNoIndex")),
            "23": f("dialogDisplayNameEntryMenu"),
            "24": f("dialogDisplayPCBoxMenu"),
            "25": f("openShopDialog", [("martID", .enumRef("MartID"))]),
            "28": f("transitionBegin", [("transitionID", .enumRef("TransitionID")), ("duration", .float)]),
            "29": f("transitionWait", [("unk", .bool)]),
            "31": f("playerProcessEvents"),
            "32": f("playerLockMovement"),
            "33": f("playerFreeMovement"),
            "34": f("triggerScriptFunction", [("function", .enumRef("ScriptFunction")), ("arg1", .integer), ("arg2", .integer), ("arg3", .integer), ("arg4", .integer)]),
            "40": f("cameraSetPosition", [("x", .float), ("y", .float), ("z", .float)]),
            "41": f("cameraSetRotation", [("x", .float), ("y", .float), ("z", .float)]),
            "42": f("cameraPresetFromFile", [("groupID", .integer), ("fileID", .enumRef("FileIdentifier")), ("unk1", .integer), ("unk2", .integer)]),
            "47": f("characterHide", [("resourceID", .enumRef("ResourceID")), ("groupID", .enumRef("GroupID"))]),
            "50": f("characterSetVisibility", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("visible", .bool)]),
            "51": f("characterSetAnimation", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("animID", .integer), ("unk", .bool), ("repeat", .bool)]),
            "53": f("characterWaitForAnimation", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("unk", .bool)]),
            "54": f("characterTalk", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("msgID", .enumRef("MsgID"))]),
            "55": f("characterEndSpeech", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID"))]),
            "58": f("characterCheckWithinBounds", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x1", .float), ("y1", .float), ("x2", .float), ("y2", .float)]),
            "59": f("characterSetPosition", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x", .float), ("y", .float), ("z", .float)]),
            "60": f("characterRotateAroundAxes", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x", .float), ("y", .float), ("z", .float)]),
            "61": f("characterMoveToPosition", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x", .float), ("y", .float), ("z", .float)]),
            "62": f("characterWaitForMovement", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("unk", .bool)]),
            "63": f("characterClearFlags", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("flagBits", .integer)]),
            "64": f("characterSetFlags", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("flagBits", .integer)]),
            "66": f("characterMoveToPositionSlow", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x", .float), ("y", .float), ("z", .float)]),
            "68": f("characterTurnToAngle", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("angle", .float)]),
            "70": f("characterAttachToCharacter", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("targetGID", .enumRef("GroupID")), ("targetRID", .enumRef("ResourceID")), ("unk", .integer)]),
            "73": f("characterRunToPosition", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("x", .float), ("y", .float), ("z", .float)]),
            "78": f("flagSetFalse", [("flag", .enumRef("Flag"))]),
            "79": f("flagSetTrue", [("flag", .enumRef("Flag"))]),
            "80": f("flagSetValue", [("flag", .enumRef("Flag")), ("value", .integer)]),
            "81": f("flagCheckTrue", [("flag", .enumRef("Flag"))], ret: .bool),
            "82": f("flagGetValue", [("flag", .enumRef("Flag"))], ret: .integer),
            "92": f("getCurrentRoomID", ret: .enumRef("Room")),
            "93": f("getCurrentGroupID", ret: .enumRef("GroupID")),
            "94": f("mapGetPreviousRoomID", ret: .enumRef("Room")),
            "95": f("mapWarpToRoom", [("roomID", .enumRef("Room")), ("entryPointID", .integer)]),
            "98": f("mapWarpToMenuRoom", [("roomID", .enumRef("Room"))]),
            "102": f("battleStart", [("battleID", .enumRef("BattleID"))]),
            "103": f("battleGetResult", ret: .enumRef("BattleResult")),
            "104": f("soundSetBGM", [("id", .integer), ("unk", .integer), ("volume", .integer)]),
            "105": f("soundPlaySFX", [("id", .integer), ("unk", .integer), ("volume", .integer)]),
            "109": f("soundFadeBGM", [("volume", .integer), ("duration", .integer)]),
            "112": f("modelGetResourceID", [("fileID", .enumRef("FileIdentifier"))], ret: .enumRef("ResourceID")),
            "118": f("characterSetProperty", [("resourceID", .enumRef("ResourceID")), ("value", .integer)]),
            "119": f("playerReceiveItem", [("itemID", .enumRef("Item")), ("quantity", .integer)]),
            "123": f("playerCountPartyPokemon", ret: .integer),
            "128": f("mapSetReturnMap", [("currentRoom", .enumRef("Room")), ("previousRoom", .enumRef("Room")), ("warpPointIndex", .integer)]),
            "131": f("characterSurpriseAnimation", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("unk", .bool)]),
            "132": f("dialogSetMessageVar", [("varIndex", .integer), ("value", .integer)]),
            "144": f("mapWarpWithTransitions", [("beforeWarp", .enumRef("ScriptFunction")), ("afterWarp", .enumRef("ScriptFunction"))]),
            "151": f("characterFaceDirection", [("groupID", .enumRef("GroupID")), ("resourceID", .enumRef("ResourceID")), ("direction", .integer)]),
            "152": f("battleStartWithOptions", [("battleID", .enumRef("BattleID")), ("unk1", .bool), ("unk2", .bool)]),
            "157": f("sleep"),
            "163": f("useCologne"),
            "165": f("characterFaceCharacter", [("targetGID", .enumRef("GroupID")), ("targetRID", .enumRef("ResourceID")), ("argGID", .enumRef("GroupID")), ("argRID", .enumRef("ResourceID")), ("speed", .float)]),
            "180": f("getCurrentFloorID", ret: .integer),
            "181": f("characterTurnHeadTowards", [("argGID", .enumRef("GroupID")), ("argRID", .enumRef("ResourceID")), ("targetGID", .enumRef("GroupID")), ("targetRID", .enumRef("ResourceID"))]),
            "189": f("pdaUpdateStrategyMemo", ret: .bool),
            "191": f("mapTransformElement", [("fileID", .enumRef("FileIdentifier")), ("unk1", .bool), ("unk2", .bool), ("unk3", .bool)]),
            "194": f("mapBeginRelicPurifications", [("unk1", .integer), ("unk2", .integer)]),
            "198": f("menuEnterTradingMenu"),
            "199": f("menuDisplayCustomMenu", [("msgIDs", .enumRef("Array")), ("length", .integer), ("x", .integer), ("y", .integer), ("startIndex", .integer)]),
            "204": f("promptDNAKeyCode", [("sample1", .integer), ("sample2", .integer), ("sample3", .integer)], ret: .enumRef("Pokemon")),
            "205": f("getDNASampleSpecies", [("sampleID", .integer)], ret: .enumRef("Pokemon")),
            "208": f("promptDNASampleSelection"),
            "209": f("scriptCallByID", [("scriptID", .integer)]),
            "217": f("playerReceiveGiftPokemon", [("giftPokemonID", .integer)], ret: .integer),
            "218": f("soundPlayPokemonCry", [("pokemon", .enumRef("Pokemon"))]),
            "224": f("dialogDisplayMessageWithOptions", [("msgID", .enumRef("MsgID")), ("unk1", .integer), ("unk2", .integer), ("unk3", .integer)], ret: .integer),
            "228": f("soundGetCurrentBGM", ret: .integer),
            "235": f("menuShowSaveMenu", [("unk", .bool)], ret: .bool),
            "236": f("playerGetCouponsThisRun", ret: .integer),
            "239": f("playerGetCouponsLastArea", ret: .integer),
            "241": f("mapActivateParticleEffects", [("fileID1", .enumRef("FileIdentifier")), ("fileID2", .enumRef("FileIdentifier"))]),
            "242": f("playerCountPurifiablePokemon", ret: .integer),
        ]
    }()
}
