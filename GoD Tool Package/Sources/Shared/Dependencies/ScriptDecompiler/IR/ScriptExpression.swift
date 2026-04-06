import GoDFoundation

/// Expression tree nodes produced by stack-based decompilation of IR instructions.
/// These represent the "what" of computation without control flow structure.
public indirect enum ScriptExpr: Equatable {
    // Values
    case constant(IRConstant)
    case variable(IRVariable)
    case lastResult

    // Operations
    case binary(IRBinaryOperator, ScriptExpr, ScriptExpr)
    case unary(IRUnaryOperator, ScriptExpr)

    // Function calls
    case callScript(functionIndex: Int, args: [ScriptExpr], name: String?)
    case callBuiltIn(functionID: Int, args: [ScriptExpr], name: String?)

    // Special
    case printf(args: [ScriptExpr])

    /// Human-readable description for debugging
    public var summary: String {
        switch self {
        case .constant(let c):
            switch c {
            case .integer(let v): return "\(v)"
            case .float(let v): return "\(v)"
            case .void: return "void"
            case .string(let i): return "string(\(i))"
            case .unknown(let t, let v): return "raw(\(t), 0x\(String(v, radix: 16)))"
            }
        case .variable(let v):
            switch v.storage {
            case .global(let i): return "global_\(i)"
            case .local(let i): return "local_\(i)"
            case .literal: return "lit"
            case .lastResult: return "result"
            }
        case .lastResult: return "result"
        case .binary(let op, let l, let r): return "(\(l.summary) \(op.rawValue) \(r.summary))"
        case .unary(let op, let e): return "\(op.rawValue)\(e.summary)"
        case .callScript(let i, let args, let name):
            let argStr = args.map(\.summary).joined(separator: ", ")
            return "\(name ?? "function_\(i)")(\(argStr))"
        case .callBuiltIn(let i, let args, let name):
            let argStr = args.map(\.summary).joined(separator: ", ")
            return "\(name ?? "builtin_\(i)")(\(argStr))"
        case .printf(let args):
            let argStr = args.map(\.summary).joined(separator: ", ")
            return "printf(\(argStr))"
        }
    }
}

/// A statement produced by stack-based decompilation — an expression with context.
/// Statements include assignments, bare calls, yields, and control flow primitives.
public enum ScriptStatement: Equatable {
    /// Variable assignment: target = expression
    case assign(target: IRVariable, value: ScriptExpr)
    /// Memory copy
    case copyMemory(dest: IRVariable, source: IRVariable, length: Int)
    /// Expression evaluated for side effects (typically a function call)
    case expression(ScriptExpr)
    /// Return with no value
    case returnVoid
    /// Return with a value on the stack
    case returnValue(ScriptExpr)
    /// Yield execution for N frames
    case yield(frames: Int)
    /// Conditional jump (kept as-is until CFG structuring)
    case jumpIfFalse(condition: ScriptExpr, target: Int)
    case jumpIfTrue(condition: ScriptExpr, target: Int)
    /// Unconditional jump (kept as-is until CFG structuring)
    case jump(target: Int)
    /// Label at a jump target
    case label(offset: Int)
    /// No-op / exit
    case nop
    case exit
}
