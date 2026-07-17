import GoDFoundation
import ScriptDecompiler
import Structs

// MARK: - Colosseum Expression Type

/// Colosseum-specific expression tree that supports the VM's variable wrapping model.
/// In the Colosseum VM, `pushVar` consumes a stack value (the index) and creates a
/// typed variable reference. Binary ops carry type annotations on their operands.
public indirect enum ColoExpr {
    case constant(ColoConstant)
    case variable(ColoScriptVar, ColoExpr)          // typed variable reference wrapping an index
    case variableAssignment(ColoExpr, ColoExpr)     // target = value
    case structAssignment(ColoExpr, ColoExpr, Int)   // memcpy(dst, src, len)
    case operation(ColoOperator, [ColoExpr])          // unary or binary op
    case call(Int, [ColoExpr])                        // script function call
    case callBuiltIn(Int, [ColoExpr])                 // engine built-in call
    case printf(String, [ColoExpr])                   // formatted print
    case yield(ColoExpr)                              // yield for N frames
    case returnVoid                                   // plain return
    case returnResult(ColoExpr)                       // return with value
    case jumpFalse(ColoExpr, Int)                     // conditional jump
    case jump(Int)                                    // unconditional jump
    case location(Int)                                // jump target marker
    case ifStatement([(ColoExpr, [ColoExpr])])        // if/elif/else chains
    case whileLoop(ColoExpr, [ColoExpr])              // while loop
    case exit
    case nop

    /// Whether this expression represents a full statement (not just a value)
    var isStatement: Bool {
        switch self {
        case .variableAssignment, .structAssignment, .call, .callBuiltIn,
             .printf, .yield, .returnVoid, .returnResult, .exit,
             .ifStatement, .whileLoop:
            return true
        default:
            return false
        }
    }
}

public enum ColoConstant: Equatable {
    case void(Int)
    case integer(Int32)
    case float(Float)
    case unknown(typeID: Int, value: Int)

    var text: String {
        switch self {
        case .void: return "null"
        case .integer(let v): return abs(v) < 0x100 ? "\(v)" : "0x\(String(UInt32(bitPattern: v), radix: 16, uppercase: true))"
        case .float(let v): return "\(v)"
        case .unknown(let t, let v): return "type\(t)(\(v))"
        }
    }

    var intValue: Int32? {
        switch self {
        case .integer(let v): return v
        case .void(let v): return Int32(v)
        default: return nil
        }
    }
}

public enum ColoOperator: String {
    case add = "+", subtract = "-", multiply = "*", divide = "/", mod = "%"
    case and = "&", or = "|", logicalAnd = "&&", logicalOr = "||"
    case equal = "==", notEqual = "!=", lessThan = "<", lessThanEqual = "<="
    case greaterThan = ">", greaterThanEqual = ">="
    case not = "!"
    case negate = "negate"  // rendered specially in formatter

    public var symbol: String {
        self == .negate ? "-" : rawValue
    }
}

// MARK: - Pass 1: Stack Simulation → Flat Expression List

public struct ColoExpressionBuilder {

    public init() {}

