import GoDFoundation

/// Lowers a flat (uncompounded) ColoExpr statement list back to instructions,
/// mirroring the Genius Sonority compiler's code-generation conventions.
/// Inverse of `ColoExpressionBuilder.buildExpressions`.
///
/// Canonical conventions (measured across the full Colosseum US script corpus):
/// - Variable reads emit `pushImmediate(index)` + `pushMultiVar(mask, count: 1)`.
/// - Binary/unary operator and `setVar` operand masks are carried by the
///   consumer instruction; literal-mask wraps push only their inner value.
/// - Every statement's leftover value is discarded with a `pop` whose mask is
///   `0x80 | typeID` — `(0x81, count: 0)` for void, `(0x82, 1)` int,
///   `(0x83, 1)` float.
/// - Built-in calls push an object reference (`pushImmediate(0)` +
///   `pushMultiVar(0x42, 1)`), then the function ID immediate, then arguments,
///   then `callStandard(returnCount: 1, argCount: argumentCount + 1)`.
/// - `return value` compiles to `pushImmediate(0)`, the value, a `setVar`
///   targeting local 0 (`0x42`), a pop, then `returnOp`.
/// - `-1` constants use `pushImmediate` (the dedicated `pushMinus1` opcode is
///   unused by the original compiler).
public struct ColoExprLowering {

    /// Input the lowering can't turn into bytecode. The parser rejects
    /// source that would produce any of these, so seeing one means an
    /// expression list built some other way; it is reported rather than
    /// trapping (which would take an MCP server down) or emitting a jump to
    /// offset 0.
    public enum LoweringError: Error, CustomStringConvertible {
        case undefinedLabel(Int)
        case unexpected(String)

        public var description: String {
            switch self {
            case .undefinedLabel(let label):
                return "script lowering: jump to label \(label), which nothing declares"
            case .unexpected(let what):
                return "script lowering: unexpected \(what)"
            }
        }
    }

    public init() {}

    /// Lower a flat expression list to instructions with absolute offsets
    /// starting at `startOffset`.
    ///
    /// Jump targets may be either absolute byte offsets (as produced by the
    /// expression builder) or symbolic labels — negative integers paired with
    /// matching `.location(label)` markers (as produced by
    /// `ColoExprUncompound`). Labels are resolved to byte offsets after layout.
    public func lower(_ expressions: [ColoExpr], startOffset: Int) throws -> [ColoScriptInstruction] {
        var opcodes = [ColoScriptOpcode]()
        var labelIndex = [Int: Int]()  // symbolic label → opcode index

        for expression in expressions {
            if case .location(let label) = expression {
                if label < 0 { labelIndex[label] = opcodes.count }
                continue
            }
            try lowerStatement(expression, into: &opcodes)
        }

        var instructions = [ColoScriptInstruction]()
        var byteOffsets = [Int]()
        var offset = startOffset
        for opcode in opcodes {
            byteOffsets.append(offset)
            instructions.append(ColoScriptInstruction(offset: offset, opcode: opcode))
            offset += opcode.length
        }
        byteOffsets.append(offset)  // one past the end, for labels at the tail

        // Fixup: resolve symbolic labels (encoded as sign-extended UInt32s)
        for (index, instruction) in instructions.enumerated() {
            let resolve: (UInt32) throws -> UInt32? = { raw in
                let value = Int(Int32(bitPattern: raw))
                guard value < 0 else { return nil }
                guard let opcodeIndex = labelIndex[value] else {
                    throw LoweringError.undefinedLabel(value)
                }
                return UInt32(byteOffsets[opcodeIndex])
            }
            switch instruction.opcode {
            case .jump(let target):
                if let resolved = try resolve(target) {
                    instructions[index] = ColoScriptInstruction(
                        offset: instruction.offset, opcode: .jump(offset: resolved))
                }
            case .jumpFalse(let target):
                if let resolved = try resolve(target) {
                    instructions[index] = ColoScriptInstruction(
                        offset: instruction.offset, opcode: .jumpFalse(offset: resolved))
                }
            default:
                break
            }
        }
        return instructions
    }

