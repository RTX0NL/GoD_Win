import GoDFoundation
import ScriptDecompiler
import Structs

// MARK: - XD Expression Type

/// XD-specific expression tree
public indirect enum XDExpr {
    case constant(XDConstantValue)
    case variable(XDVarRef)
    case lastResult
    case operation(XDScriptOperator, [XDExpr])
    case call(Int, [XDExpr], String?)                   // script function call
    case callStandard(Int, Int, [XDExpr])                // classID, methodID, args
    case variableAssignment(XDExpr, XDExpr)
    case yield(XDExpr)
    case returnVoid
    case returnResult(XDExpr)
    case jumpFalse(XDExpr, Int)
    case jumpTrue(XDExpr, Int)
    case jump(Int)
    case location(Int)
    case ifStatement([(XDExpr, [XDExpr])])
    case whileLoop(XDExpr, [XDExpr])
    case exit
    case nop
    case setLine(Int)
}

/// XD constant value
public enum XDConstantValue: Equatable {
    case void
    case integer(Int32)
    case float(Float)
    case string(Int, String?)     // index, resolved string
    case vector(Int)              // index into VECT section
    case object(Int32)
    case array(Int)
    case text(Int32)              // message ID
    case character(Int32)
    case pokemonIndex(Int32)
    case codePointer(Int32)
    case unknown(type: Int, value: UInt32)

    public var text: String {
        switch self {
        case .void: return "null"
        case .integer(let v): return abs(v) < 0x100 ? "\(v)" : "0x\(String(UInt32(bitPattern: v), radix: 16, uppercase: true))"
        case .float(let v): return "\(v)"
        case .string(_, let s): return "\"\(s ?? "???")\""
        case .vector(let i): return "vector(\(i))"
        case .object(let v): return "object(\(v))"
        case .array(let i): return "array(\(i))"
        case .text(let v): return "msg(\(v))"
        case .character(let v): return "character(\(v))"
        case .pokemonIndex(let v): return "pokemon(\(v))"
        case .codePointer(let v): return "code(\(v))"
        case .unknown(let t, let v): return "type\(t)(0x\(String(v, radix: 16)))"
        }
    }
}

/// XD variable reference
public struct XDVarRef: Equatable {
    public let level: Int
    public let index: Int16

    /// Level 0 = global, 1 = stack/local, 2 = last result, 3+ = object
    public var isGlobal: Bool { level == 0 }
    public var isLocal: Bool { level == 1 }
    public var isLastResult: Bool { level == 2 }
    public var isObject: Bool { level >= 3 }

    public var text: String {
        if isGlobal { return "gvar\(index)" }
        if isLocal { return index >= 0 ? "arg\(index)" : "local\(abs(index))" }
        if isLastResult { return "result" }
        // Object references
        let param = Int(index)
        if param == 0x80 { return "player" }
        if param > 0x80 && param <= 0x120 { return "character\(param - 0x80)" }
        if param >= 0x200 && param < 0x300 { return "array\(param - 0x200)" }
        return "class\(param)"
    }
}

// MARK: - Expression Builder

public struct XDExpressionBuilder {

    public init() {}

