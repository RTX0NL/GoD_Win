import Foundation
import Wii

public struct PBREngine {
    // Stub — will be expanded when PBR support is implemented. The
    // cross-game `Pokemon` engine is a separate `Engine` conformer
    // and is loaded into PBR projects independently by `ProjectSetup`.
}

public enum PokemonBattleRevolution {
    public static let gameIDUS = "RPBE"
    public static let gameIDEU = "RPBP"
    public static let gameIDJP = "RPBJ"

    public static let gameIDs = [
        gameIDUS,
        gameIDEU,
        gameIDJP
    ]
}
