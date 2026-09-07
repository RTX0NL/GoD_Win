import GoDFoundation
import GoDEngine
import Structs
import Pokemon

public extension ColosseumEngine {
    struct Enums: EngineEnums {
        public private(set) var entries: [Enum] = Enums.allItems

        public init(unchecked items: [Enum]) {
            self.entries = items
        }

        static public var allItems: [Enum] {
            [
                ColoScriptEnumDefaults.battleResult,
                ColoScriptEnumDefaults.transitionID,
                ColoScriptEnumDefaults.buttonInput,
                ColoScriptEnumDefaults.language,
                ColoScriptEnumDefaults.yesNoIndex,
                ColoScriptEnumDefaults.groupID,
                ColoScriptEnumDefaults.characterRID,
                ColoSaveEnumDefaults.gender,
                ColoSaveEnumDefaults.region,
                ColoSaveEnumDefaults.gameVersion,
                ColoSaveEnumDefaults.abilitySlot,
                // A game engine carries every enum its own structs
                // reference, so `getStruct` resolves standalone — the save
                // structs are read through this engine alone, not through the
                // combined engine the typed-data path builds. Declared in the
                // Pokemon module (they are Pokemon data, and PBR needs its own
                // set) but owned here, because the numbering is this game's:
                // Deoxys is species 410 here and 386 in Battle Revolution.
                PokemonEnumDefaults.colosseumSpeciesEnum,
                PokemonEnumDefaults.colosseumMovesEnum,
                PokemonEnumDefaults.colosseumItemsEnum,
                PokemonEnumDefaults.typesEnum,
                PokemonEnumDefaults.coloXdAbilitiesEnum,
                PokemonEnumDefaults.coloXdMoveTargetEnum,
                PokemonEnumDefaults.coloXdMoveCategoryEnum,
                PokemonEnumDefaults.coloXdMoveEffectTypeEnum,
                PokemonEnumDefaults.coloXdContestCategoryEnum,
                PokemonEnumDefaults.coloXdItemPocketEnum,
            ]
        }
    }
}
