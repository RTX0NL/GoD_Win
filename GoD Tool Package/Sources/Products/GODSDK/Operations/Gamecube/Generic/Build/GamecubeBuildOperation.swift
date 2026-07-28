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
                // Use the injected tree, not `FileSystem.shared`: reaching for
                // the singleton made this the one build step that couldn't run
                // against an `InMemoryFST`, so it was untestable and ignored
                // the caller's choice of file system. Mirrors `WiiOps.fillISO`.
                guard let iso = fileSystem.readFile(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                let remaining = size - iso.length
                if remaining > 0 {
                    logger?.log(.info("Padding \(isoPath.fileName) to \(size) bytes"))
                    iso.append(GoDData(length: remaining, byteOrder: .big))
                    try fileSystem.writeFile(iso, at: isoPath, overwrite: true)
                }
            }
        }
    }
}
