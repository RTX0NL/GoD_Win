import Foundation

public enum Toggle: String, Codable {
    case yes = "YES"
    case no = "NO"
    
    public init?(rawValue: String) {
        switch rawValue {
        case "yes", "YES", "Yes", "true", "TRUE", "True":
            self = .yes
        default:
            self = .no
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Toggle(rawValue: rawValue) ?? .no
    }
}

public extension Array {
    func filter(_ keypath: KeyPath<Element, Toggle>) -> Self {
        filter {
            $0[keyPath: keypath] == .yes
        }
    }
}
