import GoDFoundation

/// Game-agnostic script intermediate representation.
/// Game-specific instruction decoders translate their native bytecode into these IR nodes.
/// The CFG and AST passes operate entirely on this representation.

/// A single IR instruction with its byte offset in the original script
public struct IRInstruction {
    /// Byte offset in the original bytecode (used for jump target resolution)
    public let offset: Int
    /// The IR operation
    public let op: IROp

    public init(offset: Int, op: IROp) {
        self.offset = offset
        self.op = op
    }
}

/// IR operations — the universal instruction set for the decompiler
public enum IROp: Equatable {
    // Stack operations
    case pushConstant(IRConstant)
    case pushVariable(IRVariable)
    case pop(count: Int)

    // Arithmetic / logic
    case binaryOp(IRBinaryOperator)
    case unaryOp(IRUnaryOperator)

    // Assignment
    case assign(target: IRVariable, source: IRVariable)
    case copyMemory(dest: IRVariable, source: IRVariable, length: Int)

    // Control flow
    case jump(target: Int)                   // unconditional jump to byte offset
    case jumpIfFalse(target: Int)            // conditional jump if stack top is false
    case jumpIfTrue(target: Int)             // conditional jump if stack top is true

    // Functions
    case callScript(functionIndex: Int, argCount: Int, returnCount: Int)
    case callBuiltIn(functionID: Int, argCount: Int, returnCount: Int)
    case returnVoid
    case returnValue

    // Special
    case yield(frames: Int)
    case printf(argCount: Int)
    case nop
    case exit

    /// Whether this instruction terminates a basic block
    public var isTerminator: Bool {
        switch self {
        case .jump, .jumpIfFalse, .jumpIfTrue, .returnVoid, .returnValue, .exit:
            return true
        default:
            return false
        }
    }

    /// The jump target offset, if this is a jump instruction
    public var jumpTarget: Int? {
        switch self {
        case .jump(let t), .jumpIfFalse(let t), .jumpIfTrue(let t):
            return t
        default:
            return nil
        }
    }

    /// Whether this is a conditional jump
    public var isConditionalJump: Bool {
        switch self {
        case .jumpIfFalse, .jumpIfTrue: return true
        default: return false
        }
    }
}

/// IR constant values
public enum IRConstant: Equatable {
    case integer(Int32)
    case float(Float)
    case void
    case string(Int)       // string table index
    case unknown(type: Int, rawValue: UInt32)
}

/// IR variable reference
public struct IRVariable: Equatable {
    public enum Storage: Equatable {
        case global(index: Int)
        case local(index: Int)       // function argument or local
        case literal                 // value already on stack
        case lastResult              // return value of previous call
    }

    public let storage: Storage
    public let valueType: IRValueType

    public init(storage: Storage, valueType: IRValueType) {
        self.storage = storage
        self.valueType = valueType
    }
}

/// IR value types
public enum IRValueType: Equatable {
    case void
    case integer
    case float
    case unknown(id: Int)
}

/// Binary operators
public enum IRBinaryOperator: String, Equatable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case bitwiseAnd = "&"
    case bitwiseOr = "|"
    case logicalAnd = "&&"
    case logicalOr = "||"
    case equal = "=="
    case notEqual = "!="
    case lessThan = "<"
    case lessThanEqual = "<="
    case greaterThan = ">"
    case greaterThanEqual = ">="
}

/// Unary operators
public enum IRUnaryOperator: String, Equatable {
    case not = "!"
    case negate = "-"
}

/// A decoded script function in IR form
public struct IRFunction {
    /// Function index in the script
    public let index: Int
    /// Number of arguments (inferred or declared)
    public let argCount: Int
    /// The IR instructions for this function
    public let instructions: [IRInstruction]
    /// Optional function name (from external metadata)
    public let name: String?

    public init(index: Int, argCount: Int, instructions: [IRInstruction], name: String? = nil) {
        self.index = index
        self.argCount = argCount
        self.instructions = instructions
        self.name = name
    }
}

/// A complete script in IR form (all functions)
public struct IRScript {
    public let functions: [IRFunction]

    public init(functions: [IRFunction]) {
        self.functions = functions
    }
}
