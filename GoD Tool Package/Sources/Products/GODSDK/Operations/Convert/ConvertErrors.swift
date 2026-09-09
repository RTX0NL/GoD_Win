import GoDFoundation

enum ConvertErrors: Error, CustomStringConvertible {
    case inputFileNotFound(file: File, ErrorTrace)
    case writeFailed(file: File, ErrorTrace)
    case emptyStruct(structName: String, ErrorTrace)
    case structSizeMismatch(structName: String, structSize: Int, dataSize: Int, ErrorTrace)
    case structDoesNotTile(structName: String, structSize: Int, dataSize: Int, ErrorTrace)
    case notAStructTable(file: File, ErrorTrace)
    case noEngines(structName: String, ErrorTrace)

    var description: String {
        switch self {
        case let .inputFileNotFound(file, trace):
            return "Convert: input file not found at \(file.path)\n\(trace)"
        case let .writeFailed(file, trace):
            return "Convert: failed to write output at \(file.path)\n\(trace)"
        case let .emptyStruct(name, trace):
            return "Convert: struct '\(name)' has zero length; cannot map binary data onto it\n\(trace)"
        case let .structSizeMismatch(name, structSize, dataSize, trace):
            return "Convert: struct '\(name)' is \(structSize) bytes but the input is \(dataSize) bytes — a single struct must match the input size exactly\n\(trace)"
        case let .structDoesNotTile(name, structSize, dataSize, trace):
            return "Convert: struct '\(name)' (\(structSize) bytes) does not tile the \(dataSize)-byte input exactly (\(dataSize % max(structSize, 1)) bytes left over)\n\(trace)"
        case let .notAStructTable(file, trace):
            return "Convert: expected a JSON array of struct objects at \(file.path)\n\(trace)"
        case let .noEngines(name, trace):
            return "Convert: no engine folders listed; struct '\(name)' has nothing to resolve against — set `engines` to the engine folder(s) that declare it and everything it references\n\(trace)"
        }
    }
}
