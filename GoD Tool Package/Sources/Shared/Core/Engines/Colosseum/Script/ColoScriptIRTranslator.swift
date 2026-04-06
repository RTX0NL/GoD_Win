import GoDFoundation
import ScriptDecompiler

/// Translates a parsed ColoScript into the game-agnostic IR representation
public struct ColoScriptIRTranslator {

    public init() {}

    /// Translate a complete ColoScript to IR
    public func translate(_ script: ColoScript) -> IRScript {
        let functions = script.functions.enumerated().map { (index, instructions) in
            translateFunction(index: index, instructions: instructions)
        }
        return IRScript(functions: functions)
    }

    /// Translate a single function's instructions to IR
    public func translateFunction(index: Int, instructions: [ColoScriptInstruction]) -> IRFunction {
        let irInstructions = instructions.flatMap { translateInstruction($0) }
        let argCount = inferArgCount(instructions)
        return IRFunction(
            index: index,
            argCount: argCount,
            instructions: irInstructions,
            name: nil
        )
    }

    // MARK: - Instruction Translation

    private func translateInstruction(_ inst: ColoScriptInstruction) -> [IRInstruction] {
        let offset = inst.offset

        switch inst.opcode {
        case .nop:
            return [IRInstruction(offset: offset, op: .nop)]

        case .exit:
            return [IRInstruction(offset: offset, op: .exit)]

        case .pushMinus1:
            return [IRInstruction(offset: offset, op: .pushConstant(.integer(-1)))]

        case .pop(_, let count):
            return [IRInstruction(offset: offset, op: .pop(count: Int(count)))]

        case .call(let funcID, let retCount, let argCount):
            return [IRInstruction(offset: offset, op: .callScript(
                functionIndex: Int(funcID),
                argCount: Int(argCount),
                returnCount: Int(retCount)
            ))]

        case .returnOp:
            return [IRInstruction(offset: offset, op: .returnVoid)]

        case .jump(let target):
            return [IRInstruction(offset: offset, op: .jump(target: Int(target)))]

        case .jumpFalse(let target):
            return [IRInstruction(offset: offset, op: .jumpIfFalse(target: Int(target)))]

        case .pushImmediate(let type, let value):
            let constant: IRConstant
            switch type {
            case .integer:
                constant = .integer(Int32(bitPattern: value))
            case .float:
                constant = .float(Float(bitPattern: value))
            case .void:
                constant = .void
            case .unknown(let id):
                constant = .unknown(type: id, rawValue: value)
            }
            return [IRInstruction(offset: offset, op: .pushConstant(constant))]

        case .pushVar(let v), .pushVar2(let v):
            return [IRInstruction(offset: offset, op: .pushVariable(translateVar(v)))]

        case .pushMultiVar(let v, let count):
            // Push the same variable N times
            return (0..<Int(count)).map { _ in
                IRInstruction(offset: offset, op: .pushVariable(translateVar(v)))
            }

        case .bitwiseAnd:
            return [IRInstruction(offset: offset, op: .binaryOp(.bitwiseAnd))]
        case .bitwiseOr:
            return [IRInstruction(offset: offset, op: .binaryOp(.bitwiseOr))]
        case .logicalAnd:
            return [IRInstruction(offset: offset, op: .binaryOp(.logicalAnd))]
        case .logicalOr:
            return [IRInstruction(offset: offset, op: .binaryOp(.logicalOr))]
        case .add:
            return [IRInstruction(offset: offset, op: .binaryOp(.add))]
        case .subtract:
            return [IRInstruction(offset: offset, op: .binaryOp(.subtract))]
        case .multiply:
            return [IRInstruction(offset: offset, op: .binaryOp(.multiply))]
        case .divide:
            return [IRInstruction(offset: offset, op: .binaryOp(.divide))]
        case .mod:
            return [IRInstruction(offset: offset, op: .binaryOp(.modulo))]
        case .equal:
            return [IRInstruction(offset: offset, op: .binaryOp(.equal))]
        case .notEqual:
            return [IRInstruction(offset: offset, op: .binaryOp(.notEqual))]
        case .lessThan:
            return [IRInstruction(offset: offset, op: .binaryOp(.lessThan))]
        case .lessThanEqual:
            return [IRInstruction(offset: offset, op: .binaryOp(.lessThanEqual))]
        case .greaterThan:
            return [IRInstruction(offset: offset, op: .binaryOp(.greaterThan))]
        case .greaterThanEqual:
            return [IRInstruction(offset: offset, op: .binaryOp(.greaterThanEqual))]

        case .not:
            return [IRInstruction(offset: offset, op: .unaryOp(.not))]
        case .negate:
            return [IRInstruction(offset: offset, op: .unaryOp(.negate))]

        case .setVar(let source, let target):
            return [IRInstruction(offset: offset, op: .assign(
                target: translateVar(target),
                source: translateVar(source)
            ))]

        case .copyStruct(let source, let dest, let length):
            return [IRInstruction(offset: offset, op: .copyMemory(
                dest: translateVar(dest),
                source: translateVar(source),
                length: Int(length)
            ))]

        case .printf(_, let argCount):
            return [IRInstruction(offset: offset, op: .printf(argCount: Int(argCount)))]

        case .yield(_, let argCount):
            return [IRInstruction(offset: offset, op: .yield(frames: Int(argCount)))]

        case .callStandard(let retCount, let argCount):
            return [IRInstruction(offset: offset, op: .callBuiltIn(
                functionID: 0,  // actual ID is pushed as first arg
                argCount: Int(argCount),
                returnCount: Int(retCount)
            ))]

        case .invalid:
            return [IRInstruction(offset: offset, op: .nop)]
        }
    }

    // MARK: - Variable Translation

    private func translateVar(_ v: ColoScriptVar) -> IRVariable {
        let type: IRValueType
        switch v.valueType {
        case .void: type = .void
        case .integer: type = .integer
        case .float: type = .float
        case .unknown(let id): type = .unknown(id: id)
        }

        let storage: IRVariable.Storage
        if v.isLiteral {
            storage = .literal
        } else if v.isLocal {
            storage = .local(index: 0)  // actual index determined by stack position
        } else {
            storage = .global(index: 0)  // actual index determined by stack position
        }

        return IRVariable(storage: storage, valueType: type)
    }

    // MARK: - Argument Inference

    private func inferArgCount(_ instructions: [ColoScriptInstruction]) -> Int {
        // Simple heuristic: count is based on call sites referencing this function
        // For now, return 0 — will be refined when cross-referencing is available
        return 0
    }
}
