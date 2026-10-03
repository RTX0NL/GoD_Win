import GoDFoundation
import GoDEngine
import Dolphin
import Wii

extension WiiOps {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .encryptISO(fstPath, isoPath, overwrite, wiiEnginePath, dolphinEnginePath):
                guard let commonKeyFile = settings.wiiCommonKeyFile else {
                    throw WiiErrors.missingCommonKey(.init())
                }
                let commonKey = try WiiOps.loadCommonKey(from: commonKeyFile, fileSystem: fileSystem)
                let wiiEngine = try WiiEngine(from: wiiEnginePath, in: fileSystem)
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)

                logger?.log(.warning("Encrypting Wii ISO from: \(fstPath.folderName)"))
                let iso = WiiISO(
                    fst: fileSystem,
                    rootFolder: fstPath,
                    commonKey: commonKey,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine
                )
                // A lazy composition, not a buffer: `writeFile` pulls it in
                // 8 MB windows, hashing and encrypting one 2 MiB group at a
                // time, so a 4.7 GB disc never becomes resident.
                let isoData = try iso.encryptedData(commonKey: commonKey, logger: logger)

                if overwrite || fileSystem.inspectFile(at: isoPath) == nil {
                    try fileSystem.writeFile(isoData, at: isoPath, overwrite: overwrite)
                }
                logger?.log(.warning("Wii ISO encryption complete"))

            case let .fillISO(isoPath, size):
                // See the GameCube equivalent: constant-memory resize where
                // the tree supports it. This matters most here — a Wii disc
                // pads to 4.7 GB.
                guard let current = fileSystem.fileSize(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                if current < size {
                    logger?.log(.info("Padding ISO from \(current) to \(size) bytes"))
                    try fileSystem.padFile(at: isoPath, toAtLeast: size)
                }
            }
        }
    }
}