    // MARK: - Statements

    private func lowerStatement(_ expression: ColoExpr, into out: inout [ColoScriptOpcode]) throws {
        switch expression {
        case .variableAssignment(let target, let value):
            try lowerAssignment(target: target, value: value, into: &out)
            // The statement pop's mask follows the assignment *target* type
            if case .variable(let targetVar, _, _) = target {
                appendPop(for: targetVar.valueType, into: &out)
            } else {
                appendPop(for: .integer, into: &out)
            }

        case .structAssignment(let source, let dest, let length):
            // copyStruct: builder pops arg2 (dest index) last-pushed, arg1 first
            if case .variable(let sourceVar, let sourceIndex, _) = source,
               case .variable(let destVar, let destIndex, _) = dest {
                try lowerValue(sourceIndex, into: &out)
                try lowerValue(destIndex, into: &out)
                out.append(.copyStruct(source: sourceVar, dest: destVar, length: UInt16(length)))
            }

        case .call(let functionID, let returnCount, let args):
            try lowerCall(functionID: functionID, returnCount: returnCount, args: args, into: &out)
            appendPop(for: returnCount == 0 ? .void : .integer, into: &out)

        case .callBuiltIn:
            try lowerValue(expression, into: &out)
            appendPop(for: .integer, into: &out)

        case .printf(let format, let args):
            out.append(.pushImmediate(type: .integer, value: stringOffset(from: format)))
            for arg in args { try lowerValue(arg, into: &out) }
            out.append(.printf(unused: 0, argCount: UInt16(args.count + 1)))
            appendPop(for: .void, into: &out)

        case .yield(let frames):
            try lowerValue(frames, into: &out)
            out.append(.yield(unused: 0, argCount: 1))
            appendPop(for: .void, into: &out)

        case .returnVoid:
            out.append(.returnOp)

        case .returnResult(let value):
            // `return v` = `local0 = v; pop; returnOp`
            out.append(.pushImmediate(type: .integer, value: 0))
            let sourceVar: ColoScriptVar
            if case .variable(let source, let inner, _) = value {
                sourceVar = source
                try lowerValue(inner, into: &out)
            } else {
                sourceVar = literalVar(.integer)
                try lowerValue(value, into: &out)
            }
            let target = ColoScriptVar(valueType: .integer, isLocal: true, isLiteral: false,
                                       isPointer: false, flag0x20: false)
            out.append(.setVar(source: sourceVar, target: target))
            appendPop(for: sourceVar.valueType, into: &out)
            out.append(.returnOp)

        case .jump(let target):
            out.append(.jump(offset: UInt32(bitPattern: Int32(target))))

        case .jumpFalse(let condition, let target):
            try lowerValue(condition, into: &out)
            out.append(.jumpFalse(offset: UInt32(bitPattern: Int32(target))))

        case .location:
            break  // position marker only — validated by the round-trip diff

        case .exit:
            out.append(.exit)

        case .nop:
            out.append(.nop)

        case .ifStatement, .whileLoop:
            throw LoweringError.unexpected("an if or while statement that wasn't flattened first")

        default:
            // Leftover stack value flushed as a bare statement: pushes only
            try lowerValue(expression, into: &out)
        }
    }

    private func lowerAssignment(target: ColoExpr, value: ColoExpr, into out: inout [ColoScriptOpcode]) throws {
        guard case .variable(let targetVar, let targetIndex, _) = target,
              case .variable(let sourceVar, let sourceValue, _) = value else {
            // Malformed assignment — lower operands as plain values
            try lowerValue(target, into: &out)
            try lowerValue(value, into: &out)
            return
        }
        try lowerValue(targetIndex, into: &out)
        try lowerValue(sourceValue, into: &out)
        out.append(.setVar(source: sourceVar, target: targetVar))
    }

