import GoDFoundation
import Dolphin
import GameCube

extension Gamecube {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree
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
                
                let iso = GamecubeISO(
                    fst: fileSystem,
                    rootFolder: fstPath,
                    dolphinEngine: dolphinEngine,
                    gamecubeEngine: gamecubeEngine
                )
                let data = try iso.data
                guard fileSystem.writeFile(data, at: isoPath, overwrite: overwrite) else {
                    throw FSTErrors.failedToWriteFile(isoPath, .init())
                }
            case let .fillISO(
                isoPath,
                size
            ):
                guard let iso = FileSystem.shared.readFile(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }
                let remaining = size - iso.length
                if remaining > 0 {
                    iso.append(GoDData(length: remaining))
                    FileSystem.shared.writeFile(iso, at: isoPath, overwrite: true)
                }
                
            }
        }
    }
}
