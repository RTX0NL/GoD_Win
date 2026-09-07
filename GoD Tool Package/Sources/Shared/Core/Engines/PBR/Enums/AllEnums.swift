import GoDFoundation
import GoDEngine
import Structs
import Pokemon

/// Namespace for PBR engine enum defaults.
public enum PBREnumDefaults {}

public extension PBREngine {
    struct Enums: EngineEnums {
        public private(set) var entries: [Enum] = Enums.allItems

        public init(unchecked items: [Enum]) {
            self.entries = items
        }

        public static var allItems: [Enum] {
            [
                PBREnumDefaults.commonTableIndex,
                PBREnumDefaults.commonTableIndexJP,
                PBREnumDefaults.modelBoneSlot,
                PBREnumDefaults.modelAnimationSlot,
                // Carried here as well as in the Pokemon engine, because the
                // common-table structs name them and `getStruct` only ever
                // consults one engine's own enums — the `structs:` parameter
                // on `typeCommonTable` covers the cross-engine case, but the
                // engine still has to resolve standalone.
                PokemonEnumDefaults.pbrSpeciesEnum,
                PokemonEnumDefaults.pbrMovesEnum,
                PokemonEnumDefaults.pbrItemsEnum,
                PokemonEnumDefaults.typesEnum,
                PokemonEnumDefaults.pbrAbilitiesEnum,
                PokemonEnumDefaults.pbrMoveTargetEnum,
                PokemonEnumDefaults.pbrMoveCategoryEnum,
                PokemonEnumDefaults.pbrMoveEffectTypeEnum,
            ]
        }
    }
}
