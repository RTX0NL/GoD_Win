import GoDFoundation
import ScriptDecompiler
import Structs

// MARK: - Colosseum Expression Type

/// Colosseum-specific expression tree that supports the VM's variable wrapping model.
/// In the Colosseum VM, `pushVar` consumes a stack value (the index) and creates a
/// typed variable reference. Binary ops carry type annotations on their operands.
/// Which opcode produced a variable read. `.wrap` marks consumer-owned
/// wraps (binary op / setVar operands) whose mask is encoded in the consumer
/// instruction rather than by a push of its own.
public enum ColoVarPushForm: Equatable {
    case wrap                // no push — mask carried by the consumer instruction
    case single              // pushVar (opcode 15)
    case single2             // pushVar2 (opcode 19)
    case multi(UInt16)       // pushMultiVar (opcode 16)
}

public indirect enum ColoExpr {
    case constant(ColoConstant)
    case variable(ColoScriptVar, ColoExpr, ColoVarPushForm)  // typed variable reference wrapping an index
    case variableAssignment(ColoExpr, ColoExpr)     // target = value
    case structAssignment(ColoExpr, ColoExpr, Int)   // memcpy(dst, src, len)
    case operation(ColoOperator, [ColoExpr])          // unary or binary op
    case call(Int, returnCount: Int, [ColoExpr])      // script function call
    case callBuiltIn(ColoExpr, [ColoExpr])            // engine built-in call (ID is usually a constant, but can be computed)
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

    /// Binding strength for text output/parsing (higher binds tighter).
    /// All binary operators are left-associative.
    public var precedence: Int {
        switch self {
        case .not, .negate: return 7
        case .multiply, .divide, .mod: return 6
        case .add, .subtract: return 5
        case .lessThan, .lessThanEqual, .greaterThan, .greaterThanEqual: return 4
        case .equal, .notEqual: return 3
        case .and, .or: return 2
        case .logicalAnd: return 1
        case .logicalOr: return 0
        }
    }
}

// MARK: - Pass 1: Stack Simulation → Flat Expression List

public struct ColoExpressionBuilder {

    public init() {}

