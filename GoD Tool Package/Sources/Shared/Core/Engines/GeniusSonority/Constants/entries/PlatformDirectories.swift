import GoDFoundation

extension GeniusSonorityEngine.Data.FSYS {

    // MARK: - PBR Platform Directories

    /// Battle Revolution's copies of the Wii Home Menu library — the overlay
    /// the console draws when the HOME button is pressed, which the Revolution
    /// SDK ships and every Wii title carries its own copy of.
    ///
    /// The disc holds two versions side by side and loads whichever matches
    /// the installed System Menu, so the same thirteen filenames appear twice.
    /// Four of the thirteen are byte-identical across the pair
    /// (`SpeakerSe.arc`, `home.csv`, `home_nosave.csv`, `homeBtnIcon.tpl`);
    /// the rest genuinely differ, so the directory has to survive into the
    /// project or one version overwrites the other.
    ///
    /// Identical on all three discs — US, PAL and JP each ship exactly
    /// `HomeButton2` and `HomeButton3`.
    static let defaultPBRPlatformDirectories: [String] = [
        "hb/HomeButton2",
        "hb/HomeButton3",
    ]
}
