import GoDFoundation
import Dolphin

extension NKitDump {
    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump NKit", status: .started))
        // Read through the readable rather than `allData`: the codec
        // only ever walks forward through the image, so a streamed
        // source stays streamed and a 1 GB input costs a window.
        guard let nkitData = fileSystem.readFile(at: config.nkitPath) else {
            throw NKitErrors.inputNotFound(file: config.nkitPath, .init())
        }
        let iso = try NKitGCConverter.dump(nkit: nkitData)
        try fileSystem.writeFile(iso, at: config.isoPath, overwrite: config.overwrite)
        logger?.log(.info("Restored \(iso.length) bytes to \(config.isoPath.path)"))
        logger?.log(.taskStatus(taskName: "Dump NKit", status: .completed(true)))
    }
}

extension NKitBuild {
    static func build(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Build NKit", status: .started))
        guard let isoData = fileSystem.readFile(at: config.isoPath) else {
            throw NKitErrors.inputNotFound(file: config.isoPath, .init())
        }
        let nkit = try NKitGCConverter.build(iso: isoData, junkOverrideID: config.junkOverrideID)
        try fileSystem.writeFile(nkit, at: config.nkitPath, overwrite: config.overwrite)
        let saved = isoData.length - nkit.length
        let percent = isoData.length == 0 ? 0 : (saved * 100) / isoData.length
        logger?.log(.info(
            "Shrunk \(isoData.length) → \(nkit.length) bytes (\(percent)% smaller) — \(config.nkitPath.path)"
        ))
        logger?.log(.taskStatus(taskName: "Build NKit", status: .completed(true)))
    }
}

enum NKitErrors: Error, CustomStringConvertible {
    case inputNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .inputNotFound(file, trace):
            return "NKit input not found: \(file)\n\(trace)"
        }
    }
}
