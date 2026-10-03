import GoDFoundation
import GoDEngine
import Structs

/// Namespace for XD struct defaults
public enum XDStructDefaults {}

public extension XDEngine {
    struct Structs: EngineStructs {
        enum Defaults {}

        public private(set) var entries: [StructMap] = Structs.allItems

        public init(unchecked items: [StructMap]) {
            self.entries = items
        }

        static public var allItems: [StructMap] {
            [
                // DOL structs
                XDStructDefaults.abilityStruct,
                XDStructDefaults.statusEffectStruct,
                XDStructDefaults.tmStruct,
                XDStructDefaults.menuDataStruct,
                XDStructDefaults.pkxModelStruct,
                XDStructDefaults.shinyPKXModelStruct,
                XDStructDefaults.wzxAnimationStruct,
                XDStructDefaults.wzxMoveAnimationStruct,
                XDStructDefaults.textureInfoStruct,
                XDStructDefaults.textureStruct,
                XDStructDefaults.textureJPStruct,
                XDStructDefaults.characterModelStruct,
                // common.rel structs
                XDStructDefaults.moveStruct,
                XDStructDefaults.itemStruct,
                XDStructDefaults.natureStruct,
                XDStructDefaults.typeStruct,
                XDStructDefaults.trainerClassStruct,
                XDStructDefaults.multiplierStruct,
                XDStructDefaults.treasureStruct,
                XDStructDefaults.doorStruct,
                XDStructDefaults.interactionPointStruct,
                XDStructDefaults.battleFieldStruct,
                XDStructDefaults.battleFieldEUStruct,
                XDStructDefaults.battleLayoutStruct,
                XDStructDefaults.pokefaceStruct,
                XDStructDefaults.aiWeightEffectStruct,
                XDStructDefaults.pokemonAIRoleStruct,
                XDStructDefaults.tutorMoveStruct,
                XDStructDefaults.validItemStruct,
                XDStructDefaults.soundFileStruct,
                XDStructDefaults.soundMetadataStruct,
                XDStructDefaults.peopleIDStruct,
                XDStructDefaults.battleTypeStruct,
                XDStructDefaults.rgbaColorStruct,
                XDStructDefaults.pokemonMenuAnimationStruct,
                XDStructDefaults.pokemonBaseStatsStruct,
                XDStructDefaults.pokemonEvolutionStruct,
                XDStructDefaults.pokemonLevelUpMoveStruct,
                XDStructDefaults.pokemonSpriteStruct,
                XDStructDefaults.pokemonStatStruct,
                XDStructDefaults.battlePlayerStruct,
                XDStructDefaults.battleStruct,
                XDStructDefaults.battleEUStruct,
                XDStructDefaults.pokespotStruct,
                XDStructDefaults.pokespotEncounterStruct,
                XDStructDefaults.roomStruct,
                XDStructDefaults.roomJPStruct,
                XDStructDefaults.generalFlagStruct,
                // Deck structs (per trainer deck file)
                XDStructDefaults.deckTrainerStruct,
                XDStructDefaults.deckTrainerPokemonStruct,
                XDStructDefaults.deckTrainerAIStruct,
                XDStructDefaults.deckShadowPokemonStruct,
                // Save sub-block structs
                XDStructDefaults.saveWazaStruct,
                XDStructDefaults.saveItemStruct,
                XDStructDefaults.savePokemonStruct,
                XDStructDefaults.saveSlotHeaderStruct,
                XDStructDefaults.saveConfigStruct,
                XDStructDefaults.saveTrainer1Struct,
                XDStructDefaults.saveBoxStruct,
                XDStructDefaults.savePCBoxStruct,
                XDStructDefaults.saveDaycareStruct,
                XDStructDefaults.saveMemoEntryStruct,
                XDStructDefaults.saveStrategyMemoStruct,
                XDStructDefaults.saveBattleRuleStruct,
                XDStructDefaults.saveBattleModeStruct,
                XDStructDefaults.saveShadowPokemonStruct,
                // Sections identified from the game's own savedata BIOS
                // (see "XD save sections" in CLAUDE.md).
                XDStructDefaults.saveMailboxStruct,
                XDStructDefaults.saveFlagsStruct,
                XDStructDefaults.saveFlagsTailStruct,
                XDStructDefaults.saveExRibbonStruct,
                XDStructDefaults.saveReliveStageStruct,
                XDStructDefaults.saveReliveStruct,
                XDStructDefaults.saveAnywaySaveHeaderStruct,
                // Japanese-build variants of the four sections whose
                // layout the international releases widened. Registered
                // unconditionally — which set a save actually uses is
                // `Data.sectionStructTypes`, chosen per region by
                // `XDEngine.defaultEngine(forGameID:)`.
                XDStructDefaults.saveConfigStructJP,
                XDStructDefaults.savePCBoxStructJP,
                XDStructDefaults.saveBattleRuleStructJP,
                XDStructDefaults.saveBattleModeStructJP,
                XDStructDefaults.saveShadowPokemonStructJP,
                // map REL floor tables
                XDStructDefaults.floorCharacterStruct,
                XDStructDefaults.floorPositionStruct,
                XDStructDefaults.floorRenderDataStruct,
                XDStructDefaults.floorRenderData4CStruct,
                XDStructDefaults.floorRenderDataColosseumFormatStruct,
                XDStructDefaults.floorFieldCameraStruct,
                XDStructDefaults.floorOffscreenDataStruct,
                XDStructDefaults.floorBerryStruct,
                XDStructDefaults.contestEffectStruct,
                XDStructDefaults.pokespotAppearanceStruct,
                XDStructDefaults.orreColosseumBattleStruct,
                XDStructDefaults.battleSideStruct,
                XDStructDefaults.legendaryPokemonStruct,
                XDStructDefaults.ballSpriteStruct,
                XDStructDefaults.heartGaugeChangeStruct,
                XDStructDefaults.colosseumFormatPokemonStatStruct,
                XDStructDefaults.menuSoundsStruct,
                XDStructDefaults.messageSoundStruct,
                XDStructDefaults.soundTestEntryStruct,
                XDStructDefaults.tableResEntryStruct,
                XDStructDefaults.shopCouponDialogStruct,
                XDStructDefaults.shopGreetingDialogStruct,
                XDStructDefaults.roomSoundStruct,
                XDStructDefaults.ribbonStruct,
                XDStructDefaults.purificationChamberSettingsStruct,
                XDStructDefaults.tutorialEntryStruct,
                XDStructDefaults.flagItemStruct,
                XDStructDefaults.flagPartyStruct,
                XDStructDefaults.flagValueStruct,
                XDStructDefaults.battleBingoPokemonStruct,
                XDStructDefaults.battleBingoMysteryPanelStruct,
                XDStructDefaults.battleBingoStruct,
                XDStructDefaults.battleCDItemStruct,
                XDStructDefaults.battleCDStruct,
                XDStructDefaults.mirorBPlaceStruct,
                XDStructDefaults.mirorBStruct,
                XDStructDefaults.storyCheckpointStruct,
                XDStructDefaults.worldMapLocationStruct,
                XDStructDefaults.shopStruct,
                XDStructDefaults.shopGoodsEntryStruct,
            ]
        }
    }
}

public extension XDEngine {
    // struct definition accessors
}