    public func buildExpressions(
        instructions: [XDScriptInstruction],
        script: XDScript
    ) -> (expressions: [XDExpr], argCount: Int) {
        var stack = [XDExpr]()
        var expressions = [XDExpr]()
        var argCount = 0

        var jumpTargets = Set<Int>()
        for inst in instructions {
            if let target = inst.jumpTarget {
                jumpTargets.insert(target)
            }
        }

        var i = 0
        while i < instructions.count {
            let inst = instructions[i]

            if jumpTargets.contains(inst.codeOffset) {
                flushStatements(&stack, into: &expressions)
                expressions.append(.location(inst.codeOffset))
            }

            switch inst.opcodeID {
            case .nop:
                break

            case .exit:
                expressions.append(.exit)

            case .setLine:
                break // debug info, ignore

            case .xdOperator:
                guard let op = XDScriptOperator(rawValue: inst.subOpCode) else { break }
                if op.isUnary {
                    let operand = safePop(&stack)
                    stack.append(.operation(op, [operand]))
                } else {
                    let rhs = safePop(&stack)
                    let lhs = safePop(&stack)
                    stack.append(.operation(op, [lhs, rhs]))
                }

            case .loadImmediate:
                let constType = XDConstantType(rawValue: inst.subOpCode)
                let value = inst.constantValue ?? 0
                let constant: XDConstantValue
                switch constType {
                case .void: constant = .void
                case .integer: constant = .integer(Int32(bitPattern: value))
                case .float: constant = .float(Float(bitPattern: value))
                case .string:
                    let idx = Int(inst.parameter)
                    let str = idx < script.strings.count ? script.strings[idx] : nil
                    constant = .string(idx, str)
                case .vector: constant = .vector(Int(inst.parameter))
                case .matrix: constant = .unknown(type: 5, value: value)
                case .object: constant = .object(Int32(bitPattern: value))
                case .array: constant = .array(Int(value))
                case .text: constant = .text(Int32(bitPattern: value))
                case .character: constant = .character(Int32(bitPattern: value))
                case .pokemonIndex: constant = .pokemonIndex(Int32(bitPattern: value))
                case .codePointer: constant = .codePointer(Int32(bitPattern: value))
                case .none: constant = .unknown(type: inst.subOpCode, value: value)
                }
                stack.append(.constant(constant))

            case .loadVariable, .loadNonCopyableVariable:
                let varRef = XDVarRef(level: inst.level, index: inst.parameter)
                if varRef.isLastResult {
                    stack.append(.lastResult)
                } else {
                    stack.append(.variable(varRef))
                    if varRef.isLocal && inst.parameter >= 0 {
                        argCount = max(argCount, Int(inst.parameter) + 1)
                    }
                }

            case .setVariable:
                let varRef = XDVarRef(level: inst.level, index: inst.parameter)
                let value = safePop(&stack)
                stack.append(.variableAssignment(.variable(varRef), value))

            case .setVector:
                // upper nibble = dimension (0=x, 1=y, 2=z), lower = level
                break // TODO: vector component assignment

            case .pop:
                // Automatically consumed by call/callStandard lookahead — skip
                break

            case .call:
                let funcAddr = inst.longParameter
                let funcEntry = script.functions.first(where: { $0.codeOffset == funcAddr })

                // Look ahead to next instruction: if it's pop, subOpCode = arg count
                let paramCount = lookAheadPopCount(instructions: instructions, afterIndex: i)

                var params = [XDExpr]()
                for _ in 0..<paramCount {
                    params.append(safePop(&stack))
                }
                params.reverse()
                stack.append(.call(funcAddr, params, funcEntry?.name))

                // Skip the pop instruction we consumed
                if paramCount > 0 { i += 1 }

            case .returnOp:
                // Check if top of stack is an assignment to arg0
                if let top = stack.last,
                   case .variableAssignment(.variable(let v), let value) = top,
                   v.isLocal && v.index == 0 {
                    stack.removeLast()
                    expressions.append(.returnResult(value))
                } else {
                    flushStatements(&stack, into: &expressions)
                    expressions.append(.returnVoid)
                }

            case .callStandard:
                let classID = inst.subOpCode
                let methodID = Int(inst.parameter)

                // Look ahead to next instruction: if it's pop, subOpCode = arg count
                let paramCount = lookAheadPopCount(instructions: instructions, afterIndex: i)

                var params = [XDExpr]()
                for _ in 0..<paramCount {
                    params.append(safePop(&stack))
                }
                params.reverse()
                stack.append(.callStandard(classID, methodID, params))

                // Skip the pop instruction we consumed
                if paramCount > 0 { i += 1 }

            case .jump:
                flushStatements(&stack, into: &expressions)
                expressions.append(.jump(inst.longParameter))

            case .jumpIfFalse:
                let condition = safePop(&stack)
                flushStatements(&stack, into: &expressions)
                expressions.append(.jumpFalse(condition, inst.longParameter))

            case .jumpIfTrue:
                let condition = safePop(&stack)
                flushStatements(&stack, into: &expressions)
                expressions.append(.jumpTrue(condition, inst.longParameter))

            case .reserve, .release:
                break // stack frame management, ignore for decompilation
            }

            i += 1
        }

        flushStatements(&stack, into: &expressions)
        return (expressions, argCount)
    }

    private func safePop(_ stack: inout [XDExpr]) -> XDExpr {
        stack.isEmpty ? .constant(.void) : stack.removeLast()
    }

    /// Look at the instruction after index i — if it's a pop, return its subOpCode (arg count)
    private func lookAheadPopCount(instructions: [XDScriptInstruction], afterIndex i: Int) -> Int {
        let nextIdx = i + 1
        guard nextIdx < instructions.count else { return 0 }
        let next = instructions[nextIdx]
        guard next.opcodeID == .pop else { return 0 }
        // Clamp: a malformed/negative decoded count would otherwise form
        // an invalid range (`0..<negative`) in the pop loops and trap.
        return max(0, next.subOpCode)
    }

    private func flushStatements(_ stack: inout [XDExpr], into expressions: inout [XDExpr]) {
        // Move statement-like expressions from stack to expression list
        while let expr = stack.popLast() {
            expressions.append(expr)
        }
    }
}

// MARK: - Compounding (reuse Colosseum pattern)

public struct XDExpressionCompound {

    public init() {}