    // MARK: - Values

    private func lowerValue(_ expression: ColoExpr, into out: inout [ColoScriptOpcode]) throws {
        switch expression {
        case .constant(let constant):
            out.append(pushConstant(constant))

        case .variable(let variable, let index, let form):
            if variable.isLiteral {
                // Literal wraps carry no push of their own
                try lowerValue(index, into: &out)
            } else {
                try lowerValue(index, into: &out)
                switch form {
                case .single: out.append(.pushVar(var1: variable))
                case .single2: out.append(.pushVar2(var1: variable))
                case .multi(let count): out.append(.pushMultiVar(var1: variable, count: count))
                case .wrap: out.append(.pushMultiVar(var1: variable, count: 1))
                }
            }

        case .operation(let op, let operands):
            try lowerOperation(op, operands: operands, into: &out)

        case .call(let functionID, let returnCount, let args):
            try lowerCall(functionID: functionID, returnCount: returnCount, args: args, into: &out)

        case .callBuiltIn(let functionID, let args):
            // Object reference (local 0), function ID, then arguments
            out.append(.pushImmediate(type: .integer, value: 0))
            out.append(.pushMultiVar(var1: localIntVar, count: 1))
            try lowerValue(functionID, into: &out)
            try lowerValues(args, into: &out)
            out.append(.callStandard(returnCount: 1, argCount: UInt16(args.count + 1)))

        case .variableAssignment(let target, let value):
            // Assignment used as a value (e.g. pending return value)
            try lowerAssignment(target: target, value: value, into: &out)

        case .yield(let frames):
            try lowerValue(frames, into: &out)
            out.append(.yield(unused: 0, argCount: 1))

        default:
            throw LoweringError.unexpected("\(expression) where a value was expected")
        }
    }

    /// Script-internal call: a value-returning call is preceded by a
    /// return-slot push (`local0`) below its arguments.
    private func lowerCall(functionID: Int, returnCount: Int, args: [ColoExpr], into out: inout [ColoScriptOpcode]) throws {
        if returnCount == 1 {
            out.append(.pushImmediate(type: .integer, value: 0))
            out.append(.pushMultiVar(var1: localIntVar, count: 1))
        }
        try lowerValues(args, into: &out)
        out.append(.call(functionID: UInt32(functionID),
                         returnCount: UInt16(returnCount),
                         argCount: UInt16(args.count)))
    }

    /// Lower a sequence of values. A `pushMultiVar` with count > 1 pushes one
    /// resolved variable `count` times — the builder models that as `count`
    /// identical expressions, so collapse adjacent repeats back into the
    /// single multi-push.
    private func lowerValues(_ expressions: [ColoExpr], into out: inout [ColoScriptOpcode]) throws {
        var index = 0
        while index < expressions.count {
            let expression = expressions[index]
            if case .variable(_, _, .multi(let count)) = expression, count > 1 {
                var repeats = 1
                while index + repeats < expressions.count,
                      repeats < Int(count),
                      isSameExpression(expressions[index + repeats], expression) {
                    repeats += 1
                }
                try lowerValue(expression, into: &out)  // emits pushMultiVar(count)
                index += repeats
            } else {
                try lowerValue(expression, into: &out)
                index += 1
            }
        }
    }

    private func isSameExpression(_ lhs: ColoExpr, _ rhs: ColoExpr) -> Bool {
        // Structural comparison via the debug description — duplicates from a
        // multi-push are copies of the same value, so this is exact enough.
        String(describing: lhs) == String(describing: rhs)
    }

