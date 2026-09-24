import GoDFoundation

extension GeniusSonorityEngine.Data.FSYS {

    // MARK: - XD Misc FSYS Names

    /// Archives that don't belong to the map / menu / battlefield categories
    /// and hold their own copies of files those categories also ship. Each
    /// gets a standalone folder so its versions can't land on top of the ones
    /// the game actually loads.
    ///
    /// Measured collisions these resolve on the XD discs: `worldmap`'s map
    /// snapshots against `world_map`'s, and the cave archives' Poké Ball
    /// models against `people_archive`'s (`ball_net.dat` is 7,075 bytes in
    /// `M2_cave_1F_1` and 21,383 in `people_archive`).
    static let defaultXDMiscFsysNames: [String] = [
        // Leftover Colosseum battle maps, which keep the old layout.
        "B1_1",
        "B1_2",
        "B1_3",
        "B1_4",
        "B1_5",
        "B1_6",
        "B1_7",
        // The Mt. Battle cave set.
        "M2_cave_1F_1",
        "M2_cave_1F_2",
        "M2_cave_2F_1",
        "M2_cave_2F_2",
        "M2_cave_3F_1",
        "M2_cave_3F_1_bf",
        "M2_cave_3F_2",
        // The one without the underscore — `world_map` is the live one.
        "worldmap",
        // Development leftovers.
        "TEST000",
        "TEST001",
        "TEST002",
        "TEST003",
        "TEST004",
        "Script_test",
        "tv_test",
        "debug_menu",
        // Bonus-disc / e-Reader extras.
        "ex_coupon",
        "ex_shrine",
        "ex_title",
        "ex_top",
        "keydisc",
        // The move viewer, which ships its own `fight.msg`, font and copy of
        // the M1 water colosseum map rather than sharing the live ones.
        "waza_viewer",
    ]

    // MARK: - Colosseum Misc FSYS Names

    /// Colosseum has no test or bonus-disc leftovers of its own; the move
    /// viewer is the one archive that carries private copies of shared files.
    static let defaultColoMiscFsysNames: [String] = [
        "waza_viewer",
    ]
}
