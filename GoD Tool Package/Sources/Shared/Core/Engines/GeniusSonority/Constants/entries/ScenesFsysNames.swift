import GoDFoundation

extension GeniusSonorityEngine.Data.FSYS {

    // MARK: - XD Scene FSYS Names

    /// Cutscenes and camera demos. Each is a self-contained staging of a
    /// place the game already ships — its own build of the map model, its own
    /// camera set — so its files go to a folder of their own rather than on
    /// top of the versions the live map and menu archives use.
    ///
    /// Measured: `ending_Scene04`/`05_1`/`05_2` carry their own `M6_out` map
    /// model, and the move demos their own `worldmap_menu.rel`.
    static let defaultXDSceneFsysNames: [String] = [
        "ending_Scene01",
        "ending_Scene02",
        "ending_Scene03",
        "ending_Scene04",
        "ending_Scene05_1",
        "ending_Scene05_2",
        "ending_Scene06_1",
        "ending_Scene06_2",
        "ending_Scene06_3",
        "ending_Scene07",
        "ending_Scene08",
        "ending_Scene09",
        "ending_Scene10",
        "ending_Scene11",
        "ending_Scene12_1",
        "ending_Scene12_2",
        "ending_SpecialScene01",
        "ending_SpecialScene02",
        "mechkyogre_movedemo",
        "worldmap_movedemo",
    ]
}
