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
        func f(_ name: String, _ params: [(String, String)] = [], ret: String? = nil) -> ScriptFunctionDef {
            ScriptFunctionDef(
                name: name,
                parameters: params.map { .init(name: $0.0, type: $0.1) },
                returnType: ret
            )
        }

        return [
            "2": f("randomNumberMod", [("max", "integer")], ret: "integer"),
            "3": f("threadRunInBackground", [("function", "scriptFunction"), ("arg1", "integer"), ("arg2", "integer"), ("arg3", "integer"), ("arg4", "integer")], ret: "integer"),
            "6": f("threadWaitForCompletion", [("threadID", "integer")]),
            "7": f("dialogDisplaySilentMessage", [("msgID", "msgID"), ("unk1", "integer"), ("unk2", "integer")]),
            "8": f("dialogWaitForMessage", [("unk", "bool")]),
            "11": f("dialogDisplayYesNoMenu", ret: "yesNoIndex"),
            "23": f("dialogDisplayNameEntryMenu"),
            "24": f("dialogDisplayPCBoxMenu"),
            "25": f("openShopDialog", [("martID", "martID")]),
            "28": f("transitionBegin", [("transitionID", "transitionID"), ("duration", "float")]),
            "29": f("transitionWait", [("unk", "bool")]),
            "31": f("playerProcessEvents"),
            "32": f("playerLockMovement"),
            "33": f("playerFreeMovement"),
            "34": f("triggerScriptFunction", [("function", "scriptFunction"), ("arg1", "integer"), ("arg2", "integer"), ("arg3", "integer"), ("arg4", "integer")]),
            "40": f("cameraSetPosition", [("x", "float"), ("y", "float"), ("z", "float")]),
            "41": f("cameraSetRotation", [("x", "float"), ("y", "float"), ("z", "float")]),
            "42": f("cameraPresetFromFile", [("groupID", "integer"), ("fileID", "fileIdentifier"), ("unk1", "integer"), ("unk2", "integer")]),
            "47": f("characterHide", [("resourceID", "resourceID"), ("groupID", "groupID")]),
            "50": f("characterSetVisibility", [("groupID", "groupID"), ("resourceID", "resourceID"), ("visible", "bool")]),
            "51": f("characterSetAnimation", [("groupID", "groupID"), ("resourceID", "resourceID"), ("animID", "integer"), ("unk", "bool"), ("repeat", "bool")]),
            "53": f("characterWaitForAnimation", [("groupID", "groupID"), ("resourceID", "resourceID"), ("unk", "bool")]),
            "54": f("characterTalk", [("groupID", "groupID"), ("resourceID", "resourceID"), ("msgID", "msgID")]),
            "55": f("characterEndSpeech", [("groupID", "groupID"), ("resourceID", "resourceID")]),
            "58": f("characterCheckWithinBounds", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x1", "float"), ("y1", "float"), ("x2", "float"), ("y2", "float")]),
            "59": f("characterSetPosition", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x", "float"), ("y", "float"), ("z", "float")]),
            "60": f("characterRotateAroundAxes", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x", "float"), ("y", "float"), ("z", "float")]),
            "61": f("characterMoveToPosition", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x", "float"), ("y", "float"), ("z", "float")]),
            "62": f("characterWaitForMovement", [("groupID", "groupID"), ("resourceID", "resourceID"), ("unk", "bool")]),
            "63": f("characterClearFlags", [("groupID", "groupID"), ("resourceID", "resourceID"), ("flagBits", "integer")]),
            "64": f("characterSetFlags", [("groupID", "groupID"), ("resourceID", "resourceID"), ("flagBits", "integer")]),
            "66": f("characterMoveToPositionSlow", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x", "float"), ("y", "float"), ("z", "float")]),
            "68": f("characterTurnToAngle", [("groupID", "groupID"), ("resourceID", "resourceID"), ("angle", "float")]),
            "70": f("characterAttachToCharacter", [("groupID", "groupID"), ("resourceID", "resourceID"), ("targetGID", "groupID"), ("targetRID", "resourceID"), ("unk", "integer")]),
            "73": f("characterRunToPosition", [("groupID", "groupID"), ("resourceID", "resourceID"), ("x", "float"), ("y", "float"), ("z", "float")]),
            "78": f("flagSetFalse", [("flag", "flag")]),
            "79": f("flagSetTrue", [("flag", "flag")]),
            "80": f("flagSetValue", [("flag", "flag"), ("value", "integer")]),
            "81": f("flagCheckTrue", [("flag", "flag")], ret: "bool"),
            "82": f("flagGetValue", [("flag", "flag")], ret: "integer"),
            "92": f("getCurrentRoomID", ret: "room"),
            "93": f("getCurrentGroupID", ret: "groupID"),
            "94": f("mapGetPreviousRoomID", ret: "room"),
            "95": f("mapWarpToRoom", [("roomID", "room"), ("entryPointID", "integer")]),
            "98": f("mapWarpToMenuRoom", [("roomID", "room")]),
            "102": f("battleStart", [("battleID", "battleID")]),
            "103": f("battleGetResult", ret: "battleResult"),
            "104": f("soundSetBGM", [("id", "integer"), ("unk", "integer"), ("volume", "integer")]),
            "105": f("soundPlaySFX", [("id", "integer"), ("unk", "integer"), ("volume", "integer")]),
            "109": f("soundFadeBGM", [("volume", "integer"), ("duration", "integer")]),
            "112": f("modelGetResourceID", [("fileID", "fileIdentifier")], ret: "resourceID"),
            "118": f("characterSetProperty", [("resourceID", "resourceID"), ("value", "integer")]),
            "119": f("playerReceiveItem", [("itemID", "item"), ("quantity", "integer")]),
            "123": f("playerCountPartyPokemon", ret: "integer"),
            "128": f("mapSetReturnMap", [("currentRoom", "room"), ("previousRoom", "room"), ("warpPointIndex", "integer")]),
            "131": f("characterSurpriseAnimation", [("groupID", "groupID"), ("resourceID", "resourceID"), ("unk", "bool")]),
            "132": f("dialogSetMessageVar", [("varIndex", "integer"), ("value", "integer")]),
            "144": f("mapWarpWithTransitions", [("beforeWarp", "scriptFunction"), ("afterWarp", "scriptFunction")]),
            "151": f("characterFaceDirection", [("groupID", "groupID"), ("resourceID", "resourceID"), ("direction", "integer")]),
            "152": f("battleStartWithOptions", [("battleID", "battleID"), ("unk1", "bool"), ("unk2", "bool")]),
            "157": f("sleep"),
            "163": f("useCologne"),
            "165": f("characterFaceCharacter", [("targetGID", "groupID"), ("targetRID", "resourceID"), ("argGID", "groupID"), ("argRID", "resourceID"), ("speed", "float")]),
            "180": f("getCurrentFloorID", ret: "integer"),
            "181": f("characterTurnHeadTowards", [("argGID", "groupID"), ("argRID", "resourceID"), ("targetGID", "groupID"), ("targetRID", "resourceID")]),
            "189": f("pdaUpdateStrategyMemo", ret: "bool"),
            "191": f("mapTransformElement", [("fileID", "fileIdentifier"), ("unk1", "bool"), ("unk2", "bool"), ("unk3", "bool")]),
            "194": f("mapBeginRelicPurifications", [("unk1", "integer"), ("unk2", "integer")]),
            "198": f("menuEnterTradingMenu"),
            "199": f("menuDisplayCustomMenu", [("msgIDs", "array"), ("length", "integer"), ("x", "integer"), ("y", "integer"), ("startIndex", "integer")]),
            "204": f("promptDNAKeyCode", [("sample1", "integer"), ("sample2", "integer"), ("sample3", "integer")], ret: "pokemon"),
            "205": f("getDNASampleSpecies", [("sampleID", "integer")], ret: "pokemon"),
            "208": f("promptDNASampleSelection"),
            "209": f("scriptCallByID", [("scriptID", "integer")]),
            "217": f("playerReceiveGiftPokemon", [("giftPokemonID", "integer")], ret: "integer"),
            "218": f("soundPlayPokemonCry", [("pokemon", "pokemon")]),
            "224": f("dialogDisplayMessageWithOptions", [("msgID", "msgID"), ("unk1", "integer"), ("unk2", "integer"), ("unk3", "integer")], ret: "integer"),
            "228": f("soundGetCurrentBGM", ret: "integer"),
            "235": f("menuShowSaveMenu", [("unk", "bool")], ret: "bool"),
            "236": f("playerGetCouponsThisRun", ret: "integer"),
            "239": f("playerGetCouponsLastArea", ret: "integer"),
            "241": f("mapActivateParticleEffects", [("fileID1", "fileIdentifier"), ("fileID2", "fileIdentifier")]),
            "242": f("playerCountPurifiablePokemon", ret: "integer"),
        ]
    }()
}
