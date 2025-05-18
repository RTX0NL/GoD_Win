import GoDFoundation

public enum ProjectSetupErrors: GoDError {
    case isoNotFound(File, ErrorTrace)
    case invalidGameID(ErrorTrace)
    
    public var description: String {
        switch self {
        case let .isoNotFound(file, errorTrace):
            return "Error: Couldn't load iso file: \(file)\n\(errorTrace)"
        case let .invalidGameID(errorTrace):
            return "Error: Couldn't read Game ID\n\(errorTrace)"
        }
    }
}