    public func compound(_ expressions: [XDExpr]) -> [XDExpr] {
        var result = expressions
        result = compoundIfStatements(result)
        result = compoundWhileLoops(result)
        result = compoundElseStatements(result)
        return result
    }

    private func compoundIfStatements(_ exprs: [XDExpr]) -> [XDExpr] {
        var result = [XDExpr]()
        var i = 0
        while i < exprs.count {
            if case .jumpFalse(let condition, let target) = exprs[i] {
                var body = [XDExpr]()
                i += 1
                while i < exprs.count {
                    if case .location(let loc) = exprs[i], loc == target { break }
                    body.append(exprs[i])
                    i += 1
                }
                let compoundedBody = compoundIfStatements(body)
                result.append(.ifStatement([(condition, compoundedBody)]))
            } else {
                result.append(exprs[i])
            }
            i += 1
        }
        return result
    }

    private func compoundWhileLoops(_ exprs: [XDExpr]) -> [XDExpr] {
        var result = [XDExpr]()
        var i = 0
        while i < exprs.count {
            if case .location(let locOffset) = exprs[i] {
                if i + 1 < exprs.count, case .ifStatement(let branches) = exprs[i + 1] {
                    if let lastInBody = branches.first?.1.last, case .jump(let jumpTarget) = lastInBody, jumpTarget == locOffset {
                        let condition = branches[0].0
                        var body = Array(branches[0].1.dropLast())
                        body = compoundWhileLoops(body)
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

    private func compoundElseStatements(_ exprs: [XDExpr]) -> [XDExpr] {
        var result = [XDExpr]()
        var i = 0
        while i < exprs.count {
            if case .ifStatement(var branches) = exprs[i] {
                if let lastBranch = branches.last,
                   let lastInBody = lastBranch.1.last,
                   case .jump(let jumpTarget) = lastInBody {
                    var elseBody = [XDExpr]()
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
                        branches.append((.constant(.integer(1)), elseBody))
                        result.append(.ifStatement(branches))
                        i = j + 1
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

// MARK: - Formatter

public struct XDExprFormatter {

    public let classNames: [Int: String]
    public let methodNames: [Int: [Int: String]]  // classID → methodID → name
    public let enums: [String: Enum]
    public let indent: String

    public init(
        classNames: [Int: String] = [:],
        methodNames: [Int: [Int: String]] = [:],
        enums: [String: Enum] = [:],
        indent: String = "    "
    ) {
        self.classNames = classNames
        self.methodNames = methodNames
        self.enums = enums
        self.indent = indent
    }

    public func formatFunction(name: String, argCount: Int, body: [XDExpr]) -> String {
        let args = (0..<argCount).map { "arg\($0)" }.joined(separator: ", ")
        var lines = ["func \(name)(\(args)) {"]
        lines += formatExprs(body, depth: 1)
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    public func formatExprs(_ exprs: [XDExpr], depth: Int) -> [String] {
        let prefix = String(repeating: indent, count: depth)
        var lines = [String]()

        for expr in exprs {
            switch expr {
            case .variableAssignment(let target, let value):
                lines.append("\(prefix)\(formatExpr(target)) = \(formatExpr(value))")
            case .call(_, let args, let name):
                let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
                lines.append("\(prefix)\(name ?? "function")(\(argStr))")
            case .callStandard(let classID, let methodID, let args):
                let className = classNames[classID] ?? "Class\(classID)"
                let methodName = methodNames[classID]?[methodID] ?? "method\(methodID)"
                let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
                lines.append("\(prefix)\(className).\(methodName)(\(argStr))")
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
            case .exit, .nop, .location, .jump, .setLine:
                break
            default:
                let text = formatExpr(expr)
                if !text.isEmpty { lines.append("\(prefix)\(text)") }
            }
        }

        return lines
    }

    public func formatExpr(_ expr: XDExpr) -> String {
        switch expr {
        case .constant(let c):
            return c.text
        case .variable(let v):
            return v.text
        case .lastResult:
            return "result"
        case .operation(let op, let operands):
            if op.isUnary && operands.count == 1 {
                return "\(op.symbol)(\(formatExpr(operands[0])))"
            } else if operands.count == 2 {
                return "(\(formatExpr(operands[0])) \(op.symbol) \(formatExpr(operands[1])))"
            }
            return "op(\(operands.map { formatExpr($0) }.joined(separator: ", ")))"
        case .call(_, let args, let name):
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "\(name ?? "function")(\(argStr))"
        case .callStandard(let classID, let methodID, let args):
            let className = classNames[classID] ?? "Class\(classID)"
            let methodName = methodNames[classID]?[methodID] ?? "method\(methodID)"
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "\(className).\(methodName)(\(argStr))"
        case .variableAssignment(let target, let value):
            return "\(formatExpr(target)) = \(formatExpr(value))"
        default:
            return ""
        }
    }
}