    /// Build a flat expression list for a single function (Pass 1)
    public func buildExpressions(instructions: [ColoScriptInstruction]) -> (expressions: [ColoExpr], argCount: Int) {
        var stack = [ColoExpr]()
        var expressions = [ColoExpr]()
        var argCount = 0

        // Collect jump targets for location markers
        var jumpTargets = Set<Int>()
        for inst in instructions {
            if let target = inst.jumpTarget {
                jumpTargets.insert(Int(target))
            }
        }

        var currentOffset = 0
        for inst in instructions {
            // Insert location marker at jump targets
            if jumpTargets.contains(inst.offset) {
                expressions.append(.location(inst.offset))
            }
            currentOffset = inst.offset

            switch inst.opcode {
            case .nop:
                break
            case .exit:
                break
            case .pushMinus1:
                stack.append(.constant(.integer(-1)))
            case .pop:
                // No-op for the expression stack (legacy tool ignores pop)
                break

            case .call(let funcID, _, let argc):
                var args = [ColoExpr]()
                for _ in 0..<argc {
                    args.append(safePop(&stack))
                }
                stack.append(.call(Int(funcID), args.reversed()))

            case .returnOp:
                // Peek: if top is `variableAssignment(variable(local, const(0)), value)`, convert to returnResult
                if let top = stack.last, case .variableAssignment(let target, let value) = top {
                    if case .variable(let v, .constant(.integer(0))) = target, v.isLocal {
                        stack.removeLast()
                        expressions.append(.returnResult(value))
                    } else {
                        expressions.append(.returnVoid)
                    }
                } else {
                    expressions.append(.returnVoid)
                }

            case .jump(let offset):
                expressions.append(.jump(Int(offset)))

            case .jumpFalse(let offset):
                let condition = safePop(&stack)
                expressions.append(.jumpFalse(condition, Int(offset)))

            case .pushImmediate(let type, let value):
                switch type {
                case .integer: stack.append(.constant(.integer(Int32(bitPattern: value))))
                case .float: stack.append(.constant(.float(Float(bitPattern: value))))
                case .void: stack.append(.constant(.void(Int(value))))
                case .unknown(let id): stack.append(.constant(.unknown(typeID: id, value: Int(value))))
                }

            case .pushVar(let v):
                handlePushVar(v, stack: &stack, argCount: &argCount)
            case .pushMultiVar(let v, _):
                handlePushVar(v, stack: &stack, argCount: &argCount)
            case .pushVar2(let v):
                handlePushVar(v, stack: &stack, argCount: &argCount)

            case .not(let v):
                let arg = safePop(&stack)
                stack.append(.operation(.not, [ColoExpr.variable(v, arg)]))
            case .negate(let v):
                let arg = safePop(&stack)
                stack.append(.operation(.negate, [ColoExpr.variable(v, arg)]))

            case .bitwiseAnd(let v1, let v2): handleBinaryOp(.and, v1: v1, v2: v2, stack: &stack)
            case .bitwiseOr(let v1, let v2): handleBinaryOp(.or, v1: v1, v2: v2, stack: &stack)
            case .multiply(let v1, let v2): handleBinaryOp(.multiply, v1: v1, v2: v2, stack: &stack)
            case .divide(let v1, let v2): handleBinaryOp(.divide, v1: v1, v2: v2, stack: &stack)
            case .mod(let v1, let v2): handleBinaryOp(.mod, v1: v1, v2: v2, stack: &stack)
            case .add(let v1, let v2): handleBinaryOp(.add, v1: v1, v2: v2, stack: &stack)
            case .subtract(let v1, let v2): handleBinaryOp(.subtract, v1: v1, v2: v2, stack: &stack)
            case .lessThan(let v1, let v2): handleBinaryOp(.lessThan, v1: v1, v2: v2, stack: &stack)
            case .lessThanEqual(let v1, let v2): handleBinaryOp(.lessThanEqual, v1: v1, v2: v2, stack: &stack)
            case .greaterThan(let v1, let v2): handleBinaryOp(.greaterThan, v1: v1, v2: v2, stack: &stack)
            case .greaterThanEqual(let v1, let v2): handleBinaryOp(.greaterThanEqual, v1: v1, v2: v2, stack: &stack)
            case .equal(let v1, let v2): handleBinaryOp(.equal, v1: v1, v2: v2, stack: &stack)
            case .notEqual(let v1, let v2): handleBinaryOp(.notEqual, v1: v1, v2: v2, stack: &stack)
            case .logicalAnd(let v1, let v2): handleBinaryOp(.logicalAnd, v1: v1, v2: v2, stack: &stack)
            case .logicalOr(let v1, let v2): handleBinaryOp(.logicalOr, v1: v1, v2: v2, stack: &stack)

            case .setVar(let source, let target):
                let value = safePop(&stack)
                let targetExpr = safePop(&stack)
                stack.append(.variableAssignment(
                    ColoExpr.variable(target, targetExpr),
                    ColoExpr.variable(source, value)
                ))

            case .copyStruct(let source, let dest, let length):
                let arg2 = safePop(&stack)
                let arg1 = safePop(&stack)
                stack.append(.structAssignment(
                    ColoExpr.variable(source, arg1),
                    ColoExpr.variable(dest, arg2),
                    Int(length)
                ))

            case .printf(_, let argc):
                var args = [ColoExpr]()
                // `argc` includes the format-string pointer; the real
                // args are `argc - 1`. Clamp so `argc == 0` doesn't form
                // an invalid range (`1..<0`) and trap the decompile.
                for _ in 0..<max(0, Int(argc) - 1) {
                    args.append(safePop(&stack))
                }
                // Last pop is the format string pointer
                let formatExpr = safePop(&stack)
                let formatStr: String
                if case .constant(.integer(let offset)) = formatExpr {
                    formatStr = "string@\(offset)"
                } else {
                    formatStr = "?"
                }
                stack.append(.printf(formatStr, args))

            case .yield(_, _):
                let frames = safePop(&stack)
                stack.append(.yield(frames))

            case .callStandard(_, let argc):
                // Pop argc-1 real arguments. Clamp so `argc == 0` doesn't
                // form an invalid range (`0..<(-1)`) and trap.
                var args = [ColoExpr]()
                for _ in 0..<max(0, Int(argc) - 1) {
                    args.append(safePop(&stack))
                }
                // Pop function ID (search for integer constant)
                var functionID: Int = 0
                while !stack.isEmpty && functionID == 0 {
                    let expr = safePop(&stack)
                    if case .constant(.integer(let id)) = expr {
                        functionID = Int(id)
                    }
                }
                // Pop object reference (local var 0, always precedes builtin calls)
                if !stack.isEmpty {
                    _ = safePop(&stack)
                }
                stack.append(.callBuiltIn(functionID, args.reversed()))

            case .invalid:
                break
            }

            // After processing, insert location marker if next instruction is a target
            let nextOffset = inst.offset + inst.opcode.length
            if jumpTargets.contains(nextOffset) && inst.opcode != .returnOp {
                // Flush any pending statements from the stack
                flushStatements(&stack, into: &expressions)
            }
        }

        // Flush remaining stack into expressions
        flushStatements(&stack, into: &expressions)

        return (expressions, argCount)
    }

