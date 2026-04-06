import GoDFoundation

/// Converts a linear sequence of IR instructions into statements with expression trees
/// by simulating the stack-based execution model.
public struct StackDecompiler {

    public init() {}

    /// Decompile a function's IR instructions into statements
    public func decompile(_ function: IRFunction) -> [ScriptStatement] {
        var stack = [ScriptExpr]()
        var statements = [ScriptStatement]()

        // Collect jump targets for label insertion
        var jumpTargets = Set<Int>()
        for inst in function.instructions {
            if let target = inst.op.jumpTarget {
                jumpTargets.insert(target)
            }
        }

        for inst in function.instructions {
            // Insert label if this offset is a jump target
            if jumpTargets.contains(inst.offset) {
                statements.append(.label(offset: inst.offset))
            }

            switch inst.op {
            case .pushConstant(let c):
                stack.append(.constant(c))

            case .pushVariable(let v):
                if case .lastResult = v.storage {
                    stack.append(.lastResult)
                } else {
                    stack.append(.variable(v))
                }

            case .pop(let count):
                for _ in 0..<count {
                    if !stack.isEmpty { stack.removeLast() }
                }

            case .binaryOp(let op):
                let rhs = stack.popLast() ?? .constant(.void)
                let lhs = stack.popLast() ?? .constant(.void)
                stack.append(.binary(op, lhs, rhs))

            case .unaryOp(let op):
                let operand = stack.popLast() ?? .constant(.void)
                stack.append(.unary(op, operand))

            case .assign(let target, _):
                let value = stack.popLast() ?? .constant(.void)
                statements.append(.assign(target: target, value: value))

            case .copyMemory(let dest, let source, let length):
                statements.append(.copyMemory(dest: dest, source: source, length: length))

            case .callScript(let funcIndex, let argCount, let returnCount):
                let args = popArgs(&stack, count: argCount)
                let expr = ScriptExpr.callScript(functionIndex: funcIndex, args: args, name: nil)
                if returnCount > 0 {
                    stack.append(expr)
                } else {
                    statements.append(.expression(expr))
                }

            case .callBuiltIn(let funcID, let argCount, let returnCount):
                // The function ID is usually pushed as an immediate before callStandard
                // Pop it from the stack args
                var args = popArgs(&stack, count: argCount)
                let actualFuncID: Int
                if let first = args.first, case .constant(.integer(let id)) = first {
                    actualFuncID = Int(id)
                    args = Array(args.dropFirst())
                } else {
                    actualFuncID = funcID
                }
                let expr = ScriptExpr.callBuiltIn(functionID: actualFuncID, args: args, name: nil)
                if returnCount > 0 {
                    stack.append(expr)
                } else {
                    statements.append(.expression(expr))
                }

            case .returnVoid:
                statements.append(.returnVoid)

            case .returnValue:
                let value = stack.popLast() ?? .constant(.void)
                statements.append(.returnValue(value))

            case .yield(let frames):
                statements.append(.yield(frames: frames))

            case .printf(let argCount):
                let args = popArgs(&stack, count: argCount)
                statements.append(.expression(.printf(args: args)))

            case .jump(let target):
                statements.append(.jump(target: target))

            case .jumpIfFalse(let target):
                let condition = stack.popLast() ?? .constant(.void)
                statements.append(.jumpIfFalse(condition: condition, target: target))

            case .jumpIfTrue(let target):
                let condition = stack.popLast() ?? .constant(.void)
                statements.append(.jumpIfTrue(condition: condition, target: target))

            case .nop:
                break

            case .exit:
                statements.append(.exit)
            }
        }

        return statements
    }

    private func popArgs(_ stack: inout [ScriptExpr], count: Int) -> [ScriptExpr] {
        var args = [ScriptExpr]()
        for _ in 0..<count {
            args.append(stack.popLast() ?? .constant(.void))
        }
        return args.reversed()  // args are pushed left-to-right, popped right-to-left
    }
}
