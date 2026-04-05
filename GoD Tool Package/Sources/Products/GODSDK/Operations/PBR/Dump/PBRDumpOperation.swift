import GoDFoundation
import GoDEngine

extension PBROps {
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case .dumpPBR:
                logger?.log(.info("PBR dump not yet implemented"))
            }
        }
    }
}
