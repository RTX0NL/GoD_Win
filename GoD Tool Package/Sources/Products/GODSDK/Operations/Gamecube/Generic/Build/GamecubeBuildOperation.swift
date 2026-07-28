import GoDFoundation
import Dolphin
import GameCube

extension Gamecube {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildISO(
                fstPath,
                isoPath,
                overwrite,
                dolphinEnginePath,
                gamecubeEnginePath
            ):
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)
                let gamecubeEngine = try GamecubeEngine(from: gamecubeEnginePath, in: fileSystem)

                logger?.log(.taskStatus(taskName: "Build Gamecube ISO", status: .started))
                let iso = GamecubeISO(
                    fst: fileSystem,
                    rootFolder: fstPath,
                    dolphinEngine: dolphinEngine,
                    gamecubeEngine: gamecubeEngine
                )
                let data = try iso.data
                try fileSystem.writeFile(data, at: isoPath, overwrite: overwrite)
                logger?.log(.info("Wrote \(isoPath.fileName) (\(data.length) bytes)"))
                logger?.log(.taskStatus(taskName: "Build Gamecube ISO", status: .completed(true)))

            case let .fillISO(
                isoPath,
                size
            ):
                // `padFile` resizes in place on a tree that supports random
                // access, and falls back to read-append-write on one that
                // doesn't. Padding a disc image to capacity used to read the
                // whole thing into memory and write it all back — gigabytes of
                // traffic to append zeros.
                guard let current = fileSystem.fileSize(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                if current < size {
                    logger?.log(.info("Padding \(isoPath.fileName) from \(current) to \(size) bytes"))
                    try fileSystem.padFile(at: isoPath, toAtLeast: size)
                }
            }
        }
    }
}