    private func lowerOperation(_ op: ColoOperator, operands: [ColoExpr], into out: inout [ColoScriptOpcode]) throws {
        if operands.count == 1, case .variable(let variable, let inner, _) = operands[0] {
            try lowerValue(inner, into: &out)
            switch op {
            case .not: out.append(.not(var1: variable))
            case .negate: out.append(.negate(var1: variable))
            default: throw LoweringError.unexpected("operator \(op) with one operand")
            }
            return
        }

        guard operands.count == 2,
              case .variable(let rhsVar, let rhsInner, _) = operands[0],
              case .variable(let lhsVar, let lhsInner, _) = operands[1] else {
            throw LoweringError.unexpected("operator \(op) without two typed operands")
        }

        // Push order: LHS first, RHS on top (builder pops RHS first)
        try lowerValue(lhsInner, into: &out)
        try lowerValue(rhsInner, into: &out)

        switch op {
        case .and: out.append(.bitwiseAnd(var1: rhsVar, var2: lhsVar))
        case .or: out.append(.bitwiseOr(var1: rhsVar, var2: lhsVar))
        case .multiply: out.append(.multiply(var1: rhsVar, var2: lhsVar))
        case .divide: out.append(.divide(var1: rhsVar, var2: lhsVar))
        case .mod: out.append(.mod(var1: rhsVar, var2: lhsVar))
        case .add: out.append(.add(var1: rhsVar, var2: lhsVar))
        case .subtract: out.append(.subtract(var1: rhsVar, var2: lhsVar))
        case .lessThan: out.append(.lessThan(var1: rhsVar, var2: lhsVar))
        case .lessThanEqual: out.append(.lessThanEqual(var1: rhsVar, var2: lhsVar))
        case .greaterThan: out.append(.greaterThan(var1: rhsVar, var2: lhsVar))
        case .greaterThanEqual: out.append(.greaterThanEqual(var1: rhsVar, var2: lhsVar))
        case .equal: out.append(.equal(var1: rhsVar, var2: lhsVar))
        case .notEqual: out.append(.notEqual(var1: rhsVar, var2: lhsVar))
        case .logicalAnd: out.append(.logicalAnd(var1: rhsVar, var2: lhsVar))
        case .logicalOr: out.append(.logicalOr(var1: rhsVar, var2: lhsVar))
        case .not, .negate:
            throw LoweringError.unexpected("operator \(op) with two operands")
        }
    }

    // MARK: - Helpers

    private func pushConstant(_ constant: ColoConstant) -> ColoScriptOpcode {
        switch constant {
        case .integer(let value):
            return .pushImmediate(type: .integer, value: UInt32(bitPattern: value))
        case .float(let value):
            return .pushImmediate(type: .float, value: value.bitPattern)
        case .void(let value):
            return .pushImmediate(type: .void, value: UInt32(truncatingIfNeeded: value))
        case .unknown(let typeID, let value):
            return .pushImmediate(type: .unknown(id: typeID), value: UInt32(truncatingIfNeeded: value))
        }
    }

    /// Statement-result pop: mask `0x80 | typeID`, count 0 for void else 1.
    /// Void pops use type ID 1 in the original compiler's output.
    private func appendPop(for type: ColoValueType, into out: inout [ColoScriptOpcode]) {
        let popType: ColoValueType = type == .void ? .unknown(id: 1) : type
        let variable = literalVar(popType)
        out.append(.pop(unused: variable, count: type == .void ? 0 : 1))
    }

    private func literalVar(_ type: ColoValueType) -> ColoScriptVar {
        ColoScriptVar(valueType: type, isLocal: false, isLiteral: true,
                      isPointer: false, flag0x20: false)
    }

    private var localIntVar: ColoScriptVar {
        ColoScriptVar(valueType: .integer, isLocal: true, isLiteral: false,
                      isPointer: false, flag0x20: false)
    }

    /// Parse the builder's "string@<offset>" printf format token back to its offset
    private func stringOffset(from format: String) -> UInt32 {
        guard format.hasPrefix("string@"), let value = UInt32(format.dropFirst(7)) else {
            return 0
        }
        return value
    }
}
