import GoDFoundation

enum XDSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)
    case noValidSlot(file: File, ErrorTrace)
    case missingArtifact(file: File, ErrorTrace)
    case missingStructBinding(index: Int, name: String, ErrorTrace)
    case missingHeaderRegionFile(file: File, ErrorTrace)
    case missingHeaderStruct(name: String, ErrorTrace)
    case sectionSizeMismatch(index: Int, name: String, expected: Int, actual: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "XD save: missing slot bin at \(file)\n\(trace)"
        case let .noValidSlot(file, trace):
            return "XD save: neither slot holds a valid save — every slot's body checksum failed after decrypt, which is what a blank, never-saved memory-card file looks like. Check that \(file) came from a card the game has actually saved to.\n\(trace)"
        case let .missingArtifact(file, trace):
            return "XD save: missing section artifact at \(file)\n\(trace)"
        case let .missingStructBinding(index, name, trace):
            return "XD save: section \(index) '\(name)' has a JSON artifact but no resolvable struct binding to decode it\n\(trace)"
        case let .missingHeaderRegionFile(file, trace):
            return "XD save: slot header file not found at \(file)\n\(trace)"
        case let .missingHeaderStruct(name, trace):
            return """
                XD save: the slot header was dumped as JSON but the engine has no \
                '\(name)' struct to decode it with. Re-dump with an engine that \
                declares it, or restore the engine folder this project was dumped against.
                \(trace)
                """
        case let .sectionSizeMismatch(index, name, expected, actual, trace):
            return "XD save: section \(index) '\(name)' rebuilt to \(actual) bytes but the dump recorded \(expected) — extend the struct's padding (or fix the edit) so it tiles the section exactly\n\(trace)"
        }
    }
}
