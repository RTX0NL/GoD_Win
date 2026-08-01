import GoDFoundation
import GoDEngine
import Dolphin
import GameCube

extension Gamecube {
    /// Takes a `StreamedFileSystem` rather than any tree: this operation opens
    /// a disc image, and reading one through `readFile` would cost its full
    /// size in memory before the first byte is parsed. Requiring the streamed
    /// tree in the signature is what makes the caller's choice of tree matter
    /// — there is no capability to probe for at runtime.
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: StreamedFileSystem,
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
                // Opened, not read: `GamecubeISO` only ever wants windows of
                // the image, so a 1.4 GB ISO never has to be resident.
                guard let data = fileSystem.streamFile(at: isoPath) else {
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
