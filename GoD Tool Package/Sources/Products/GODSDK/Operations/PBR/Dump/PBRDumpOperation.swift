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
            case let .dumpPBR(fstFolder, outputFolder, _, _, _):
                // Not implemented, and project setup wires this op in
                // *enabled* for a PBR disc — so report it at warning level
                // and mark the task failed. Logging it as info and returning
                // success made a no-op look like a completed dump, with an
                // empty output folder as the only clue.
                logger?.log(.taskStatus(taskName: "Dump PBR", status: .started))
                logger?.log(.warning(
                    "PBR dump is not implemented yet — nothing was written. "
                    + "\(fstFolder.path) was left untouched and no files were "
                    + "produced under \(outputFolder.path). A PBR disc can still "
                    + "be decrypted with the wiiDump operation."
                ))
                logger?.log(.taskStatus(taskName: "Dump PBR", status: .completed(false)))
            }
        }
    }
}
