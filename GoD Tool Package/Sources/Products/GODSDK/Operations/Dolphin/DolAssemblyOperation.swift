import Foundation
import GoDFoundation
import Dolphin
import Disassembler
import Structs

enum DolAssembly {
    static func assemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)

        try DolAssembler(dolphinEngine: dolphinEngine, registry: registry)
            .assemble(
                codeFolder: config.codeFolder,
                outputDolPath: config.outputDolPath,
                symbolMapPath: config.symbolMapPath,
                typeMapPath: config.typeMapPath,
                bssEntryListPath: config.bssEntryListPath,
                engineFolders: config.engines ?? [],
                sdaBase: config.sdaBase,
                sda2Base: config.sda2Base,
                in: fileSystem,
                logger: logger
            )
    }
}
