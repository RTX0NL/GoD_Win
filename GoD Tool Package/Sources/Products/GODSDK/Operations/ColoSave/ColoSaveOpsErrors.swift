import GoDFoundation

enum ColoSaveOpsErrors: Error, CustomStringConvertible {
    case missingSlot(file: File, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSlot(file, trace):
            return "Colo save: missing slot bin at \(file)\n\(trace)"
        }
    }
}
