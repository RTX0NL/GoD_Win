import GoDFoundation

/// Type annotation for a script function parameter or return value.
/// Either a primitive type or a reference to a named enum defined in the engine.
public enum ScriptParamType: Codable, Equatable {
    /// Primitive types (no enum lookup needed)
    case integer
    case float
    case bool
    /// String value (stored as a load-time-relocated pointer to a
    /// NUL-terminated string in the script file)
    case string

    /// Reference to an engine enum by name.
    /// The formatter resolves raw values against the enum's cases.
    /// Output: `EnumName.caseName` if a case matches, raw value otherwise.
    case enumRef(String)

    // Custom Codable: encodes primitives as plain strings, enum refs as "enum:Name"
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        switch str {
        case "integer": self = .integer
        case "float": self = .float
        case "bool": self = .bool
        case "string": self = .string
        default:
            // "enum:FlagName" or just "FlagName" for backwards compat
            if str.hasPrefix("enum:") {
                self = .enumRef(String(str.dropFirst(5)))
            } else {
                self = .enumRef(str)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer: try container.encode("integer")
        case .float: try container.encode("float")
        case .bool: try container.encode("bool")
        case .string: try container.encode("string")
        case .enumRef(let name): try container.encode(name)
        }
    }
}
