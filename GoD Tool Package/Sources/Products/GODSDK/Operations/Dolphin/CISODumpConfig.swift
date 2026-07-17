import GoDFoundation
import Dolphin

enum CISODump {
    struct Config: Codable {
        /// Path to the `.ciso` input.
        let cisoPath: File
        /// Where to write the restored raw ISO.
        let isoPath: File
        /// Explicit target disc size. When nil, defaults to the
        /// minimum size that covers every present block in the map
        /// (i.e. `blockMap.count * blockSize`). For an exact
        /// byte-for-byte restore of a known disc, pass the real size
        /// (1459978240 for GC, 4699979776 for Wii single-layer,
        /// 8511160320 for dual-layer).
        let targetDiscSize: UInt64?
        let overwrite: Bool

        init(cisoPath: File, isoPath: File, targetDiscSize: UInt64? = nil, overwrite: Bool = true) {
            self.cisoPath = cisoPath
            self.isoPath = isoPath
            self.targetDiscSize = targetDiscSize
            self.overwrite = overwrite
        }
    }
}

enum CISOBuild {
    struct Config: Codable {
        /// Path to the raw ISO input.
        let isoPath: File
        /// Where to write the `.ciso` output.
        let cisoPath: File
        /// Block size in bytes. Default 2 MiB (the only value any
        /// GC/Wii CISO in the wild uses).
        let blockSize: UInt32
        let overwrite: Bool

        init(
            isoPath: File,
            cisoPath: File,
            blockSize: UInt32 = CISOFile.defaultBlockSize,
            overwrite: Bool = true
        ) {
            self.isoPath = isoPath
            self.cisoPath = cisoPath
            self.blockSize = blockSize
            self.overwrite = overwrite
        }
    }
}
