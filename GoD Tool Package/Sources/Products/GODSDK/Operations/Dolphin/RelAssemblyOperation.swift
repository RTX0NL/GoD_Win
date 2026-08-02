import GoDFoundation
import Dolphin

extension RelAssembly {
    /// Reconstruct a `.rel` binary from disassembly artifacts. First
    /// iteration reads only the canonical `<relName>.rel.json` emitted by
    /// `RelDisassembly`; that file is lossless, so byte-identical output
    /// is achievable without parsing the human-editable `.s` / chunk
    /// files. Those will feed in once `.s` parsing lands.
    static func assemble(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        guard RelOperationsGate.enabled else {
            throw RelOperationsGate.DisabledError(operation: "relAssembly", trace: .init())
        }

        logger?.log(.taskStatus(taskName: "Assemble REL", status: .started))

        let jsonFile = config.inputFolder.file("\(config.relName).rel.json")
        guard let jsonData = fileSystem.readFile(at: jsonFile)?.allData else {
            throw RelAssemblyErrors.manifestNotFound(file: jsonFile, .init())
        }

        let rel: RELFile
        do {
            rel = try RELFile(outputs: [
                FileData(file: File("\(config.relName).rel.json"), data: jsonData)
            ])
        } catch {
            throw RelAssemblyErrors.invalidManifest(file: jsonFile, underlying: error, .init())
        }

        let bytes = try rel.binaryData
        try fileSystem.writeFile(bytes, at: config.outputPath, overwrite: config.overwrite)

        logger?.log(.info("Wrote \(bytes.length) bytes to \(config.outputPath.path)"))
        logger?.log(.taskStatus(taskName: "Assemble REL", status: .completed(true)))
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