    // MARK: - Helpers

    private func safePop(_ stack: inout [ColoExpr]) -> ColoExpr {
        stack.isEmpty ? .constant(.void(0)) : stack.removeLast()
    }

    private func handlePushVar(_ v: ColoScriptVar, stack: inout [ColoExpr], argCount: inout Int) {
        let indexExpr = safePop(&stack)
        if v.isLocal {
            if case .constant(.integer(let idx)) = indexExpr {
                argCount = max(argCount, Int(idx) + 1)
            }
        }
        if v.isLiteral {
            stack.append(indexExpr)
        } else {
            stack.append(.variable(v, indexExpr))
        }
    }

    private func handleBinaryOp(_ op: ColoOperator, v1: ColoScriptVar, v2: ColoScriptVar, stack: inout [ColoExpr]) {
        let arg1 = safePop(&stack)  // RHS
        let arg2 = safePop(&stack)  // LHS
        // Legacy: operation(op, [variable(var1, arg1_rhs), variable(var2, arg2_lhs)])
        // Text rendering: exprs[1] op exprs[0] = var2(LHS) op var1(RHS)
        stack.append(.operation(op, [ColoExpr.variable(v1, arg1), ColoExpr.variable(v2, arg2)]))
    }

    private func flushStatements(_ stack: inout [ColoExpr], into expressions: inout [ColoExpr]) {
        while let expr = stack.popLast() {
            expressions.append(expr)
        }
    }
}

// MARK: - Pass 2: Compound Expressions

public struct ColoExpressionCompound {

    public init() {}

    public func compound(_ expressions: [ColoExpr]) -> [ColoExpr] {
        var result = expressions
        result = compoundIfStatements(result)
        result = compoundWhileLoops(result)
        result = compoundElseStatements(result)
        return result
    }

    /// Convert jumpFalse(cond, targetOffset) → exprs → location(targetOffset) into ifStatement
    private func compoundIfStatements(_ exprs: [ColoExpr]) -> [ColoExpr] {
        var result = [ColoExpr]()
        var i = 0
        while i < exprs.count {
            if case .jumpFalse(let condition, let target) = exprs[i] {
                // Collect body until we find the matching location
                var body = [ColoExpr]()
                i += 1
                while i < exprs.count {
                    if case .location(let loc) = exprs[i], loc == target {
                        break
                    }
                    body.append(exprs[i])
                    i += 1
                }
                // Recursively compound the body
                let compoundedBody = compoundIfStatements(body)
                result.append(.ifStatement([(condition, compoundedBody)]))
            } else {
                result.append(exprs[i])
            }
            i += 1
        }
        return result
    }

