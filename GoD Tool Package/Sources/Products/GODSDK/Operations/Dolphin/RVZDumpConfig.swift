import GoDFoundation
import Dolphin

enum RVZDump {
    struct Config: Codable {
        /// Path to the `.rvz` or `.wia` input. Which one it is comes from
        /// the file's own magic, not the extension — Dolphin reads either
        /// under either name.
        let rvzPath: File
        /// Where to write the restored raw ISO.
        let isoPath: File
        let overwrite: Bool

        init(rvzPath: File, isoPath: File, overwrite: Bool = true) {
            self.rvzPath = rvzPath
            self.isoPath = isoPath
            self.overwrite = overwrite
        }
    }
}
