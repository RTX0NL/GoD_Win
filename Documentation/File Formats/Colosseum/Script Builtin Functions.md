# Colosseum Script Built-in Functions

Reference for every native `callStandard` function in Pokemon Colosseum (US).

Source of truth: the engine's own dispatch table in `main.dol` at
`0x802E1CF0` (symbol `scriptBuiltinFunctionTable`) — 247 entries of 12 bytes:
`{u32 handlerPointer, u8 argTypes[8]}` (type byte 0 = end of arguments,
2 = float, anything else = int). The `callStandard` opcode handler
(`scriptOpCallStandardHandler`, 0x800F10E8) marshals stack values into int and
float argument blocks according to these bytes, so argument counts and
primitive types below are engine-declared, not guessed.

Everything else is layered evidence:
- **Names** come from the legacy modding tool where known (`legacy` in the
  Named column); all others are `<module>Unknown<id>` placeholders derived
  from the handler's address cluster (flag functions live at 0x80190xxx,
  character functions at 0x8018xxxx, sound at 0x80165xxx, camera at
  0x80176-0x80179, dialog at 0x80102/0x80106, map/floor at 0x8011xxxx, ...).
- **Bool** parameters are legacy-declared, or inferred (`?` suffix) when every
  scripted call in the US corpus passes only constant 0/1 (n ≥ 8).
- **Return types**: a function returns Int when the corpus consumes its result
  (usage is all-or-nothing per function) or the legacy tool declares it.
  `Void` results are never consumed by any script.
- Types are deliberately limited to Int / Float / Bool / String so modded
  games remain expressible; semantic ID spaces (message IDs, flag IDs, battle
  IDs, ...) are the modder's concern. Observed ID ranges live in the census
  data, summarized in `SCD - Script Bytecode.md`. (No native builtin takes a
  String — strings only appear as relocated `printf` format pointers.)

Call counts are across the 142 US map scripts.

