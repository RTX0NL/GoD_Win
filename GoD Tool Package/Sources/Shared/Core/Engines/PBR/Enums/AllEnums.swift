import GoDFoundation
import GoDEngine
import Structs

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
            ]
        }
    }
}
