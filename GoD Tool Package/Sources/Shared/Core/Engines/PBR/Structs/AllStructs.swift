import GoDFoundation
import GoDEngine
import Structs

/// Namespace for PBR engine struct defaults.
public enum PBRStructDefaults {}

public extension PBREngine {
    struct Structs: EngineStructs {
        public private(set) var entries: [StructMap] = Structs.allItems

        public init(unchecked items: [StructMap]) {
            self.entries = items
        }

        public static var allItems: [StructMap] {
            [
                // common.fsys container format
                PBRStructDefaults.commonTableHeaderStruct,
                PBRStructDefaults.commonTableNameRecordStruct,
                PBRStructDefaults.commonTableStringHeaderStruct,
                PBRStructDefaults.commonTableRelocationStruct,

                // Pokémon model table (index 6) and its body maps
                PBRStructDefaults.pokemonModelStruct,
                PBRStructDefaults.modelBoneMapStruct,
                PBRStructDefaults.modelAnimationMapStruct,

                // Per-species tables
                PBRStructDefaults.pokemonStatsStruct,
                PBRStructDefaults.pokemonStatsJPStruct,
                PBRStructDefaults.evolutionStruct,
                PBRStructDefaults.pokemonEvolutionsStruct,
                PBRStructDefaults.levelUpMoveStruct,
                PBRStructDefaults.levelUpMovesStruct,
                PBRStructDefaults.pokemonIconStruct,
                PBRStructDefaults.pokemonFaceStruct,
                PBRStructDefaults.pokemonBodyStruct,
                PBRStructDefaults.abilityMessageIDsStruct,

                // Battle system tables
                PBRStructDefaults.moveStruct,
                PBRStructDefaults.itemStruct,
                PBRStructDefaults.tmStruct,
                PBRStructDefaults.typeMatchupStruct,
                PBRStructDefaults.experienceTableStruct,

                // Trainer tables
                PBRStructDefaults.trainerModelStruct,
                PBRStructDefaults.trainerCustomisationStruct,
                PBRStructDefaults.trainerTitleStruct,

                // Colosseum / shop tables
                PBRStructDefaults.colosseumTrainerDeckStruct,
                PBRStructDefaults.colosseumPokemonDecksStruct,
                PBRStructDefaults.colosseumStruct,
                PBRStructDefaults.pokeCouponRewardStruct,

                // Tables the legacy tool never typed — layouts recovered from
                // the game's own field accessors plus column analysis of the
                // real disc. See MiscTableStructs.swift.
                PBRStructDefaults.countryStruct,
                PBRStructDefaults.colosseumQuoteSetStruct,
                PBRStructDefaults.colosseumsUnknownStruct,

                // Japanese-disc variants of the two tables whose layout the
                // international release changed. Both differ only by the
                // width of a per-language array, so they sit beside their
                // US/PAL counterparts rather than replacing them.
                PBRStructDefaults.countryJapaneseStruct,
                PBRStructDefaults.colosseumsUnknownJapaneseStruct,

                PBRStructDefaults.pokemonModelEffectStruct,
                PBRStructDefaults.ballModelStruct,
                PBRStructDefaults.fightAIBattlePassStruct,
                PBRStructDefaults.fightAIExpectDataStruct,
                PBRStructDefaults.fightAIPokemonPartDataStruct,
                PBRStructDefaults.fightAIValueStruct,
                PBRStructDefaults.fightAIMoveDataStruct,
                PBRStructDefaults.flagIDStruct,
                PBRStructDefaults.floorEventStruct,
                PBRStructDefaults.menuBattleRuleStruct,
                PBRStructDefaults.trainerCustomTableEntryStruct,
                PBRStructDefaults.trainerEventStruct,
                PBRStructDefaults.tutorialDataStruct,

                // deck.fsys tables (dckp / dckt / dcka) and their sub-structs
                PBRStructDefaults.deckHeaderStruct,
                PBRStructDefaults.trainerDeckMessagesStruct,
                PBRStructDefaults.trainerDeckAppearanceStruct,
                PBRStructDefaults.trainerDeckPoolStruct,
                PBRStructDefaults.trainerDeckStruct,
                PBRStructDefaults.pokemonDeckStatsStruct,
                PBRStructDefaults.pokemonDeckEVsStruct,
                PBRStructDefaults.pokemonDeckStruct,
                PBRStructDefaults.aiDeckStruct,
            ]
        }
    }
}
