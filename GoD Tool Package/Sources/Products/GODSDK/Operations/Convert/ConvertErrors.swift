import GoDFoundation

enum ConvertErrors: Error, CustomStringConvertible {
    case inputFileNotFound(file: File, ErrorTrace)
    case writeFailed(file: File, ErrorTrace)
    case emptyStruct(structName: String, ErrorTrace)
    case windowOutOfRange(structName: String, offset: Int, length: Int, dataSize: Int, ErrorTrace)
    case structDoesNotTile(structName: String, structSize: Int, offset: Int, dataSize: Int, ErrorTrace)
    case invalidCount(structName: String, count: Int, ErrorTrace)
    case insertOutOfRange(file: File, offset: Int, length: Int, fileSize: Int, ErrorTrace)
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
        case let .windowOutOfRange(name, offset, length, dataSize, trace):
            return "Convert: '\(name)' needs \(length) bytes at offset \(offset), but the input is \(dataSize) bytes — the window must sit wholly inside the input\n\(trace)"
        case let .structDoesNotTile(name, structSize, offset, dataSize, trace):
            return "Convert: struct '\(name)' (\(structSize) bytes) does not tile the \(dataSize) bytes from offset \(offset) exactly (\(dataSize % max(structSize, 1)) bytes left over) — give a count to stop before the leftover\n\(trace)"
        case let .invalidCount(name, count, trace):
            return "Convert: count \(count) for '\(name)' is negative\n\(trace)"
        case let .insertOutOfRange(file, offset, length, fileSize, trace):
            return "Convert: cannot insert \(length) bytes at offset \(offset) into \(file.path) (\(fileSize) bytes) — the patch must fit inside the existing file; omit insertOffset to replace the file instead\n\(trace)"
        case let .notAStructTable(file, trace):
            return "Convert: expected a JSON array of struct objects at \(file.path)\n\(trace)"
        case let .noEngines(name, trace):
            return "Convert: no engine folders listed; struct '\(name)' has nothing to resolve against — set `engines` to the engine folder(s) that declare it and everything it references\n\(trace)"
        }
    }
}
