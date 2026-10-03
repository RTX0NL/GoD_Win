import GoDFoundation
import GoDEngine
import Structs

public enum PokemonStructDefaults {}

public extension PokemonEngine {
    struct Structs: EngineStructs {
        public private(set) var entries: [StructMap] = Structs.allItems

        public init(unchecked items: [StructMap]) {
            self.entries = items
        }

        public static var allItems: [StructMap] {
            [
                PokemonStructDefaults.trainerAIStruct,
                PokemonStructDefaults.trainerTeamSlotStruct,
                PokemonStructDefaults.trainerStruct,
            ]
        }
    }
}
