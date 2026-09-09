import GoDFoundation
import Dolphin

extension RelAssembly {
    /// Thin wrapper around `RelAssembler`: rebuilds `<relName>.rel` from the
    /// manifest and the chunk files it points at, so edits to the `.s`, `.csv`
    /// and embedded-file artifacts land in the binary.
    static func assemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil,
        registry: FileFormatRegistry = .all()
    ) throws {
        guard RelOperationsGate.enabled else {
            throw RelOperationsGate.DisabledError(operation: "relAssembly", trace: .init())
        }

        let rel: RELFile
        do {
            rel = try RelAssembler(registry: registry, engineFolders: config.engines ?? []).assemble(
                relName: config.relName,
                in: config.inputFolder,
                fileSystem: fileSystem,
                logger: logger
            )
        } catch let error as RelAssemblerErrors {
            switch error {
            case let .manifestNotFound(file, trace):
                throw RelAssemblyErrors.manifestNotFound(file: file, trace)
            case let .invalidManifest(file, underlying, trace):
                throw RelAssemblyErrors.invalidManifest(file: file, underlying: underlying, trace)
            default:
                throw error
            }
        }

        let bytes = try rel.binaryData
        try fileSystem.writeFile(bytes, at: config.outputPath, overwrite: config.overwrite)

        logger?.log(.info("Wrote \(bytes.length) bytes to \(config.outputPath.path)"))
    }
}

enum RelAssemblyErrors: Error, CustomStringConvertible {
    case manifestNotFound(file: File, ErrorTrace)
    case invalidManifest(file: File, underlying: Error, ErrorTrace)

    var description: String {
        switch self {
        case let .manifestNotFound(file, trace):
            return "REL manifest not found: \(file)\n\(trace)"
        case let .invalidManifest(file, underlying, trace):
            return "Invalid REL manifest at \(file): \(underlying)\n\(trace)"
        }
    }
}
