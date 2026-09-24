import GoDFoundation
import GoDEngine
import Structs

public extension ColosseumEngine {
    struct Structs: EngineStructs {
        public private(set) var entries: [StructMap] = Structs.allItems

        public init(unchecked items: [StructMap]) {
            self.entries = items
        }

        static public var allItems: [StructMap] {
            [
                ColosseumStructDefaults.saveSlotHeaderStruct,
                ColosseumStructDefaults.characterModelStruct,
                // main.dol tables
                ColosseumStructDefaults.abilityStruct,
                ColosseumStructDefaults.statusEffectStruct,
                ColosseumStructDefaults.tmStruct,
                ColosseumStructDefaults.typeStruct,
                ColosseumStructDefaults.itemStruct,
                ColosseumStructDefaults.validItemStruct,
                ColosseumStructDefaults.textureInfoStruct,
                ColosseumStructDefaults.textureStruct,
                ColosseumStructDefaults.textureEUStruct,
                ColosseumStructDefaults.textureRenderingStruct,
                ColosseumStructDefaults.pkxModelStruct,
                ColosseumStructDefaults.unownPKXModelStruct,
                ColosseumStructDefaults.shinyPKXModelStruct,
                ColosseumStructDefaults.wzxMoveAnimationStruct,
                // common.rel tables
                ColosseumStructDefaults.legendaryPokemonStruct,
                ColosseumStructDefaults.pokefaceStruct,
                ColosseumStructDefaults.peopleIDStruct,
                ColosseumStructDefaults.trainerClassStruct,
                ColosseumStructDefaults.keyboardCharacterStruct,
                ColosseumStructDefaults.battleStyleStruct,
                ColosseumStructDefaults.multiplierStruct,
                ColosseumStructDefaults.metLocationStruct,
                ColosseumStructDefaults.soundFileStruct,
                ColosseumStructDefaults.aiWeightEffectStruct,
                ColosseumStructDefaults.pokemonAIRoleStruct,
                ColosseumStructDefaults.treasureStruct,
                ColosseumStructDefaults.doorStruct,
                ColosseumStructDefaults.interactionPointStruct,
                ColosseumStructDefaults.battleTypeStruct,
                ColosseumStructDefaults.battleFieldStruct,
                ColosseumStructDefaults.battleFieldEUStruct,
                ColosseumStructDefaults.battlePlayerStruct,
                ColosseumStructDefaults.battleStruct,
                ColosseumStructDefaults.battleEUStruct,
                ColosseumStructDefaults.trainerStruct,
                ColosseumStructDefaults.pokemonIVsStruct,
                ColosseumStructDefaults.trainerPokemonMoveStruct,
                ColosseumStructDefaults.trainerPokemonStruct,
                ColosseumStructDefaults.trainerAIDataStruct,
                ColosseumStructDefaults.shadowPokemonFlagsStruct,
                ColosseumStructDefaults.shadowDataStruct,
                ColosseumStructDefaults.roomScriptFunctionStruct,
                ColosseumStructDefaults.roomStruct,
                ColosseumStructDefaults.roomEUStruct,
                ColosseumStructDefaults.moveStruct,
                ColosseumStructDefaults.natureStruct,
                ColosseumStructDefaults.pokemonBaseStatsStruct,
                ColosseumStructDefaults.pokemonEvolutionStruct,
                ColosseumStructDefaults.pokemonLevelUpMoveStruct,
                ColosseumStructDefaults.pokemonSpriteStruct,
                ColosseumStructDefaults.pokemonStatStruct,
                // Native callStandard dispatch table entry (DOL data section)
                ColosseumStructDefaults.scriptBuiltinFunctionStruct,
                // Pokemon record — referenced by Trainer1 / PCBox /
                // Daycare via .subStruct(name: "ColoPokemon"); its move
                // slots reference ColoWaza.
                ColosseumStructDefaults.saveWazaStruct,
                ColosseumStructDefaults.savePokemonStruct,
                // Save-slot sections — every Colo section has a
                // struct binding so its length can be derived.
                ColosseumStructDefaults.saveConfigStruct,
                ColosseumStructDefaults.saveTrainer1Struct,
                ColosseumStructDefaults.saveBoxStruct,
                ColosseumStructDefaults.savePCBoxStruct,
                ColosseumStructDefaults.saveItemStruct,
                ColosseumStructDefaults.saveMailboxStruct,
                ColosseumStructDefaults.savePCItemsMailboxStruct,
                ColosseumStructDefaults.saveDaycareStruct,
                ColosseumStructDefaults.saveMemoEntryStruct,
                ColosseumStructDefaults.saveStrategyMemoStruct,
                ColosseumStructDefaults.saveBattleEntryStruct,
                ColosseumStructDefaults.saveShadowMonitorStruct,
                ColosseumStructDefaults.saveTailStruct,
            ]
        }
    }
}

public extension ColosseumEngine {
    // struct definition accessors
}
