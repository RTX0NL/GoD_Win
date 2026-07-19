import GoDFoundation

enum XDSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case missingStructBinding(index: Int, name: String, ErrorTrace)
    case invalidHeaderRegion(ErrorTrace)
    case sectionSizeMismatch(index: Int, name: String, expected: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "XD save: missing slot bin at \(file)\n\(trace)"
        case let .missingArtifact(file, trace):
            return "XD save: missing section artifact at \(file)\n\(trace)"
        case let .missingStructBinding(index, name, trace):
            return "XD save: section \(index) '\(name)' has a JSON artifact but no resolvable struct binding to decode it\n\(trace)"
        case let .invalidHeaderRegion(trace):
            return "XD save: slot-metadata headerRegion is not valid base64\n\(trace)"
        case let .sectionSizeMismatch(index, name, expected, actual, trace):
            return "XD save: section \(index) '\(name)' rebuilt to \(actual) bytes but the dump recorded \(expected) — extend the struct's padding (or fix the edit) so it tiles the section exactly\n\(trace)"
        }
    }
}
