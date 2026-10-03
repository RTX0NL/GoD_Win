import GoDFoundation
import Dolphin

enum NKitDump {
    struct Config: Codable {
        /// Path to the `.nkit.iso` input.
        let nkitPath: File
        /// Where to write the restored raw ISO.
        let isoPath: File
        let overwrite: Bool

        init(nkitPath: File, isoPath: File, overwrite: Bool = true) {
            self.nkitPath = nkitPath
            self.isoPath = isoPath
            self.overwrite = overwrite
        }
    }
}

enum NKitBuild {
    struct Config: Codable {
        /// Path to the raw GameCube ISO input.
        let isoPath: File
        /// Where to write the `.nkit.iso` output.
        let nkitPath: File
        /// Four-character Game ID to seed the disc's junk PRNG with,
        /// for the rare disc whose padding was written under another
        /// title's ID. Nil — the normal case — uses the disc's own.
        /// Recorded in the NKit header so a restore reads the same
        /// stream.
        let junkOverrideID: String?
        let overwrite: Bool

        init(isoPath: File, nkitPath: File, junkOverrideID: String? = nil, overwrite: Bool = true) {
            self.isoPath = isoPath
            self.nkitPath = nkitPath
            self.junkOverrideID = junkOverrideID
            self.overwrite = overwrite
        }
    }
}
