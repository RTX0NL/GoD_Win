import GoDFoundation

public enum ProjectSetupErrors: GoDError {
    case isoNotFound(File, ErrorTrace)
    case gciNotFound(File, ErrorTrace)
    case fsysNotFound(File, ErrorTrace)
    case fsysParseFailed(File, underlying: String, ErrorTrace)
    case invalidGameID(ErrorTrace)
    case unsupportedInputFormat(format: String, reason: String, file: File, ErrorTrace)
    case unrecognizedGCIGamecode(String, ErrorTrace)

    public var description: String {
        switch self {
        case let .isoNotFound(file, errorTrace):
            return "Error: Couldn't load iso file: \(file)\n\(errorTrace)"
        case let .gciNotFound(file, errorTrace):
            return "Error: Couldn't load gci file: \(file)\n\(errorTrace)"
        case let .fsysNotFound(file, errorTrace):
            return "Error: Couldn't load fsys file: \(file)\n\(errorTrace)"
        case let .fsysParseFailed(file, underlying, errorTrace):
            return "Error: Couldn't parse \(file) as an FSYS archive with any known engine (XD, Colosseum, PBR). Last error: \(underlying)\n\(errorTrace)"
        case let .invalidGameID(errorTrace):
            return "Error: Couldn't read Game ID\n\(errorTrace)"
        case let .unsupportedInputFormat(format, reason, file, errorTrace):
            return "Error: \(file.path) is a \(format) image, which setup can't open: \(reason)\n\(errorTrace)"
        case let .unrecognizedGCIGamecode(gamecode, errorTrace):
            return "Error: GCI gamecode '\(gamecode)' is not a known XD/Colo save\n\(errorTrace)"
        }
    }
}
