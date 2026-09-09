import GoDFoundation
import GoDEngine
import Structs
import Pokemon

public extension XDEngine {
    struct Enums: EngineEnums {
        public private(set) var entries: [Enum] = Enums.allItems

        public init(unchecked items: [Enum]) {
            self.entries = items
        }

        static public var allItems: [Enum] {
            [
                XDSaveEnumDefaults.gender,
                XDSaveEnumDefaults.language,
                XDSaveEnumDefaults.region,
                XDSaveEnumDefaults.gameVersion,
                XDSaveEnumDefaults.statusCondition,
                // A game engine carries every enum its own structs
                // reference, so `getStruct` resolves standalone — the save
                // structs are read through this engine alone, not through the
                // combined engine the typed-data path builds. Declared in the
                // Pokemon module (they are Pokemon data, and PBR needs its own
                // set) but owned here, because the numbering is this game's:
                // Deoxys is species 410 here and 386 in Battle Revolution.
                PokemonEnumDefaults.xdSpeciesEnum,
                PokemonEnumDefaults.xdMovesEnum,
                PokemonEnumDefaults.xdItemsEnum,
                PokemonEnumDefaults.typesEnum,
                PokemonEnumDefaults.coloXdAbilitiesEnum,
                PokemonEnumDefaults.coloXdMoveTargetEnum,
                PokemonEnumDefaults.coloXdMoveCategoryEnum,
                PokemonEnumDefaults.coloXdMoveEffectTypeEnum,
                PokemonEnumDefaults.coloXdContestCategoryEnum,
                PokemonEnumDefaults.coloXdItemPocketEnum,
                // Species-data fields (PokemonStat) — shared encodings,
                // declared in the Pokemon module for the same reason.
                PokemonEnumDefaults.expRatesEnum,
                PokemonEnumDefaults.genderRatiosEnum,
                PokemonEnumDefaults.evolutionMethodsEnum,
                // Battle table (fightEncountData) — XD's own value sets.
                XDCommonRelEnumDefaults.battleKind,
                XDCommonRelEnumDefaults.battleStyle,
                XDCommonRelEnumDefaults.deck,
                XDCommonRelEnumDefaults.battleController,
                XDCommonRelEnumDefaults.roomKind,
            ]
        }
    }
}
