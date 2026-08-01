import GoDFoundation
import GoDEngine
import Dolphin
import GameCube

extension Gamecube {
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .unpackISO(
                isoPath,
                fstFolder,
                overwrite,
                dolphinEnginePath,
                gamecubeEnginePath
            ):
                // `reader` rather than `readFile`: on the on-disk tree this
                // streams the image, so a 1.4 GB ISO no longer has to be
                // resident to extract a few megabytes of it.
                guard let data = fileSystem.reader(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)
                let gamecubeEngine = try GamecubeEngine(from: gamecubeEnginePath, in: fileSystem)
                let iso = try GamecubeISO(data: data, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
                
                try fileSystem.importFST(
                    iso,
                    from: "/",
                    to: fstFolder,
                    overwrite: overwrite,
                    logger: logger
                )
            }
        }
    }
}
