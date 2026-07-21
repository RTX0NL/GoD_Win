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
                ColosseumStructDefaults.characterModelStruct,
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
                ColosseumStructDefaults.saveTailStruct,
            ]
        }
    }
}

public extension ColosseumEngine {
    // struct definition accessors
}