    public func buildExpressions(instructions: [ColoScriptInstruction]) -> (expressions: [ColoExpr], argCount: Int) {
        var stack = [ColoExpr]()
        var expressions = [ColoExpr]()
        var argCount = 0

        var jumpTargets = Set<Int>()
        for inst in instructions {
            if let target = inst.jumpTarget {
                jumpTargets.insert(Int(target))
            }
        }

        for inst in instructions {
            if jumpTargets.contains(inst.offset) {
                expressions.append(.location(inst.offset))
            }

            switch inst.opcode {
            case .nop:
                break
            case .exit:
                flushStatements(&stack, into: &expressions)
                expressions.append(.exit)
            case .pushMinus1:
                stack.append(.constant(.integer(-1)))
            case .pop:
                // No-op for the expression stack (legacy tool ignores pop)
                break

            case .call(let funcID, let returnCount, let argc):
                var args = [ColoExpr]()
                for _ in 0..<argc {
                    args.append(safePop(&stack))
                }
                // A value-returning call is preceded by a return-slot push
                // (`local0`) below its arguments — consume it. Leaving it on
                // the stack silently corrupts every later expression.
                if returnCount == 1, !stack.isEmpty {
                    _ = safePop(&stack)
                }
                stack.append(.call(Int(funcID), returnCount: Int(returnCount), args.reversed()))

            case .returnOp:
                // Peek: if top is `variableAssignment(variable(local, const(0)), value)`, convert to returnResult.
                // Consume the return value first, then flush the preceding
                // statements so they emit *before* the return (previously the
                // return was emitted inline while pending side-effect calls
                // stayed parked on the stack and flushed after it — producing
                // a `return` followed by the whole function body).
                var returnExpr: ColoExpr = .returnVoid
                if let top = stack.last, case .variableAssignment(let target, let value) = top,
                   case .variable(let v, .constant(.integer(0)), _) = target, v.isLocal {
                    stack.removeLast()
                    returnExpr = .returnResult(value)
                }
                flushStatements(&stack, into: &expressions)
                expressions.append(returnExpr)

            case .jump(let offset):
                flushStatements(&stack, into: &expressions)
                expressions.append(.jump(Int(offset)))

            case .jumpFalse(let offset):
                // Pop the branch condition, then flush the statements that
                // precede the branch so they emit before the jump.
                let condition = safePop(&stack)
                flushStatements(&stack, into: &expressions)
                expressions.append(.jumpFalse(condition, Int(offset)))

            case .pushImmediate(let type, let value):
                switch type {
                case .integer: stack.append(.constant(.integer(Int32(bitPattern: value))))
                case .float: stack.append(.constant(.float(Float(bitPattern: value))))
                case .void: stack.append(.constant(.void(Int(value))))
                case .unknown(let id): stack.append(.constant(.unknown(typeID: id, value: Int(value))))
                }

            case .pushVar(let v):
                handlePushVar(v, form: .single, stack: &stack, argCount: &argCount)
            case .pushMultiVar(let v, let count):
                // The VM resolves the variable once (consuming one index from
                // the stack) then pushes the result `count` times. Duplicate
                // the wrapped expression for the remaining count-1 pushes so
                // the expression stack stays aligned. The legacy tool left
                // count > 1 unhandled ("Unhandled push multi var with
                // count > 1"), silently corrupting every later expression in
                // the function. Real data: M2_enter_1F.scd uses count=3 twice.
                handlePushVar(v, form: .multi(count), stack: &stack, argCount: &argCount)
                if count > 1, let top = stack.last {
                    for _ in 1..<count { stack.append(top) }
                }
            case .pushVar2(let v):
                handlePushVar(v, form: .single2, stack: &stack, argCount: &argCount)

            case .not(let v):
                let arg = safePop(&stack)
                stack.append(.operation(.not, [ColoExpr.variable(v, arg, .wrap)]))
            case .negate(let v):
                let arg = safePop(&stack)
                stack.append(.operation(.negate, [ColoExpr.variable(v, arg, .wrap)]))

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
                    ColoExpr.variable(target, targetExpr, .wrap),
                    ColoExpr.variable(source, value, .wrap)
                ))

            case .copyStruct(let source, let dest, let length):
                let arg2 = safePop(&stack)
                let arg1 = safePop(&stack)
                stack.append(.structAssignment(
                    ColoExpr.variable(source, arg1, .wrap),
                    ColoExpr.variable(dest, arg2, .wrap),
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
                // The function ID sits directly below the arguments. It is
                // usually a pushImmediate constant but can be any expression
                // (D4_tower_1F_2 computes it via a script call).
                let functionID = safePop(&stack)
                // Pop object reference (local var 0, always precedes builtin calls)
                if !stack.isEmpty {
                    _ = safePop(&stack)
                }
                stack.append(.callBuiltIn(functionID, args.reversed()))

            case .invalid:
                break
            }

            // At a basic-block boundary (next instruction is a jump target),
            // flush any pending statements so they belong to this block.
            // Terminators (return/jump/jumpFalse) already flushed above, so
            // their stack is empty here.
            let nextOffset = inst.offset + inst.opcode.length
            if jumpTargets.contains(nextOffset) {
                flushStatements(&stack, into: &expressions)
            }
        }

        flushStatements(&stack, into: &expressions)

        return (expressions, argCount)
    }

    // MARK: - Helpers

    private func safePop(_ stack: inout [ColoExpr]) -> ColoExpr {
        stack.isEmpty ? .constant(.void(0)) : stack.removeLast()
    }

    private func handlePushVar(_ v: ColoScriptVar, form: ColoVarPushForm, stack: inout [ColoExpr], argCount: inout Int) {
        let indexExpr = safePop(&stack)
        if v.isLocal {
            if case .constant(.integer(let idx)) = indexExpr {
                argCount = max(argCount, Int(idx) + 1)
            }
        }
        if v.isLiteral {
            stack.append(indexExpr)
        } else {
            stack.append(.variable(v, indexExpr, form))
        }
    }

    private func handleBinaryOp(_ op: ColoOperator, v1: ColoScriptVar, v2: ColoScriptVar, stack: inout [ColoExpr]) {
        let arg1 = safePop(&stack)  // RHS
        let arg2 = safePop(&stack)  // LHS
        // Legacy: operation(op, [variable(var1, arg1_rhs), variable(var2, arg2_lhs)])
        // Text rendering: exprs[1] op exprs[0] = var2(LHS) op var1(RHS)
        stack.append(.operation(op, [ColoExpr.variable(v1, arg1, .wrap), ColoExpr.variable(v2, arg2, .wrap)]))
    }

