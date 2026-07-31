import Foundation
import GoDFoundation
import Dolphin
import Disassembler
import Structs

extension DolDisassembly {
    static func disassemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        let dolphinEngine = try DolphinEngine(from: config.dolphinEngine, in: fileSystem)

        let disassembled = try DolDisassembler(dolphinEngine: dolphinEngine, registry: registry)
            .disassemble(
                dolPath: config.dolPath,
                symbolMapPath: config.symbolMapPath,
                typeMapPath: config.typeMapPath,
                engineFolders: config.engines ?? [],
                from: fileSystem,
                logger: logger
            )

        // The disassembly lands in a subfolder named after the DOL, so several
        // executables can share one output folder.
        let targetFolder = config.outputFolder
            .folder(DolDisassembler.outputFolderName(for: config.dolPath))
        try fileSystem.importFST(disassembled, from: Folder("/"), to: targetFolder, overwrite: true)

        logger?.log(.taskStatus(taskName: "Disassemble DOL", status: .completed(true)))
    }
}
