import Structs
import GoDFoundation

/// Namespace for XD struct defaults
public enum XDStructDefaults {}

/// All struct definitions for the XD engine
public struct XDStructs: EngineStructs {
    public var entries: [StructMap]

    public static var allItems: [StructMap] {
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

    public init(unchecked items: [StructMap]) {
        self.entries = items
    }
}
