import GoDFoundation

enum ColoSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)
    case noValidSlot(file: File, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case missingStructBinding(index: Int, name: String, ErrorTrace)
    case missingHeaderRegionFile(file: File, ErrorTrace)
    case missingHeaderStruct(name: String, ErrorTrace)
    case noLatestSlot(ErrorTrace)
    case sectionSizeMismatch(index: Int, name: String, expected: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "Colo save: missing slot bin at \(file)\n\(trace)"
        case let .noValidSlot(file, trace):
            return "Colo save: no slot holds a valid save — every slot failed both its header and body checksum after decrypt, which is what a blank, never-saved memory-card file looks like. Check that \(file) came from a card the game has actually saved to.\n\(trace)"
        case let .missingArtifact(file, trace):
            return "Colo save: missing section artifact at \(file)\n\(trace)"
        case let .missingStructBinding(index, name, trace):
            return "Colo save: section \(index) '\(name)' has a JSON artifact but no resolvable struct binding to decode it\n\(trace)"
        case let .missingHeaderRegionFile(file, trace):
            return "Colo save: slot header file not found at \(file)\n\(trace)"
        case let .missingHeaderStruct(name, trace):
            return """
                Colo save: the slot header was dumped as JSON but the engine has no \
                '\(name)' struct to decode it with. Re-dump with an engine that \
                declares it, or restore the engine folder this project was dumped against.
                \(trace)
                """
        case let .noLatestSlot(trace):
            return "Colo save: save-metadata has no latestSlotIndex — cannot pick the slot to rebuild\n\(trace)"
        case let .sectionSizeMismatch(index, name, expected, actual, trace):
            return "Colo save: section \(index) '\(name)' rebuilt to \(actual) bytes but the dump recorded \(expected) — extend the struct's padding (or fix the edit) so it tiles the section exactly\n\(trace)"
        }
    }
}
