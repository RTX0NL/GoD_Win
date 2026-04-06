import Foundation

/// Collision type for overworld character models.
/// Extracted from flags byte bits 3:2 via peopleInfoBiosGetColType.
public enum CharacterCollisionType: Int, CaseIterable {
    case none = 0
    case cylinder = 1
    case sphere = 2
    case unknown3 = 3
}

/// Predefined motion types for character models.
/// Mapped by peopleInfoBiosGetMotion switch table.
public enum CharacterMotionType: Int, CaseIterable {
    case idle = 0          // motion 3, loops
    case walk = 1          // motion 5, loops
    case run = 2           // motion 8, loops
    case turnAround = 3    // motion 11, no loop
    case interact = 4      // motion 12, loops
    case surprised = 5     // motion 13, no loop
    case unknown6 = 6      // motion 39, loops
    case unknown7 = 7      // motion 40, no loop
}

/// Talk sound effect type for character models.
/// Extracted from flags byte bits 7:5 via peopleInfoBiosGetTalkSe.
/// 3-bit field supporting values 0-7.
public enum CharacterTalkSoundEffect: Int, CaseIterable {
    case none = 0
    case type1 = 1
    case type2 = 2
    case type3 = 3
    case type4 = 4
    case type5 = 5
    case type6 = 6
    case type7 = 7
}
