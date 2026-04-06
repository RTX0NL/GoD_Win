import GoDFoundation

/// A decoded Colosseum script instruction with its byte offset
public struct ColoScriptInstruction: Equatable {
    /// Byte offset within the bytecode section
    public let offset: Int
    /// The decoded opcode with operands
    public let opcode: ColoScriptOpcode

    public init(offset: Int, opcode: ColoScriptOpcode) {
        self.offset = offset
        self.opcode = opcode
    }

    /// Byte length of this instruction
    public var length: Int { opcode.length }

    /// Whether this instruction is a jump (conditional or unconditional)
    public var isJump: Bool {
        switch opcode {
        case .jump, .jumpFalse: return true
        default: return false
        }
    }

    /// The target offset of a jump instruction, or nil if not a jump
    public var jumpTarget: UInt32? {
        switch opcode {
        case .jump(let off), .jumpFalse(let off): return off
        default: return nil
        }
    }

    /// Whether this instruction terminates a basic block
    public var isTerminator: Bool {
        switch opcode {
        case .jump, .jumpFalse, .returnOp, .exit: return true
        default: return false
        }
    }
}