    private func flushStatements(_ stack: inout [ColoExpr], into expressions: inout [ColoExpr]) {
        // Statements were pushed in program order (stack bottom → top), so
        // emit them front-to-back. Using popLast() here would reverse a
        // multi-statement run — masked today only because jump-target
        // boundaries usually chunk flushes into single statements.
        expressions.append(contentsOf: stack)
        stack.removeAll(keepingCapacity: true)
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
    ///
    /// The location marker is *kept* in the output (it is zero-size and the
    /// formatter ignores it): the same offset can simultaneously be an
    /// if-statement end and another jump's target — most importantly the top
    /// of a `while` loop, which the while pass detects via the marker.
    private func compoundIfStatements(_ exprs: [ColoExpr]) -> [ColoExpr] {
        var result = [ColoExpr]()
        var i = 0
        while i < exprs.count {
            if case .jumpFalse(let condition, let target) = exprs[i] {
                var body = [ColoExpr]()
                i += 1
                while i < exprs.count {
                    if case .location(let loc) = exprs[i], loc == target {
                        break
                    }
                    body.append(exprs[i])
                    i += 1
                }
                let compoundedBody = compoundIfStatements(body)
                result.append(.ifStatement([(condition, compoundedBody)]))
                // Keep the end marker: `i` currently points at it (or past the
                // end), and the `i += 1` below advances over it after it is
                // appended by the fall-through on the next loop iteration.
                continue
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
                        // While loop detected. Keep the top-of-loop marker —
                        // other jumps may also target it.
                        let condition = branches[0].0
                        var body = Array(branches[0].1.dropLast()) // remove the back-jump
                        body = compoundWhileLoops(body) // recurse
                        result.append(exprs[i])
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
                        var thenBody = Array(lastBranch.1.dropLast())
                        thenBody = compoundElseStatements(thenBody)
                        elseBody = compoundElseStatements(elseBody)
                        branches[branches.count - 1] = (lastBranch.0, thenBody)
                        // Add else as a branch with "true" condition (always taken)
                        branches.append((.constant(.integer(1)), elseBody))
                        result.append(.ifStatement(branches))
                        // Keep the end-of-else location marker (processed on
                        // the next iteration) — other jumps may target it.
                        i = j
                        continue
                    }
                }
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
    /// Resolves a relocated string-pointer file offset to the actual string
    /// (e.g. `ColoScript.cString(at:)`); printf formats fall back to
    /// `string@<offset>` tokens when unresolved
    public let stringResolver: ((Int) -> String?)?
    /// Local-slot index of the first argument. 0 for void functions; 1 for
    /// value-returning functions, whose local 0 is the return slot.
    public var localArgBase: Int = 0
    /// Byte offsets targeted by unstructured (goto) jumps left over after
    /// compounding — locations at these offsets emit as labels
    public var gotoTargets: Set<Int> = []
    /// Output syntax flavor (block style, logical operators, bool literals)
    public var flavor: ColoScriptSourceHeader.Syntax = .swift

    public init(
        builtInFunctions: [Int: ScriptFunctionDef] = [:],
        enums: [String: Enum] = [:],
        indent: String = "    ",
        stringResolver: ((Int) -> String?)? = nil
    ) {
        self.builtInFunctions = builtInFunctions
        self.enums = enums
        self.indent = indent
        self.stringResolver = stringResolver
    }

    public func formatFunction(index: Int, name: String, argCount: Int, returnsValue: Bool = false, argTypes: [ColoValueType] = [], body: [ColoExpr]) -> String {
        let floatName = flavor == .python ? "float" : "Float"
        let args = (0..<argCount).map { i -> String in
            let type = i < argTypes.count ? argTypes[i] : .integer
            return type == .float ? "arg\(i): \(floatName)" : "arg\(i)"
        }.joined(separator: ", ")
        let returnSuffix = returnsValue ? (flavor == .python ? " -> int" : " -> Int") : ""

        // Every function's bytecode ends with an implicit terminating
        // `returnOp` (verified: all 2057 code runs in the US corpus end with
        // returnOp, or returnOp followed by exit). The terminator is dropped
        // from the text unconditionally and the compiler re-appends it, so an
        // explicit trailing `return` in source is always a *second*, explicit
        // return in the bytecode.
        var body = body
        if case .exit = body.last {
            if body.count >= 2, case .returnVoid = body[body.count - 2] {
                body.remove(at: body.count - 2)
            }
        } else if case .returnVoid = body.last {
            body.removeLast()
        }

        // Unstructured jumps that survived compounding become goto/label
        // pairs — dropping them would change control flow (GS emits early
        // exits to the shared return tail this way)
        var formatter = self
        formatter.gotoTargets = Self.leftoverJumpTargets(body)

        var lines: [String]
        if flavor == .python {
            lines = ["def \(name)(\(args))\(returnSuffix):"]
            let bodyLines = formatter.formatExprs(body, depth: 1)
            lines += bodyLines.isEmpty ? ["    pass"] : bodyLines
        } else {
            lines = ["func \(name)(\(args))\(returnSuffix) {"]
            lines += formatter.formatExprs(body, depth: 1)
            lines.append("}")
        }
        return lines.joined(separator: "\n")
    }

    /// Targets of `.jump` expressions remaining after compounding (recursive)
    private static func leftoverJumpTargets(_ body: [ColoExpr]) -> Set<Int> {
        var targets = Set<Int>()
        func walk(_ exprs: [ColoExpr]) {
            for expr in exprs {
                switch expr {
                case .jump(let target): targets.insert(target)
                case .ifStatement(let branches): branches.forEach { walk($0.1) }
                case .whileLoop(_, let loopBody): walk(loopBody)
                default: break
                }
            }
        }
        walk(body)
        return targets
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
            case .call(let funcID, _, let args):
                let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
                lines.append("\(prefix)function_\(funcID)(\(argStr))")
            case .callBuiltIn(let funcID, let args):
                lines.append("\(prefix)\(formatBuiltInCall(funcID, args: args))")
            case .printf(let fmt, let args):
                var line = "\(prefix)printf(\"\(resolveFormat(fmt))\""
                if !args.isEmpty {
                    line += ", " + args.map { formatExpr($0) }.joined(separator: ", ")
                }
                lines.append(line + ")")
            case .yield(let frames):
                lines.append("\(prefix)yield(\(formatExpr(frames)))")
            case .returnVoid:
                lines.append("\(prefix)return")
            case .returnResult(let value):
                lines.append("\(prefix)return \(formatExpr(value))")
            case .ifStatement(let branches):
                for (bi, branch) in branches.enumerated() {
                    if flavor == .python {
                        if bi == 0 {
                            lines.append("\(prefix)if \(formatExpr(branch.0)):")
                        } else if case .constant(.integer(1)) = branch.0 {
                            lines.append("\(prefix)else:")
                        } else {
                            lines.append("\(prefix)elif \(formatExpr(branch.0)):")
                        }
                        let branchLines = formatExprs(branch.1, depth: depth + 1)
                        lines += branchLines.isEmpty ? ["\(prefix)    pass"] : branchLines
                    } else {
                        if bi == 0 {
                            lines.append("\(prefix)if \(formatExpr(branch.0)) {")
                        } else if case .constant(.integer(1)) = branch.0 {
                            lines.append("\(prefix)} else {")
                        } else {
                            lines.append("\(prefix)} else if \(formatExpr(branch.0)) {")
                        }
                        lines += formatExprs(branch.1, depth: depth + 1)
                    }
                }
                if flavor == .swift { lines.append("\(prefix)}") }
            case .whileLoop(let condition, let body):
                if flavor == .python {
                    lines.append("\(prefix)while \(formatExpr(condition)):")
                    let bodyLines = formatExprs(body, depth: depth + 1)
                    lines += bodyLines.isEmpty ? ["\(prefix)    pass"] : bodyLines
                } else {
                    lines.append("\(prefix)while \(formatExpr(condition)) {")
                    lines += formatExprs(body, depth: depth + 1)
                    lines.append("\(prefix)}")
                }
            case .location(let target):
                if gotoTargets.contains(target) {
                    lines.append("\(prefix)L_\(String(format: "%04X", target)):")
                }
            case .jump(let target):
                lines.append("\(prefix)goto L_\(String(format: "%04X", target))")
            case .exit:
                lines.append("\(prefix)exit()")
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
        case .variable(let v, let indexExpr, let form):
            // Literal masks (including combined ones like 0xC2) render as
            // their inner expression — the mask lives on the consumer
            if v.isLiteral {
                return formatExpr(indexExpr)
            }
            // `&` marks the rare pushVar (single) read form; plain reads are
            // pushMultiVar. The distinction is not derivable from types.
            let sigil = form == .single ? "&" : ""
            if v.isGlobal {
                if case .constant(.integer(let idx)) = indexExpr {
                    return "\(sigil)gvar\(idx)"
                }
                // Computed index: raw arena subscript, accessor name spells
                // the access mask's primitive type
                let accessor: String
                switch v.valueType {
                case .float: accessor = "globalsF"
                case .void: accessor = "globalsO"
                default: accessor = "globals"
                }
                return "\(sigil)\(accessor)[\(formatExpr(indexExpr))]"
            } else if v.isLocal {
                if case .constant(.integer(let idx)) = indexExpr {
                    let argIndex = Int(idx) - localArgBase
                    return argIndex >= 0 ? "\(sigil)arg\(argIndex)" : "__returnSlot"
                }
                // Computed index: raw (unshifted) local-slot subscript
                return "\(sigil)locals[\(formatExpr(indexExpr))]"
            } else { // literal
                return formatExpr(indexExpr)
            }
        case .operation(let op, let operands):
            if operands.count == 1 {
                return "\(operatorSymbol(op))\(parenthesized(operands[0], asOperandOf: op, rightSide: false, unary: true))"
            } else if operands.count == 2 {
                // Legacy order: exprs[1] op exprs[0] = LHS op RHS
                let lhs = parenthesized(operands[1], asOperandOf: op, rightSide: false)
                let rhs = parenthesized(operands[0], asOperandOf: op, rightSide: true)
                return "\(lhs) \(operatorSymbol(op)) \(rhs)"
            }
            return "op(\(operands.map { formatExpr($0) }.joined(separator: ", ")))"
        case .call(let funcID, _, let args):
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "function_\(funcID)(\(argStr))"
        case .callBuiltIn(let funcID, let args):
            return formatBuiltInCall(funcID, args: args)
        case .yield(let frames):
            return "yield(\(formatExpr(frames)))"
        case .variableAssignment(let target, let value):
            return "\(formatExpr(target)) = \(formatExpr(value))"
        default:
            return "<?>"
        }
    }

    /// Flavor-aware operator spelling (`&&`/`and`, `||`/`or`, `!`/`not `)
    private func operatorSymbol(_ op: ColoOperator) -> String {
        guard flavor == .python else { return op.symbol }
        switch op {
        case .logicalAnd: return "and"
        case .logicalOr: return "or"
        case .not: return "not "
        default: return op.symbol
        }
    }

    /// The operator an expression renders as, looking through literal-mask
    /// wraps (which print as their inner expression) and inline assignments.
    private func renderedOperator(_ expr: ColoExpr) -> ColoOperator? {
        switch expr {
        case .operation(let op, _): return op
        case .variable(let v, let inner, _) where v.isLiteral: return renderedOperator(inner)
        default: return nil
        }
    }

    /// A pushed-value operand wrap whose inner expression is a bare variable
    /// read (the read was materialized on the stack rather than bound to the
    /// operator's operand mask)
    private func isPushedBareRead(_ expr: ColoExpr) -> Bool {
        if case .variable(let v, let inner, .wrap) = expr, v.isLiteral,
           case .variable(let innerVar, _, let form) = inner, !innerVar.isLiteral, form != .wrap {
            return true
        }
        return false
    }

    /// Whether an expression renders as an inline assignment (`a = b`),
    /// which always needs parentheses in operand position
    private func rendersAsAssignment(_ expr: ColoExpr) -> Bool {
        switch expr {
        case .variableAssignment: return true
        case .variable(let v, let inner, _) where v.isLiteral: return rendersAsAssignment(inner)
        default: return false
        }
    }

    /// Parenthesize an operand when required for an unambiguous reparse:
    /// lower-precedence sub-operations always; equal precedence on the right
    /// side of a left-associative operator; any operation under a unary.
    private func parenthesized(_ operand: ColoExpr, asOperandOf parent: ColoOperator, rightSide: Bool, unary: Bool = false) -> String {
        let text = formatExpr(operand)
        if rendersAsAssignment(operand) { return "(\(text))" }
        // A materialized (pushed) bare variable read in operand position is
        // parenthesized to distinguish it from the direct-mask form — parens
        // around a lone variable have no other meaning in the dialect
        if isPushedBareRead(operand) { return "(\(text))" }
        guard let childOperator = renderedOperator(operand) else { return text }
        if unary { return "(\(text))" }
        if childOperator.precedence < parent.precedence { return "(\(text))" }
        if childOperator.precedence == parent.precedence && rightSide { return "(\(text))" }
        return text
    }

    /// Resolve a builder `string@<offset>` printf token to the actual string
    /// when a resolver is available, escaping it for a quoted literal
    private func resolveFormat(_ token: String) -> String {
        guard token.hasPrefix("string@"),
              let offset = Int(token.dropFirst(7)),
              let resolved = stringResolver?(offset) else {
            return token
        }
        return resolved
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Format a built-in call. The function ID is usually a constant that
    /// resolves to a named definition; a computed ID renders as an indexed
    /// dynamic call.
    private func formatBuiltInCall(_ idExpr: ColoExpr, args: [ColoExpr]) -> String {
        if case .constant(.integer(let id)) = idExpr {
            let funcDef = builtInFunctions[Int(id)]
            let name = funcDef?.name ?? "builtin_\(id)"
            let argStr = formatCallArgs(args, paramDefs: funcDef?.parameters ?? [])
            return "\(name)(\(argStr))"
        }
        let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
        return "builtin[\(formatExpr(idExpr))](\(argStr))"
    }

    /// Format function call arguments, applying macro resolution based on parameter type definitions.
    /// A pushMultiVar with count > 1 duplicates one read across several
    /// argument slots — collapse the run into `dup(expr, n)`.
    private func formatCallArgs(_ args: [ColoExpr], paramDefs: [ScriptFunctionDef.ParameterDef]) -> String {
        var parts = [String]()
        var i = 0
        while i < args.count {
            if case .variable(_, _, .multi(let count)) = args[i], count > 1 {
                var repeats = 1
                while i + repeats < args.count, repeats < Int(count),
                      "\(args[i + repeats])" == "\(args[i])" {
                    repeats += 1
                }
                if repeats > 1 {
                    // One read filling several parameter slots, so there is no
                    // single parameter to name it after — a `dup` run stays
                    // bare in both dialects, and the parser accepts a bare
                    // argument anywhere for exactly this reason.
                    parts.append("dup(\(formatExpr(args[i])), \(repeats))")
                    i += repeats
                    continue
                }
            }
            let paramType = i < paramDefs.count ? paramDefs[i].type : nil
            let value = formatArgWithType(args[i], type: paramType)
            // Python spells each argument as a keyword argument — the
            // signatures carry real names (`sampleID`, `msgID`, `groupID`) and
            // a bare `getDNASampleSpecies(1)` says nothing about what the 1
            // is. Only where the signature names that position: past its
            // declared parameters there is no name to use, and an invented
            // one would be worse than none.
            if flavor == .python, i < paramDefs.count {
                parts.append("\(paramDefs[i].name)=\(value)")
            } else {
                parts.append(value)
            }
            i += 1
        }
        return parts.joined(separator: ", ")
    }

    /// Format a single argument, resolving to an enum case name if the parameter type is an enum ref
    private func formatArgWithType(_ expr: ColoExpr, type: ScriptParamType?) -> String {
        guard let type = type else { return formatExpr(expr) }

        switch type {
        case .bool:
            // Resolve bools — but only for actual 0/1 values (some "bool"
            // parameters receive other ints; those must survive verbatim)
            let boolText: (Int32) -> String = { value in
                if self.flavor == .python { return value != 0 ? "True" : "False" }
                return value != 0 ? "true" : "false"
            }
            if case .constant(.integer(let v)) = expr, v == 0 || v == 1 { return boolText(v) }
            if case .variable(let vr, .constant(.integer(let v)), _) = expr, vr.isLiteral, v == 0 || v == 1 { return boolText(v) }
        case .enumRef(let enumName):
            // Look up the enum and find a DEFINED case matching the raw value
            if let enumDef = enums[enumName] {
                let rawValue: Int?
                switch expr {
                case .constant(.integer(let v)): rawValue = Int(v)
                case .variable(let vr, .constant(.integer(let v)), _) where vr.isLiteral: rawValue = Int(v)
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
