import GoDFoundation
import Dolphin
import Wii

extension RVZDump {
    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump RVZ", status: .started))
        // Kept as a readable rather than a buffer: a group is read from its
        // own offset, so a 2.6 GB image never has to be resident.
        guard let source = fileSystem.readFile(at: config.rvzPath) else {
            throw RVZErrors.inputNotFound(file: config.rvzPath, .init())
        }
        let image = try RVZImage(binary: source)
        // A view rather than a buffer: `writeFile` pulls a readable in 8 MB
        // windows, so a 4.7 GB disc is restored through a couple of cached
        // blocks instead of being assembled in memory first.
        let iso = try image.discImageView(partitionRestorer: WiiRVZPartitionRestorer())
        logger?.log(.info("Restoring \(image.disc.discType) image: \(iso.length) bytes, "
            + "\(image.groups.count) groups of \(image.chunkSize) bytes, "
            + "\(image.disc.compression) compression"))
        try fileSystem.writeFile(iso, at: config.isoPath, overwrite: config.overwrite)
        logger?.log(.info("Restored \(iso.length) bytes to \(config.isoPath.path)"))
        logger?.log(.taskStatus(taskName: "Dump RVZ", status: .completed(true)))
    }
}

enum RVZErrors: Error, CustomStringConvertible {
    case inputNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .inputNotFound(file, trace):
            return "WIA/RVZ input not found: \(file)\n\(trace)"
        }
    }
}
