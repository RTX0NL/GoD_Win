import GoDFoundation

enum PatchErrors: Error, CustomStringConvertible {
    case inputFileNotFound(file: File, ErrorTrace)
    case patchFileNotFound(file: File, ErrorTrace)
    case unrecognizedPatchFormat(file: File, prefix: [UInt8], ErrorTrace)
    case formatMismatch(file: File, expected: PatchFormat, found: PatchFormat?, ErrorTrace)
    case outputIsInput(file: File, ErrorTrace)
    case outputNotReadable(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .inputFileNotFound(file, trace):
            return "Patch: file to patch not found at \(file.path)\n\(trace)"
        case let .patchFileNotFound(file, trace):
            return "Patch: patch file not found at \(file.path)\n\(trace)"
        case let .unrecognizedPatchFormat(file, prefix, trace):
            let hex = prefix.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Patch: \(file.path) starts with bytes [\(hex)], which match no patch format GODDESS reads "
            + "(\(PatchFormat.allCases.map(\.name).joined(separator: ", ")))\n\(trace)"
        case let .formatMismatch(file, expected, found, trace):
            let seen = found?.name ?? "no known format"
            return "Patch: \(file.path) was declared `\(expected.rawValue)` but its magic says \(seen) — "
            + "fix `format`, or omit it to go by the magic\n\(trace)"
        case let .outputIsInput(file, trace):
            return "Patch: outputFile and inputFile are both \(file.path) — a patch is applied to one file and "
            + "written to another, and the result is verified by reading it back\n\(trace)"
        case let .outputNotReadable(file, trace):
            return "Patch: wrote \(file.path) but could not read it back to verify it\n\(trace)"
        }
    }
}
