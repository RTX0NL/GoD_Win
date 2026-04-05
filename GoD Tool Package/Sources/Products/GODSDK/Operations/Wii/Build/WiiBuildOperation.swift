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
                let isoData = try iso.encryptedData(commonKey: commonKey, logger: logger)

                if overwrite || fileSystem.inspectFile(at: isoPath) == nil {
                    fileSystem.writeFile(isoData, at: isoPath, overwrite: overwrite)
                }
                logger?.log(.warning("Wii ISO encryption complete"))

            case let .fillISO(isoPath, size):
                guard let isoData = fileSystem.readFile(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                if isoData.length < size {
                    logger?.log(.info("Padding ISO to \(size) bytes"))
                    isoData.pad(by: size - isoData.length)
                    fileSystem.writeFile(isoData, at: isoPath, overwrite: true)
                }
            }
        }
    }
}
