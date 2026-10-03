import GoDFoundation

public enum ColoValueType: Equatable, Codable {
    case void
    case integer
    case float
    case unknown(id: Int)

    public var id: Int {
        switch self {
        case .void: return 0
        case .integer: return 2
        case .float: return 3
        case .unknown(let id): return id
        }
    }

    public var name: String {
        switch self {
        case .void: return "void"
        case .integer: return "int"
        case .float: return "float"
        case .unknown(let id): return "type\(id)"
        }
    }

    public static func from(id: Int) -> ColoValueType {
        switch id & 0x1F {  // mask off flag bits
        case 0: return .void
        case 2: return .integer
        case 3: return .float
        default: return .unknown(id: id & 0x1F)
        }
    }
}

/// Colosseum script variable reference (1-byte mask encoding)
///
/// Encodes type + storage class in a single byte:
/// - Bits 0-4: Value type ID (0=void, 2=int, 3=float)
/// - Bit 5:    0x20 flag (rare, unknown purpose)
/// - Bit 6:    isLocal (function argument or local variable)
/// - Bit 7:    isLiteral (constant value already on stack)
///
/// Extended flag (from 2-byte reads):
/// - Bit 8:    isPointer (dereference required)
public struct ColoScriptVar: Equatable, CustomStringConvertible {
    public let valueType: ColoValueType
    public let isLocal: Bool
    public let isLiteral: Bool
    public let isPointer: Bool
    public let flag0x20: Bool

    public var isGlobal: Bool { !isLocal && !isLiteral }

    public var mask: UInt8 {
        var val = UInt8(valueType.id & 0x1F)
        if flag0x20 { val |= 0x20 }
        if isLocal { val |= 0x40 }
        if isLiteral { val |= 0x80 }
        return val
    }

    public var description: String {
        let typeStr = valueType.name
        let storageStr: String
        if isLiteral && isLocal {
            storageStr = "invalid"
        } else if isLiteral {
            storageStr = "literal"
        } else if isLocal {
            storageStr = "local"
        } else {
            storageStr = "global"
        }
        let modifier = isPointer ? "*" : ""
        return "\(typeStr)\(modifier) \(storageStr)"
    }

    public static func decode(from byte: UInt8) -> ColoScriptVar {
        ColoScriptVar(
            valueType: .from(id: Int(byte & 0x1F)),
            isLocal: (byte & 0x40) != 0,
            isLiteral: (byte & 0x80) != 0,
            isPointer: false,
            flag0x20: (byte & 0x20) != 0
        )
    }
}
