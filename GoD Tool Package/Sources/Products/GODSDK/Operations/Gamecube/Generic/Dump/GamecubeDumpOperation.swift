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
                guard let data = fileSystem.readFile(at: isoPath) else {
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
