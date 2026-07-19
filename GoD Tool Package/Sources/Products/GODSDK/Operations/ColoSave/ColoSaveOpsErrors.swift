import GoDFoundation

enum ColoSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case missingStructBinding(index: Int, name: String, ErrorTrace)
    case invalidHeaderRegion(ErrorTrace)
    case noLatestSlot(ErrorTrace)
    case sectionSizeMismatch(index: Int, name: String, expected: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "Colo save: missing slot bin at \(file)\n\(trace)"
        case let .missingArtifact(file, trace):
            return "Colo save: missing section artifact at \(file)\n\(trace)"
        case let .missingStructBinding(index, name, trace):
            return "Colo save: section \(index) '\(name)' has a JSON artifact but no resolvable struct binding to decode it\n\(trace)"
        case let .invalidHeaderRegion(trace):
            return "Colo save: slot-metadata headerRegion is not valid base64\n\(trace)"
        case let .noLatestSlot(trace):
            return "Colo save: save-metadata has no latestSlotIndex — cannot pick the slot to rebuild\n\(trace)"
        case let .sectionSizeMismatch(index, name, expected, actual, trace):
            return "Colo save: section \(index) '\(name)' rebuilt to \(actual) bytes but the dump recorded \(expected) — extend the struct's padding (or fix the edit) so it tiles the section exactly\n\(trace)"
        }
    }
}
