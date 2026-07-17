import GoDFoundation

enum XDSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "XD save: missing slot bin at \(file)\n\(trace)"
        }
    }
}