| ID | Name | Arguments | Returns | Handler (US) | Calls | Named |
|----|------|-----------|---------|--------------|-------|-------|
| 1 | `taskUnknown1` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x800fb43c` | 0 | placeholder |
| 2 | `randomNumberMod` | `(max: Int)` | Int | `0x801ca4d8` | 3 | legacy |
| 3 | `threadRunInBackground` | `(function: Int, arg1: Bool?, arg2: Int, arg3: Int, arg4: Int, arg5: Int)` | Int | `0x801cb3fc` | 8 | legacy |
| 4 | `systemUnknown4` | `(arg0: Int)` | Void | `0x801cb3dc` | 0 | placeholder |
| 5 | `systemUnknown5` | `(arg0: Int)` | Void | `0x801cb394` | 0 | placeholder |
| 6 | `threadWaitForCompletion` | `(threadID: Int)` | Void | `0x801cb3b8` | 6 | legacy |
| 7 | `dialogDisplaySilentMessage` | `(msgID: Int, unk1: Bool?, unk2: Bool?)` | Void | `0x801067e8` | 143 | legacy |
| 8 | `dialogWaitForMessage` | `(unk: Bool)` | Void | `0x801065b8` | 229 | legacy |
| 9 | `dialogUnknown9` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x80106394` | 0 | placeholder |
| 10 | `dialogUnknown10` | `(arg0: Int)` | Void | `0x80106080` | 0 | placeholder |
| 11 | `dialogDisplayYesNoMenu` | `()` | Int | `0x8001e184` | 212 | legacy |
| 12 | `dialogUnknown12` | `(arg0: Int, arg1: Int)` | Void | `0x8010264c` | 0 | placeholder |
| 13 | `dialogUnknown13` | `(arg0: Int)` | Void | `0x80102510` | 0 | placeholder |
| 14 | `dialogUnknown14` | `(arg0: Int)` | Void | `0x801023e4` | 0 | placeholder |
| 15 | `dialogUnknown15` | `(arg0: Int, arg1: Int)` | Void | `0x80102398` | 0 | placeholder |
| 16 | `sysUnknown16` | `()` | Void | `0x80018f30` | 1 | placeholder |
| 17 | `sysUnknown17` | `(arg0: Int, arg1: Int)` | Void | `0x800190d8` | 23 | placeholder |
| 18 | `sysUnknown18` | `()` | Void | `0x80023e5c` | 0 | placeholder |
| 19 | `sysUnknown19` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x8001bdf4` | 0 | placeholder |
| 20 | `sysUnknown20` | `()` | Void | `0x8001be38` | 1 | placeholder |
| 21 | `sysUnknown21` | `()` | Void | `0x8001fd48` | 1 | placeholder |
| 22 | `sysUnknown22` | `(arg0: Int, arg1: Int)` | Void | `0x80029760` | 1 | placeholder |
| 23 | `dialogDisplayNameEntryMenu` | `()` | Void | `0x80028fbc` | 1 | legacy |
| 24 | `dialogDisplayPCBoxMenu` | `()` | Void | `0x8003842c` | 1 | legacy |
| 25 | `openShopDialog` | `(martID: Int)` | Void | `0x8002dc6c` | 11 | legacy |
| 26 | `sysUnknown26` | `()` | Void | `0x8002d5d4` | 1 | placeholder |
| 27 | `sysUnknown27` | `()` | Void | `0x8004b7ec` | 1 | placeholder |
| 28 | `transitionBegin` | `(transitionID: Int, duration: Float)` | Void | `0x801c41c8` | 260 | legacy |
| 29 | `transitionWait` | `(unk: Bool)` | Void | `0x801c40f0` | 246 | legacy |
| 30 | `playerUnknown30` | `()` | Void | `0x8012fcd4` | 0 | placeholder |
| 31 | `playerProcessEvents` | `()` | Void | `0x8012ebd4` | 127 | legacy |
| 32 | `playerLockMovement` | `()` | Void | `0x8012bca4` | 307 | legacy |
| 33 | `playerFreeMovement` | `()` | Void | `0x8012bba8` | 298 | legacy |
| 34 | `triggerScriptFunction` | `(function: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Int)` | Void | `0x8012bad0` | 2 | legacy |
| 35 | `menuUnknown35` | `(arg0: Int)` | Void | `0x801c9f00` | 5 | placeholder |
| 36 | `cameraUnknown36` | `(arg0: Int)` | Void | `0x80177a44` | 168 | placeholder |
| 37 | `cameraUnknown37` | `(arg0: Int, arg1: Int)` | Void | `0x801779cc` | 46 | placeholder |
| 38 | `cameraUnknown38` | `(arg0: Float, arg1: Float, arg2: Float)` | Void | `0x8017697c` | 0 | placeholder |
| 39 | `cameraUnknown39` | `(arg0: Float, arg1: Float, arg2: Float)` | Void | `0x801769b0` | 0 | placeholder |
| 40 | `cameraSetPosition` | `(x: Float, y: Float, z: Float)` | Void | `0x80176948` | 128 | legacy |
| 41 | `cameraSetRotation` | `(x: Float, y: Float, z: Float)` | Void | `0x801768f0` | 128 | legacy |
| 42 | `cameraPresetFromFile` | `(groupID: Int, fileID: Int, unk1: Bool?, unk2: Bool?)` | Void | `0x80176e0c` | 18 | legacy |
| 43 | `cameraUnknown43` | `()` | Void | `0x80176ae4` | 0 | placeholder |
| 44 | `cameraUnknown44` | `()` | Void | `0x80176a94` | 0 | placeholder |
| 45 | `cameraUnknown45` | `()` | Void | `0x80176a44` | 0 | placeholder |
| 46 | `cameraUnknown46` | `(arg0: Bool?)` | Void | `0x80176b48` | 17 | placeholder |
| 47 | `characterHide` | `(resourceID: Int)` | Void | `0x801769e4` | 0 | legacy |
| 48 | `cameraUnknown48` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Float)` | Void | `0x80177760` | 5 | placeholder |
| 49 | `cameraUnknown49` | `()` | Void | `0x80177a64` | 1 | placeholder |
| 50 | `characterSetVisibility` | `(groupID: Int, resourceID: Int, visible: Bool)` | Void | `0x8018c1e8` | 643 | legacy |
| 51 | `characterSetAnimation` | `(groupID: Int, resourceID: Int, animID: Int, unk: Bool, repeat: Bool)` | Void | `0x8018b76c` | 770 | legacy |
| 52 | `characterUnknown52` | `(arg0: Int, arg1: Int)` | Void | `0x8018b220` | 0 | placeholder |
| 53 | `characterWaitForAnimation` | `(groupID: Int, resourceID: Int, unk: Bool)` | Void | `0x8018b07c` | 322 | legacy |
| 54 | `characterTalk` | `(groupID: Int, resourceID: Int, msgID: Int)` | Void | `0x80189990` | 2295 | legacy |
| 55 | `characterEndSpeech` | `(groupID: Int, resourceID: Int)` | Void | `0x80189490` | 1276 | legacy |
| 56 | `characterUnknown56` | `(arg0: Int, arg1: Int)` | Void | `0x8018e050` | 0 | placeholder |
| 57 | `characterUnknown57` | `(arg0: Int, arg1: Int)` | Void | `0x8018db68` | 0 | placeholder |
| 58 | `characterCheckWithinBounds` | `(groupID: Int, resourceID: Int, x1: Float, y1: Float, x2: Float, y2: Float)` | Int | `0x801874bc` | 94 | legacy |
| 59 | `characterSetPosition` | `(groupID: Int, resourceID: Int, x: Float, y: Float, z: Float)` | Void | `0x801860f8` | 430 | legacy |
| 60 | `characterRotateAroundAxes` | `(groupID: Int, resourceID: Int, x: Float, y: Float, z: Float)` | Void | `0x80185f44` | 255 | legacy |
| 61 | `characterMoveToPosition` | `(groupID: Int, resourceID: Int, x: Int, y: Float, z: Float, arg5: Float)` | Void | `0x80185ee8` | 267 | legacy |
| 62 | `characterWaitForMovement` | `(groupID: Int, resourceID: Int, unk: Bool)` | Void | `0x8018a280` | 618 | legacy |
| 63 | `characterClearFlags` | `(groupID: Int, resourceID: Int, flagBits: Int)` | Void | `0x8018c7c8` | 112 | legacy |
| 64 | `characterSetFlags` | `(groupID: Int, resourceID: Int, flagBits: Int)` | Void | `0x8018c69c` | 128 | legacy |
| 65 | `characterUnknown65` | `(arg0: Int, arg1: Int)` | Void | `0x80188f78` | 77 | placeholder |
| 66 | `characterMoveToPositionSlow` | `(groupID: Int, resourceID: Int, x: Int, y: Int, z: Int)` | Void | `0x80188ca0` | 64 | legacy |
| 67 | `characterUnknown67` | `(arg0: Int, arg1: Int)` | Void | `0x80188af4` | 154 | placeholder |
| 68 | `characterTurnToAngle` | `(groupID: Int, resourceID: Int, angle: Float)` | Void | `0x8018a44c` | 240 | legacy |
| 69 | `characterUnknown69` | `(arg0: Int, arg1: Int, arg2: Float)` | Void | `0x80184948` | 152 | placeholder |
| 70 | `characterAttachToCharacter` | `(groupID: Int, resourceID: Int, targetGID: Int, targetRID: Int, unk: Int)` | Void | `0x801845e4` | 19 | legacy |
| 71 | `characterUnknown71` | `(arg0: Int, arg1: Int)` | Void | `0x80184450` | 34 | placeholder |
| 72 | `characterUnknown72` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x80184190` | 54 | placeholder |
| 73 | `characterRunToPosition` | `(groupID: Int, resourceID: Int, x: Float, y: Float, z: Float)` | Void | `0x80183fc4` | 236 | legacy |
| 74 | `characterUnknown74` | `(arg0: Int, arg1: Int, arg2: Bool?)` | Void | `0x80183e5c` | 54 | placeholder |
| 75 | `characterUnknown75` | `(arg0: Int, arg1: Int)` | Void | `0x80183ce0` | 0 | placeholder |
| 76 | `characterUnknown76` | `(arg0: Int, arg1: Int)` | Void | `0x80183350` | 84 | placeholder |
| 77 | `characterUnknown77` | `(arg0: Int, arg1: Int)` | Void | `0x80183018` | 75 | placeholder |
| 78 | `flagSetFalse` | `(flag: Int)` | Void | `0x80190528` | 759 | legacy |
| 79 | `flagSetTrue` | `(flag: Int)` | Void | `0x801903b0` | 194 | legacy |
| 80 | `flagSetValue` | `(flag: Int, value: Int)` | Void | `0x8019075c` | 141 | legacy |
| 81 | `flagCheckTrue` | `(flag: Int)` | Bool | `0x801902e0` | 2389 | legacy |
| 82 | `flagGetValue` | `(flag: Int)` | Int | `0x801906a0` | 326 | legacy |
| 83 | `pokemonUnknown83` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x801d0bd0` | 14 | placeholder |
| 84 | `pokemonUnknown84` | `(arg0: Int, arg1: Int)` | Void | `0x801e03d4` | 1 | placeholder |
| 85 | `pokemonUnknown85` | `(arg0: Int, arg1: Int)` | Void | `0x801dfc30` | 1 | placeholder |
| 86 | `pokemonUnknown86` | `(arg0: Int, arg1: Int)` | Void | `0x801df790` | 1 | placeholder |
| 87 | `pokemonUnknown87` | `(arg0: Int, arg1: Int)` | Void | `0x801df474` | 1 | placeholder |
| 88 | `taskUnknown88` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x800fee68` | 0 | placeholder |
| 89 | `taskUnknown89` | `(arg0: Int, arg1: Int)` | Void | `0x800f9318` | 0 | placeholder |
| 90 | `taskUnknown90` | `(arg0: Int, arg1: Int)` | Void | `0x800e3d6c` | 0 | placeholder |
| 91 | `taskUnknown91` | `(arg0: Int, arg1: Int)` | Void | `0x800e4170` | 0 | placeholder |
| 92 | `getCurrentRoomID` | `()` | Int | `0x800ff56c` | 100 | legacy |
| 93 | `getCurrentGroupID` | `()` | Int | `0x80113f48` | 24 | legacy |
| 94 | `mapGetPreviousRoomID` | `()` | Int | `0x8011394c` | 40 | legacy |
| 95 | `mapWarpToRoom` | `(roomID: Int, entryPointID: Int)` | Void | `0x80113828` | 64 | legacy |
| 96 | `mapUnknown96` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x80116958` | 123 | placeholder |
| 97 | `mapUnknown97` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Int)` | Void | `0x80116470` | 56 | placeholder |
| 98 | `mapWarpToMenuRoom` | `(roomID: Int)` | Void | `0x800ff730` | 21 | legacy |
| 99 | `taskUnknown99` | `()` | Void | `0x800ff660` | 0 | placeholder |
| 100 | `systemUnknown100` | `(arg0: Int, arg1: Int)` | Void | `0x801cb148` | 6 | placeholder |
| 101 | `systemUnknown101` | `(arg0: Int, arg1: Float, arg2: Float, arg3: Float)` | Void | `0x801cb104` | 0 | placeholder |
| 102 | `battleStart` | `(battleID: Int)` | Void | `0x8020dad0` | 155 | legacy |
| 103 | `battleGetResult` | `()` | Int | `0x801ef634` | 198 | legacy |
| 104 | `soundSetBGM` | `(id: Int, unk: Int, volume: Int)` | Void | `0x80165a20` | 259 | legacy |
| 105 | `soundPlaySFX` | `(id: Int, unk: Int, volume: Int)` | Void | `0x801659fc` | 69 | legacy |
| 106 | `soundUnknown106` | `(arg0: Int, arg1: Int)` | Void | `0x801657f8` | 36 | placeholder |
| 107 | `soundUnknown107` | `(arg0: Int, arg1: Float, arg2: Float, arg3: Float)` | Void | `0x80165788` | 0 | placeholder |
| 108 | `soundUnknown108` | `()` | Void | `0x80165744` | 0 | placeholder |
| 109 | `soundFadeBGM` | `(volume: Int, duration: Int)` | Void | `0x80165718` | 41 | legacy |
| 110 | `systemUnknown110` | `()` | Void | `0x801cb1c4` | 0 | placeholder |
| 111 | `systemUnknown111` | `()` | Int | `0x801cb2b8` | 3 | placeholder |
| 112 | `modelGetResourceID` | `(fileID: Int)` | Int | `0x801cba0c` | 4 | legacy |
| 113 | `systemUnknown113` | `(arg0: Int)` | Void | `0x801cb9d8` | 3 | placeholder |
| 114 | `systemUnknown114` | `(arg0: Int, arg1: Bool?)` | Void | `0x801cb954` | 27 | placeholder |
| 115 | `systemUnknown115` | `(arg0: Int, arg1: Int, arg2: Bool?, arg3: Bool?)` | Void | `0x801cb834` | 50 | placeholder |
| 116 | `systemUnknown116` | `(arg0: Int)` | Void | `0x801cb7c4` | 1 | placeholder |
| 117 | `systemUnknown117` | `(arg0: Int, arg1: Bool?)` | Void | `0x801cb708` | 12 | placeholder |
| 118 | `characterSetProperty` | `(resourceID: Int, value: Bool?)` | Void | `0x801caa08` | 169 | legacy |
| 119 | `playerReceiveItem` | `(itemID: Int, quantity: Int)` | Void | `0x801caac8` | 29 | legacy |
| 120 | `systemUnknown120` | `(arg0: Int)` | Int | `0x801caa34` | 19 | placeholder |
| 121 | `systemUnknown121` | `()` | Void | `0x801ca9f0` | 0 | placeholder |
| 122 | `systemUnknown122` | `(arg0: Int)` | Void | `0x801ca9bc` | 0 | placeholder |
| 123 | `playerCountPartyPokemon` | `()` | Int | `0x801cb078` | 4 | legacy |
| 124 | `systemUnknown124` | `()` | Int | `0x801cafd4` | 3 | placeholder |
| 125 | `mapUnknown125` | `(arg0: Int, arg1: Int, arg2: Bool?)` | Void | `0x8011388c` | 8 | placeholder |
| 126 | `playerUnknown126` | `(arg0: Bool?, arg1: Bool?)` | Void | `0x8012f008` | 21 | placeholder |
| 127 | `cameraUnknown127` | `(arg0: Float, arg1: Float, arg2: Float)` | Void | `0x80179a18` | 54 | placeholder |
| 128 | `mapSetReturnMap` | `(currentRoom: Int, previousRoom: Int, warpPointIndex: Int)` | Void | `0x801141d8` | 1 | legacy |
| 129 | `systemUnknown129` | `()` | Void | `0x801cb180` | 0 | placeholder |
| 130 | `soundUnknown130` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x80165668` | 2 | placeholder |
| 131 | `characterSurpriseAnimation` | `(groupID: Int, resourceID: Int, unk: Bool)` | Void | `0x80181eb0` | 113 | legacy |
| 132 | `dialogSetMessageVar` | `(varIndex: Int, value: Int)` | Void | `0x80132a38` | 75 | legacy |
| 133 | `systemUnknown133` | `(arg0: Int)` | Void | `0x801ca940` | 7 | placeholder |
| 134 | `systemUnknown134` | `()` | Int | `0x801ca990` | 2 | placeholder |
| 135 | `mapUnknown135` | `()` | Void | `0x80117500` | 0 | placeholder |
| 136 | `mapUnknown136` | `()` | Void | `0x801174f4` | 9 | placeholder |
| 137 | `soundUnknown137` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x801656f8` | 9 | placeholder |
| 138 | `soundUnknown138` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int)` | Void | `0x8016597c` | 4 | placeholder |
| 139 | `soundUnknown139` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int)` | Void | `0x801658fc` | 0 | placeholder |
| 140 | `cameraUnknown140` | `(arg0: Bool?, arg1: Float, arg2: Float, arg3: Float, arg4: Float)` | Void | `0x801774f0` | 81 | placeholder |
| 141 | `cameraUnknown141` | `(arg0: Bool?, arg1: Float, arg2: Float, arg3: Float, arg4: Float)` | Void | `0x801773f4` | 57 | placeholder |
| 142 | `sysUnknown142` | `(arg0: Int)` | Void | `0x80097bbc` | 0 | placeholder |
| 143 | `mapUnknown143` | `(arg0: Float)` | Void | `0x80117330` | 0 | placeholder |
| 144 | `mapWarpWithTransitions` | `(beforeWarp: Int, afterWarp: Int)` | Void | `0x8011288c` | 34 | legacy |
| 145 | `battleUnknown145` | `(arg0: Int)` | Void | `0x801ef758` | 0 | placeholder |
| 146 | `battleUnknown146` | `(arg0: Int)` | Void | `0x801ef6fc` | 0 | placeholder |
| 147 | `cameraUnknown147` | `(arg0: Float)` | Void | `0x80176868` | 0 | placeholder |
| 148 | `cameraUnknown148` | `(arg0: Float)` | Void | `0x801767e0` | 0 | placeholder |
| 149 | `cameraUnknown149` | `(arg0: Float)` | Void | `0x80176758` | 0 | placeholder |
| 150 | `cameraUnknown150` | `(arg0: Float)` | Void | `0x801766a8` | 0 | placeholder |
| 151 | `characterFaceDirection` | `(groupID: Int, resourceID: Int, direction: Bool?)` | Void | `0x8018ca20` | 40 | legacy |
| 152 | `battleStartWithOptions` | `(battleID: Int, unk1: Bool, unk2: Bool)` | Void | `0x801ca5c4` | 225 | legacy |
| 153 | `soundUnknown153` | `(arg0: Int)` | Void | `0x801657d0` | 32 | placeholder |
| 154 | `characterUnknown154` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Int)` | Void | `0x8018b368` | 3 | placeholder |
| 155 | `characterUnknown155` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x80188984` | 4 | placeholder |
| 156 | `cameraUnknown156` | `(arg0: Int, arg1: Float, arg2: Float, arg3: Float, arg4: Float)` | Void | `0x801775ec` | 0 | placeholder |
| 157 | `sleep` | `(arg0: Float)` | Void | `0x801ca4f8` | 347 | legacy |
| 158 | `sysUnknown158` | `(arg0: Int)` | Int | `0x8001e00c` | 4 | placeholder |
| 159 | `systemUnknown159` | `(arg0: Int)` | Void | `0x801caea0` | 0 | placeholder |
| 160 | `cameraUnknown160` | `(arg0: Bool?)` | Void | `0x80177004` | 38 | placeholder |
| 161 | `mapUnknown161` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x8011416c` | 27 | placeholder |
| 162 | `mapUnknown162` | `()` | Void | `0x801140c8` | 7 | placeholder |
| 163 | `useCologne` | `(arg0: Int, arg1: Int)` | Void | `0x80022b3c` | 0 | legacy |
| 164 | `characterUnknown164` | `(arg0: Int, arg1: Int, arg2: Float, arg3: Float, arg4: Float, arg5: Float)` | Void | `0x80187d48` | 21 | placeholder |
| 165 | `characterFaceCharacter` | `(targetGID: Int, targetRID: Int, argGID: Int, argRID: Int, speed: Float)` | Void | `0x80187a60` | 188 | legacy |
| 166 | `systemUnknown166` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x801cb61c` | 1 | placeholder |
| 167 | `systemUnknown167` | `(arg0: Int)` | Void | `0x801cb59c` | 0 | placeholder |
| 168 | `characterUnknown168` | `(arg0: Bool?, arg1: Int)` | Void | `0x80184470` | 12 | placeholder |
| 169 | `characterUnknown169` | `(arg0: Int, arg1: Int)` | Int | `0x80186254` | 49 | placeholder |
| 170 | `characterUnknown170` | `(arg0: Int, arg1: Int, arg2: Float, arg3: Float, arg4: Float, arg5: Float, arg6: Float, arg7: Bool?)` | Int | `0x80186620` | 120 | placeholder |
| 171 | `mapUnknown171` | `(arg0: Int)` | Void | `0x80117ae4` | 29 | placeholder |
| 172 | `characterUnknown172` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x8018bdf4` | 51 | placeholder |
| 173 | `pokemonUnknown173` | `(arg0: Int)` | Void | `0x801d2080` | 23 | placeholder |
| 174 | `cutsceneUnknown174` | `()` | Void | `0x802612d0` | 0 | placeholder |
| 175 | `characterUnknown175` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Int)` | Void | `0x8018b558` | 0 | placeholder |
| 176 | `characterUnknown176` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x8018aec0` | 0 | placeholder |
| 177 | `characterUnknown177` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Float, arg5: Bool?)` | Void | `0x8018a700` | 53 | placeholder |
| 178 | `characterUnknown178` | `(arg0: Int, arg1: Int, arg2: Float)` | Void | `0x801821b8` | 14 | placeholder |
| 179 | `cameraUnknown179` | `(arg0: Float, arg1: Bool?)` | Void | `0x8017707c` | 57 | placeholder |
| 180 | `getCurrentFloorID` | `()` | Int | `0x8011393c` | 8 | legacy |
| 181 | `characterTurnHeadTowards` | `(argGID: Int, argRID: Int, targetGID: Int, targetRID: Int)` | Void | `0x80188fa0` | 85 | legacy |
| 182 | `menuUnknown182` | `(arg0: Int)` | Void | `0x801c9f5c` | 1 | placeholder |
| 183 | `systemUnknown183` | `(arg0: Int)` | Void | `0x801ca8b0` | 0 | placeholder |
| 184 | `systemUnknown184` | `()` | Void | `0x801ca884` | 0 | placeholder |
| 185 | `systemUnknown185` | `(arg0: Int)` | Void | `0x801ca858` | 0 | placeholder |
| 186 | `systemUnknown186` | `(arg0: Int)` | Void | `0x801ca7ec` | 10 | placeholder |
| 187 | `systemUnknown187` | `()` | Int | `0x801ca91c` | 5 | placeholder |
| 188 | `systemUnknown188` | `(arg0: Int)` | Void | `0x801ca8f4` | 4 | placeholder |
| 189 | `pdaUpdateStrategyMemo` | `()` | Bool | `0x801c9edc` | 2 | legacy |
| 190 | `menuUnknown190` | `(arg0: Int, arg1: Int)` | Void | `0x801c9e7c` | 6 | placeholder |
| 191 | `mapTransformElement` | `(fileID: Int, unk1: Bool, unk2: Bool, unk3: Bool)` | Void | `0x801c9dc4` | 12 | legacy |
| 192 | `menuUnknown192` | `(arg0: Int)` | Void | `0x801c9d74` | 0 | placeholder |
| 193 | `menuUnknown193` | `(arg0: Int, arg1: Int)` | Void | `0x801c9cdc` | 4 | placeholder |
| 194 | `mapBeginRelicPurifications` | `(unk1: Int, unk2: Int)` | Void | `0x8025f2c0` | 2 | legacy |
| 195 | `mapUnknown195` | `()` | Int | `0x8011392c` | 9 | placeholder |
| 196 | `menuUnknown196` | `()` | Int | `0x801c9c9c` | 1 | placeholder |
| 197 | `menuUnknown197` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int)` | Void | `0x801c9b6c` | 4 | placeholder |
| 198 | `menuEnterTradingMenu` | `()` | Void | `0x80032564` | 1 | legacy |
| 199 | `menuDisplayCustomMenu` | `(msgIDs: Int, length: Int, x: Int, y: Int, startIndex: Bool?)` | Int | `0x801c8dd0` | 24 | legacy |
| 200 | `menuUnknown200` | `()` | Int | `0x801c89f8` | 1 | placeholder |
| 201 | `sysUnknown201` | `()` | Void | `0x80035da0` | 1 | placeholder |
| 202 | `sysUnknown202` | `()` | Void | `0x80035d70` | 1 | placeholder |
| 203 | `mapUnknown203` | `(arg0: Int, arg1: Int, arg2: Bool?)` | Void | `0x80115e04` | 24 | placeholder |
| 204 | `promptDNAKeyCode` | `(sample1: Int, sample2: Int, sample3: Int)` | Int | `0x801c8688` | 1 | legacy |
| 205 | `getDNASampleSpecies` | `(sampleID: Int)` | Int | `0x801c8834` | 1 | legacy |
| 206 | `sysUnknown206` | `()` | Void | `0x80088428` | 0 | placeholder |
| 207 | `menuUnknown207` | `()` | Void | `0x801c8804` | 1 | placeholder |
| 208 | `promptDNASampleSelection` | `()` | Void | `0x801c8628` | 15 | legacy |
| 209 | `scriptCallByID` | `(scriptID: Int, arg1: Int, arg2: Int, arg3: Int, arg4: Int)` | Void | `0x801cb4a8` | 9 | legacy |
| 210 | `characterUnknown210` | `(arg0: Int, arg1: Int, arg2: Int, arg3: Int)` | Void | `0x8018bc88` | 0 | placeholder |
| 211 | `systemUnknown211` | `()` | Void | `0x801ca358` | 8 | placeholder |
| 212 | `sysUnknown212` | `()` | Int | `0x80089c10` | 3 | placeholder |
| 213 | `sysUnknown213` | `()` | Int | `0x80089b8c` | 1 | placeholder |
| 214 | `mapUnknown214` | `(arg0: Int, arg1: Int)` | Void | `0x80115d64` | 3 | placeholder |
| 215 | `sysUnknown215` | `(arg0: Int, arg1: Int)` | Void | `0x800896e8` | 1 | placeholder |
| 216 | `menuUnknown216` | `(arg0: Bool?)` | Void | `0x801c852c` | 103 | placeholder |
| 217 | `playerReceiveGiftPokemon` | `(giftPokemonID: Int)` | Int | `0x801cada8` | 1 | legacy |
| 218 | `soundPlayPokemonCry` | `(pokemon: Int)` | Void | `0x801cae80` | 33 | legacy |
| 219 | `systemUnknown219` | `(arg0: Int, arg1: Int)` | Void | `0x801caa60` | 13 | placeholder |
| 220 | `sysUnknown220` | `()` | Int | `0x80089c54` | 1 | placeholder |
| 221 | `systemUnknown221` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x801cb530` | 3 | placeholder |
| 222 | `systemUnknown222` | `(arg0: Int, arg1: Int)` | Void | `0x801cb4e8` | 0 | placeholder |
| 223 | `systemUnknown223` | `()` | Void | `0x801cbab8` | 29 | placeholder |
| 224 | `dialogDisplayMessageWithOptions` | `(msgID: Int, unk1: Bool?, unk2: Bool?, unk3: Int)` | Int | `0x80106698` | 13 | legacy |
| 225 | `systemUnknown225` | `(arg0: Bool?)` | Void | `0x801cac6c` | 9 | placeholder |
| 226 | `systemUnknown226` | `(arg0: Bool?)` | Int | `0x801caaf4` | 9 | placeholder |
| 227 | `cutsceneUnknown227` | `()` | Void | `0x8025ed4c` | 0 | placeholder |
| 228 | `soundGetCurrentBGM` | `()` | Int | `0x801653c4` | 2 | legacy |
| 229 | `systemUnknown229` | `(arg0: Bool?)` | Void | `0x801cba90` | 9 | placeholder |
| 230 | `cutsceneUnknown230` | `()` | Void | `0x80266250` | 0 | placeholder |
| 231 | `characterUnknown231` | `(arg0: Int, arg1: Int, arg2: Bool?)` | Void | `0x80181478` | 8 | placeholder |
| 232 | `menuUnknown232` | `(arg0: Int, arg1: Int)` | Void | `0x801c7730` | 49 | placeholder |
| 233 | `systemUnknown233` | `()` | Void | `0x801cada0` | 0 | placeholder |
| 234 | `systemUnknown234` | `()` | Void | `0x801cad18` | 1 | placeholder |
| 235 | `menuShowSaveMenu` | `(unk: Bool)` | Bool | `0x801c766c` | 1 | legacy |
| 236 | `playerGetCouponsThisRun` | `()` | Int | `0x801ca7cc` | 18 | legacy |
| 237 | `systemUnknown237` | `(arg0: Int)` | Void | `0x801ca7ac` | 0 | placeholder |
| 238 | `systemUnknown238` | `(arg0: Int)` | Void | `0x801ca728` | 0 | placeholder |
| 239 | `playerGetCouponsLastArea` | `()` | Int | `0x801ca708` | 9 | legacy |
| 240 | `sysUnknown240` | `()` | Void | `0x800979ec` | 1 | placeholder |
| 241 | `mapActivateParticleEffects` | `()` | Void | `0x8025e5f4` | 1 | legacy |
| 242 | `playerCountPurifiablePokemon` | `()` | Int | `0x801caf0c` | 2 | legacy |
| 243 | `battleUnknown243` | `(arg0: Int, arg1: Int)` | Void | `0x801ee67c` | 6 | placeholder |
| 244 | `cutsceneUnknown244` | `(arg0: Float, arg1: Float, arg2: Float, arg3: Float, arg4: Float, arg5: Float)` | Void | `0x8025e1bc` | 11 | placeholder |
| 245 | `sysUnknown245` | `(arg0: Bool?, arg1: Int, arg2: Int, arg3: Bool?)` | Int | `0x8001e074` | 9 | placeholder |
| 246 | `mapUnknown246` | `(arg0: Int, arg1: Int, arg2: Int)` | Void | `0x801140dc` | 1 | placeholder |