    /// Convert jump(backOffset) at end of if body + jumpFalse at backOffset into while loop
    private func compoundWhileLoops(_ exprs: [ColoExpr]) -> [ColoExpr] {
        var result = [ColoExpr]()
        var i = 0
        while i < exprs.count {
            if case .location(let locOffset) = exprs[i] {
                // Check if there's a jumpFalse right after this location followed by a body ending with jump(locOffset)
                if i + 1 < exprs.count, case .ifStatement(let branches) = exprs[i + 1] {
                    if let lastInBody = branches.first?.1.last, case .jump(let jumpTarget) = lastInBody, jumpTarget == locOffset {
                        // While loop detected
                        let condition = branches[0].0
                        var body = Array(branches[0].1.dropLast()) // remove the back-jump
                        body = compoundWhileLoops(body) // recurse
                        result.append(.whileLoop(condition, body))
                        i += 2
                        continue
                    }
                }
                result.append(exprs[i])
            } else {
                result.append(exprs[i])
            }
            i += 1
        }
        return result
    }

    /// Convert if { ... jump } followed by if into if-else
    private func compoundElseStatements(_ exprs: [ColoExpr]) -> [ColoExpr] {
        var result = [ColoExpr]()
        var i = 0
        while i < exprs.count {
            if case .ifStatement(var branches) = exprs[i] {
                // Check if the then-body ends with a jump and the next expression starts the else body
                if let lastBranch = branches.last,
                   let lastInBody = lastBranch.1.last,
                   case .jump(let jumpTarget) = lastInBody {
                    // Look for a location(jumpTarget) later → the code between is the else body
                    var elseBody = [ColoExpr]()
                    var j = i + 1
                    var foundEnd = false
                    while j < exprs.count {
                        if case .location(let loc) = exprs[j], loc == jumpTarget {
                            foundEnd = true
                            break
                        }
                        elseBody.append(exprs[j])
                        j += 1
                    }
                    if foundEnd && !elseBody.isEmpty {
                        // Remove the jump from the then-body
                        var thenBody = Array(lastBranch.1.dropLast())
                        thenBody = compoundElseStatements(thenBody)
                        elseBody = compoundElseStatements(elseBody)
                        branches[branches.count - 1] = (lastBranch.0, thenBody)
                        // Add else as a branch with "true" condition (always taken)
                        branches.append((.constant(.integer(1)), elseBody))
                        result.append(.ifStatement(branches))
                        i = j + 1
                        continue
                    }
                }
                // Recursively compound sub-bodies
                let compounded = branches.map { (cond, body) in
                    (cond, compoundElseStatements(body))
                }
                result.append(.ifStatement(compounded))
            } else {
                result.append(exprs[i])
            }
            i += 1
        }
        return result
    }
}

// MARK: - Text Formatting

public struct ColoExprFormatter {

    public let builtInFunctions: [Int: ScriptFunctionDef]
    /// Engine enums keyed by name, used to resolve integer constants to enum case names
    public let enums: [String: Enum]
    public let indent: String

    public init(
        builtInFunctions: [Int: ScriptFunctionDef] = [:],
        enums: [String: Enum] = [:],
        indent: String = "    "
    ) {
        self.builtInFunctions = builtInFunctions
        self.enums = enums
        self.indent = indent
    }

