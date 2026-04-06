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
                XDStructDefaults.characterModelStruct,
            ]
        }
    }
}

public extension XDEngine {
    // struct definition accessors
}
