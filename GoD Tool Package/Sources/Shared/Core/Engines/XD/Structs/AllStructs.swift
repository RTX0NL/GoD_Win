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
                // DOL structs
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
                // common.rel structs
                XDStructDefaults.moveStruct,
                XDStructDefaults.itemStruct,
                XDStructDefaults.natureStruct,
                XDStructDefaults.typeStruct,
                XDStructDefaults.trainerClassStruct,
                XDStructDefaults.multiplierStruct,
                XDStructDefaults.treasureStruct,
                XDStructDefaults.doorStruct,
                XDStructDefaults.interactionPointStruct,
                XDStructDefaults.battleFieldStruct,
                XDStructDefaults.battleLayoutStruct,
                XDStructDefaults.pokefaceStruct,
                XDStructDefaults.aiWeightEffectStruct,
                XDStructDefaults.pokemonAIRoleStruct,
                XDStructDefaults.tutorMoveStruct,
                XDStructDefaults.validItemStruct,
                XDStructDefaults.soundFileStruct,
                XDStructDefaults.soundMetadataStruct,
                XDStructDefaults.peopleIDStruct,
                XDStructDefaults.battleTypeStruct,
                XDStructDefaults.rgbaColourStruct,
                XDStructDefaults.pokemonMenuAnimationStruct,
            ]
        }
    }
}

public extension XDEngine {
    // struct definition accessors
}
