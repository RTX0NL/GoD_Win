import GoDFoundation

enum GCIOpsErrors: Error, CustomStringConvertible {
    case inputNotFound(file: File, ErrorTrace)
    case missingRegion(folder: Folder, ErrorTrace)

    var description: String {
        switch self {
        case let .inputNotFound(file, trace):
            return "GCI input not found: \(file)\n\(trace)"
        case let .missingRegion(folder, trace):
            return "GCI build: missing region file under \(folder)\n\(trace)"
        }
    }
}
