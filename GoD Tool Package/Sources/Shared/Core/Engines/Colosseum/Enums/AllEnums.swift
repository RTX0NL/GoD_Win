import GoDFoundation
import GoDEngine
import Structs

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
            ]
        }
    }
}
