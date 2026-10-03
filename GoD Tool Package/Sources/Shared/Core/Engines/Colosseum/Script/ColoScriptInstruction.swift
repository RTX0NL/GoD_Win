import GoDFoundation

/// A decoded Colosseum script instruction with its byte offset
public struct ColoScriptInstruction: Equatable {
    /// Byte offset within the bytecode section
    public let offset: Int
    public let opcode: ColoScriptOpcode

    public init(offset: Int, opcode: ColoScriptOpcode) {
        self.offset = offset
        self.opcode = opcode
    }

    public var length: Int { opcode.length }

    public var isJump: Bool {
        switch opcode {
        case .jump, .jumpFalse: return true
        default: return false
        }
    }

    public var jumpTarget: UInt32? {
        switch opcode {
        case .jump(let off), .jumpFalse(let off): return off
        default: return nil
        }
    }

    public var isTerminator: Bool {
        switch opcode {
        case .jump, .jumpFalse, .returnOp, .exit: return true
        default: return false
        }
    }
}
