import GoDFoundation

enum CompressionErrors: Error, CustomStringConvertible {
    case inputFileNotFound(file: File, ErrorTrace)
    case unrecognizedFormat(file: File, prefix: [UInt8], ErrorTrace)
    case formatMismatch(file: File, expected: CompressionOps.Format, found: CompressionFormat?, ErrorTrace)
    case rangeOutOfBounds(file: File, offset: Int, length: Int?, fileSize: Int, ErrorTrace)
    case optionNotApplicable(option: String, format: CompressionOps.Format, direction: CompressionOps.Direction, readBy: String, ErrorTrace)
    case optionOutOfRange(option: String, value: Int, format: CompressionOps.Format, rule: String, ErrorTrace)
    case invalidOutputExtension(String, ErrorTrace)

    var description: String {
        switch self {
        case let .inputFileNotFound(file, trace):
            return "Compression: input file not found at \(file.path)\n\(trace)"
        case let .unrecognizedFormat(file, prefix, trace):
            let hex = prefix.map { String(format: "%02X", $0) }.joined(separator: " ")
            let known = CompressionFormat.allCases.map(\.name).joined(separator: ", ")
            return "Compression: no format named, and \(file.path) starts with bytes [\(hex)] which match no known magic (\(known)) — set `format` explicitly; a raw LZSS stream (`lzss-raw`) has no magic and can only be named\n\(trace)"
        case let .formatMismatch(file, expected, found, trace):
            let seen = found.map { "say \($0.name)" } ?? "match no known magic"
            return "Compression: \(file.path) was declared `\(expected.rawValue)` but its first bytes \(seen) — fix `format`, or omit it to go by the magic\n\(trace)"
        case let .rangeOutOfBounds(file, offset, length, fileSize, trace):
            let window = length.map { "offset \(offset), length \($0)" } ?? "offset \(offset) to the end"
            return "Compression: range (\(window)) does not sit inside \(file.path) (\(fileSize) bytes) — offset and length must be non-negative and the window must end inside the file\n\(trace)"
        case let .optionNotApplicable(option, format, direction, readBy, trace):
            return "Compression: option `\(option)` is not read when \(direction.rawValue)ing `\(format.rawValue)` — it applies to \(readBy); remove it rather than expect it to take effect\n\(trace)"
        case let .optionOutOfRange(option, value, format, rule, trace):
            return "Compression: option `\(option)` = \(value) is out of range for `\(format.rawValue)`: \(rule)\n\(trace)"
        case let .invalidOutputExtension(ext, trace):
            return "Compression: outputExtension \"\(ext)\" is empty once the leading dot is stripped — give a real extension, or omit it to use the format's default\n\(trace)"
        }
    }
}
