import GoDFoundation
import GoDEngine
import Structs

/// Namespace for Pokémon engine enum defaults.
public enum PokemonEnumDefaults {}

public extension PokemonEngine {
    struct Enums: EngineEnums {
        public private(set) var entries: [Enum] = Enums.allItems

        public init(unchecked items: [Enum]) {
            self.entries = items
        }

        /// Static enums seeded into every Pokémon engine. Today only the
        /// small fixed-cardinality ones are bundled; species / moves /
        /// items / abilities will land here as their lists are vetted.
        public static var allItems: [Enum] {
            [
                PokemonEnumDefaults.gendersEnum,
                PokemonEnumDefaults.naturesEnum,
                PokemonEnumDefaults.typesEnum,
                PokemonEnumDefaults.eggGroupsEnum,
                PokemonEnumDefaults.expRatesEnum,
                PokemonEnumDefaults.shadowAggressionEnum,
            ]
        }
    }
}
