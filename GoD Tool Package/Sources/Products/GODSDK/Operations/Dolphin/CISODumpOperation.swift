import GoDFoundation
import Dolphin

extension CISODump {
    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump CISO", status: .started))
        guard let cisoData = fileSystem.readFile(at: config.cisoPath) else {
            throw CISOErrors.inputNotFound(file: config.cisoPath, .init())
        }
        let iso = try CISOConverter.dump(ciso: cisoData, targetDiscSize: config.targetDiscSize)
        fileSystem.writeFile(iso, at: config.isoPath, overwrite: config.overwrite)
        logger?.log(.info("Restored \(iso.length) bytes to \(config.isoPath.path)"))
        logger?.log(.taskStatus(taskName: "Dump CISO", status: .completed(true)))
    }
}

extension CISOBuild {
    static func build(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        logger?.log(.taskStatus(taskName: "Build CISO", status: .started))
        guard let isoData = fileSystem.readFile(at: config.isoPath) else {
            throw CISOErrors.inputNotFound(file: config.isoPath, .init())
        }
        let ciso = CISOConverter.build(iso: isoData, blockSize: config.blockSize)
        fileSystem.writeFile(ciso, at: config.cisoPath, overwrite: config.overwrite)
        logger?.log(.info("Shrunk \(isoData.length) → \(ciso.length) bytes (\(config.cisoPath.path))"))
        logger?.log(.taskStatus(taskName: "Build CISO", status: .completed(true)))
    }
}

enum CISOErrors: Error, CustomStringConvertible {
    case inputNotFound(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .inputNotFound(file, trace):
            return "CISO input not found: \(file)\n\(trace)"
        }
    }
}
