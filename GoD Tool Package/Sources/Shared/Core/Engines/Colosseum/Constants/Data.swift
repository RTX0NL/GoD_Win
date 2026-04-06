import GoDFoundation
import ScriptDecompiler

public extension ColosseumEngine {
    struct Data: Codable {
        /// Script built-in function definitions keyed by function ID (as string)
        public var scriptBuiltInFunctions: [String: ScriptFunctionDef]

        public init(scriptBuiltInFunctions: [String: ScriptFunctionDef]? = nil) {
            self.scriptBuiltInFunctions = scriptBuiltInFunctions ?? Self.defaultBuiltInFunctions
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
