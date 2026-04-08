import GoDFoundation

/// XD script opcodes (18 total, word-based encoding)
///
/// Each instruction is 1-2 UInt32 words:
/// ```
/// Word 1: [opcode:8][subopcode:8][parameter:16]
/// Word 2: [extended value:32]  (optional)
/// ```
public enum XDScriptOpcodeID: UInt8, Equatable {
    case nop = 0
    case xdOperator = 1      // subopcode = operator ID
    case loadImmediate = 2    // 2 words: subopcode = constant type, word2 = value
    case loadVariable = 3     // subopcode lower = level, parameter = index
    case setVariable = 4      // subopcode lower = level, parameter = index
    case setVector = 5        // subopcode upper = dimension, lower = level
    case pop = 6              // subopcode = count
    case call = 7             // longParameter (24-bit) = function address
    case returnOp = 8
    case callStandard = 9     // subopcode = class ID, parameter = method ID
    case jumpIfTrue = 10      // longParameter = target address
    case jumpIfFalse = 11     // longParameter = target address
    case jump = 12            // longParameter = target address
    case reserve = 13         // subopcode = count
    case release = 14         // subopcode = count
    case exit = 15
    case setLine = 16         // parameter = line number
    case loadNonCopyableVariable = 17  // same as loadVariable but by reference
}

/// A decoded XD script instruction
public struct XDScriptInstruction: Equatable {
    /// The opcode
    public let opcodeID: XDScriptOpcodeID
    /// Full 8-bit sub-opcode
    public let subOpCode: Int
    /// Upper 4 bits of sub-opcode
    public var subOpCodeUpper: Int { subOpCode >> 4 }
    /// Lower 4 bits of sub-opcode (variable level)
    public var level: Int { subOpCode & 0xF }
    /// 16-bit parameter (signed)
    public let parameter: Int16
    /// 24-bit parameter for jumps/calls
    public let longParameter: Int
    /// Second word value (for loadImmediate)
    public let constantValue: UInt32?
    /// Byte offset in the CODE section (in words, multiply by 4 for bytes)
    public let codeOffset: Int
    /// Number of words this instruction occupies (1 or 2)
    public var wordCount: Int { constantValue != nil ? 2 : 1 }

    public init(
        opcodeID: XDScriptOpcodeID,
        subOpCode: Int,
        parameter: Int16,
        longParameter: Int,
        constantValue: UInt32? = nil,
        codeOffset: Int
    ) {
        self.opcodeID = opcodeID
        self.subOpCode = subOpCode
        self.parameter = parameter
        self.longParameter = longParameter
        self.constantValue = constantValue
        self.codeOffset = codeOffset
    }

    /// Decode an instruction from a word (and optionally the next word)
    public static func decode(word1: UInt32, word2: UInt32?, codeOffset: Int) -> XDScriptInstruction {
        let opByte = UInt8((word1 >> 24) & 0xFF)
        let subOp = Int((word1 >> 16) & 0xFF)
        let param = Int16(bitPattern: UInt16(word1 & 0xFFFF))
        let longParam = Int(word1 & 0xFFFFFF)

        let opcodeID = XDScriptOpcodeID(rawValue: opByte) ?? .nop

        // loadImmediate uses the second word as the constant value
        let constVal: UInt32?
        if opcodeID == .loadImmediate {
            constVal = word2
        } else {
            constVal = nil
        }

        return XDScriptInstruction(
            opcodeID: opcodeID,
            subOpCode: subOp,
            parameter: param,
            longParameter: longParam,
            constantValue: constVal,
            codeOffset: codeOffset
        )
    }

    /// Encode this instruction back to 1 or 2 UInt32 words
    public func encode() -> [UInt32] {
        var word1: UInt32 = 0
        word1 |= UInt32(opcodeID.rawValue) << 24
        word1 |= UInt32(subOpCode & 0xFF) << 16
        word1 |= UInt32(UInt16(bitPattern: parameter))

        var words = [word1]
        if let cv = constantValue {
            words.append(cv)
        }
        return words
    }

    /// Whether this is a 2-word instruction
    public var isTwoWord: Bool { opcodeID == .loadImmediate }

    /// Whether this instruction is a jump
    public var isJump: Bool {
        switch opcodeID {
        case .jump, .jumpIfTrue, .jumpIfFalse: return true
        default: return false
        }
    }

    /// Jump target (word offset in CODE section), if this is a jump
    public var jumpTarget: Int? {
        guard isJump else { return nil }
        return longParameter
    }

    /// Whether this terminates a basic block
    public var isTerminator: Bool {
        switch opcodeID {
        case .jump, .jumpIfTrue, .jumpIfFalse, .returnOp, .exit: return true
        default: return false
        }
    }

    /// For callStandard: the class ID
    public var classID: Int? {
        guard opcodeID == .callStandard else { return nil }
        return subOpCode
    }

    /// For callStandard: the method ID
    public var methodID: Int? {
        guard opcodeID == .callStandard else { return nil }
        return Int(parameter)
    }
}

// MARK: - XD Operators

/// XD script operators (used with opcode 1)
public enum XDScriptOperator: Int, Equatable {
    // Unary (16-25)
    case not = 16
    case negate = 17
    case hex = 18
    case string = 19
    case integer = 20
    case float = 21
    case getVX = 22
    case getVY = 23
    case getVZ = 24
    case zeroFloat = 25

    // Binary arithmetic (32-39)
    case xor = 32
    case bitwiseOr = 33
    case bitwiseAnd = 34
    case add = 35
    case subtract = 36
    case multiply = 37
    case divide = 38
    case modulo = 39

    // Comparison (48-53)
    case equal = 48
    case greaterThan = 49
    case greaterThanEqual = 50
    case lessThan = 51
    case lessThanEqual = 52
    case notEqual = 53

    public var isUnary: Bool { rawValue >= 16 && rawValue <= 25 }
    public var isBinary: Bool { rawValue >= 32 }

    public var symbol: String {
        switch self {
        case .not: return "!"
        case .negate: return "-"
        case .hex: return "hex"
        case .string: return "str"
        case .integer: return "int"
        case .float: return "float"
        case .getVX: return ".vx"
        case .getVY: return ".vy"
        case .getVZ: return ".vz"
        case .zeroFloat: return "~0.0"
        case .xor: return "^"
        case .bitwiseOr: return "|"
        case .bitwiseAnd: return "&"
        case .add: return "+"
        case .subtract: return "-"
        case .multiply: return "*"
        case .divide: return "/"
        case .modulo: return "%"
        case .equal: return "=="
        case .greaterThan: return ">"
        case .greaterThanEqual: return ">="
        case .lessThan: return "<"
        case .lessThanEqual: return "<="
        case .notEqual: return "!="
        }
    }
}

// MARK: - XD Constant Types

/// Constant type IDs for loadImmediate
public enum XDConstantType: Int, Equatable {
    case void = 0
    case integer = 1
    case float = 2
    case string = 3
    case vector = 4
    case matrix = 5
    case object = 6
    case array = 7
    case text = 8            // XD only
    case character = 35      // XD only
    case pokemonIndex = 37   // XD only
    case codePointer = 53
}
