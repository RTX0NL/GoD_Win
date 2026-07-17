import GoDFoundation

public enum ProjectSetupErrors: GoDError {
    case isoNotFound(File, ErrorTrace)
    case gciNotFound(File, ErrorTrace)
    case invalidGameID(ErrorTrace)
    case unsupportedInputFormat(format: String, file: File, ErrorTrace)
    case unrecognisedGCIGamecode(String, ErrorTrace)

    public var description: String {
        switch self {
        case let .isoNotFound(file, errorTrace):
            return "Error: Couldn't load iso file: \(file)\n\(errorTrace)"
        case let .gciNotFound(file, errorTrace):
            return "Error: Couldn't load gci file: \(file)\n\(errorTrace)"
        case let .invalidGameID(errorTrace):
            return "Error: Couldn't read Game ID\n\(errorTrace)"
        case let .unsupportedInputFormat(format, file, errorTrace):
            return "Error: Detected \(format) at \(file.path), but the decoder isn't wired up yet. Convert to raw .iso first.\n\(errorTrace)"
        case let .unrecognisedGCIGamecode(gamecode, errorTrace):
            return "Error: GCI gamecode '\(gamecode)' is not a known XD/Colo save\n\(errorTrace)"
        }
    }
}