    public func formatFunction(index: Int, name: String, argCount: Int, body: [ColoExpr]) -> String {
        let args = (0..<argCount).map { "arg\($0)" }.joined(separator: ", ")
        var lines = ["func \(name)(\(args)) {"]
        lines += formatExprs(body, depth: 1)
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    public func formatExprs(_ exprs: [ColoExpr], depth: Int) -> [String] {
        let prefix = String(repeating: indent, count: depth)
        var lines = [String]()

        for expr in exprs {
            switch expr {
            case .variableAssignment(let target, let value):
                lines.append("\(prefix)\(formatExpr(target)) = \(formatExpr(value))")
            case .structAssignment(let dst, let src, let len):
                lines.append("\(prefix)\(formatExpr(dst))[0:\(len)] = \(formatExpr(src))[0:\(len)]")
            case .call(let funcID, let args):
                let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
                lines.append("\(prefix)function_\(funcID)(\(argStr))")
            case .callBuiltIn(let funcID, let args):
                let funcDef = builtInFunctions[funcID]
                let name = funcDef?.name ?? "builtin_\(funcID)"
                let argStr = formatCallArgs(args, paramDefs: funcDef?.parameters ?? [])
                lines.append("\(prefix)\(name)(\(argStr))")
            case .printf(let fmt, let args):
                let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
                lines.append("\(prefix)printf(\"\(fmt)\", \(argStr))")
            case .yield(let frames):
                lines.append("\(prefix)yield(\(formatExpr(frames)))")
            case .returnVoid:
                lines.append("\(prefix)return")
            case .returnResult(let value):
                lines.append("\(prefix)return \(formatExpr(value))")
            case .ifStatement(let branches):
                for (bi, branch) in branches.enumerated() {
                    if bi == 0 {
                        lines.append("\(prefix)if \(formatExpr(branch.0)) {")
                    } else if case .constant(.integer(1)) = branch.0 {
                        lines.append("\(prefix)} else {")
                    } else {
                        lines.append("\(prefix)} else if \(formatExpr(branch.0)) {")
                    }
                    lines += formatExprs(branch.1, depth: depth + 1)
                }
                lines.append("\(prefix)}")
            case .whileLoop(let condition, let body):
                lines.append("\(prefix)while \(formatExpr(condition)) {")
                lines += formatExprs(body, depth: depth + 1)
                lines.append("\(prefix)}")
            case .location:
                break  // Consumed by compounding
            case .jump:
                break  // Consumed by compounding (or leftover = goto)
            case .exit:
                break
            case .nop:
                break
            default:
                // Bare expression (shouldn't happen often after compounding)
                lines.append("\(prefix)\(formatExpr(expr))")
            }
        }

        return lines
    }

    public func formatExpr(_ expr: ColoExpr) -> String {
        switch expr {
        case .constant(let c):
            return c.text
        case .variable(let v, let indexExpr):
            if v.isGlobal {
                return "gvar\(formatExpr(indexExpr))"
            } else if v.isLocal {
                return "arg\(formatExpr(indexExpr))"
            } else { // literal
                return formatExpr(indexExpr)
            }
        case .operation(let op, let operands):
            if operands.count == 1 {
                return "\(op.symbol)\(formatExpr(operands[0]))"
            } else if operands.count == 2 {
                // Legacy order: exprs[1] op exprs[0] = LHS op RHS
                return "\(formatExpr(operands[1])) \(op.symbol) \(formatExpr(operands[0]))"
            }
            return "op(\(operands.map { formatExpr($0) }.joined(separator: ", ")))"
        case .call(let funcID, let args):
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "function_\(funcID)(\(argStr))"
        case .callBuiltIn(let funcID, let args):
            let funcDef = builtInFunctions[funcID]
            let name = funcDef?.name ?? "builtin_\(funcID)"
            let argStr = formatCallArgs(args, paramDefs: funcDef?.parameters ?? [])
            return "\(name)(\(argStr))"
        case .yield(let frames):
            return "yield(\(formatExpr(frames)))"
        case .variableAssignment(let target, let value):
            return "\(formatExpr(target)) = \(formatExpr(value))"
        default:
            return "<?>"
        }
    }

    /// Format function call arguments, applying macro resolution based on parameter type definitions
    private func formatCallArgs(_ args: [ColoExpr], paramDefs: [ScriptFunctionDef.ParameterDef]) -> String {
        args.enumerated().map { (i, arg) in
            let paramType = i < paramDefs.count ? paramDefs[i].type : nil
            return formatArgWithType(arg, type: paramType)
        }.joined(separator: ", ")
    }

    /// Format a single argument, resolving to an enum case name if the parameter type is an enum ref
    private func formatArgWithType(_ expr: ColoExpr, type: ScriptParamType?) -> String {
        guard let type = type else { return formatExpr(expr) }

        switch type {
        case .bool:
            // Resolve bools directly
            if case .constant(.integer(let v)) = expr { return v != 0 ? "true" : "false" }
            if case .variable(let vr, .constant(.integer(let v))) = expr, vr.isLiteral { return v != 0 ? "true" : "false" }
        case .enumRef(let enumName):
            // Look up the enum and find a DEFINED case matching the raw value
            if let enumDef = enums[enumName] {
                let rawValue: Int?
                switch expr {
                case .constant(.integer(let v)): rawValue = Int(v)
                case .variable(let vr, .constant(.integer(let v))) where vr.isLiteral: rawValue = Int(v)
                default: rawValue = nil
                }
                // Only use enum case if it's explicitly defined (not auto-generated)
                if let raw = rawValue,
                   let enumCase = enumDef.values.first(where: { $0.rawValue == raw }) {
                    return "\(enumName).\(enumCase.name)"
                }
            }
        default:
            break
        }

        return formatExpr(expr)
    }
}
