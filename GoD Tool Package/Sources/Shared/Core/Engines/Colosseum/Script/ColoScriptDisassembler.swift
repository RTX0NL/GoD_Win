import GoDFoundation

/// Produces a human-readable disassembly listing from a parsed ColoScript
public struct ColoScriptDisassembler {

    public init() {}

    /// Disassemble a parsed script into a text listing
    public func disassemble(_ script: ColoScript, commonFunctionNames: [Int: String]? = nil) -> String {
        var lines = [String]()

        lines.append("; Colosseum Script Disassembly")
        lines.append("; Type: 0x\(String(script.scriptTypeID, radix: 16, uppercase: true))")
        lines.append("; Functions: \(script.numberOfFunctions)")
        lines.append("")

        for (funcIndex, instructions) in script.functions.enumerated() {
            guard !instructions.isEmpty else { continue }

            // Collect jump targets for label generation
            var jumpTargets = Set<Int>()
            for inst in instructions {
                if let target = inst.jumpTarget {
                    jumpTargets.insert(Int(target))
                }
            }

            // Infer argument count from local variable usage
            let argCount = inferArgumentCount(instructions)

            // Function header
            let argList = (0..<argCount).map { "arg\($0)" }.joined(separator: ", ")
            lines.append("; Function \(funcIndex) (offset 0x\(String(instructions[0].offset, radix: 16, uppercase: true)))")
            lines.append("function_\(funcIndex)(\(argList)):")

            // Instructions
            for inst in instructions {
                // Label at jump targets
                if jumpTargets.contains(inst.offset) {
                    lines.append(".L_\(String(format: "%04X", inst.offset)):")
                }

                let text = formatInstruction(inst, commonFunctionNames: commonFunctionNames)
                lines.append("    \(text)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Instruction Formatting

    private func formatInstruction(_ inst: ColoScriptInstruction, commonFunctionNames: [Int: String]?) -> String {
        let op = inst.opcode
        switch op {
        case .nop:
            return "nop"
        case .exit:
            return "exit"
        case .pushMinus1:
            return "push -1"
        case .pop(_, let count):
            return "pop \(count)"
        case .call(let funcID, let retCount, let argCount):
            let name = commonFunctionNames?[Int(funcID)] ?? "function_\(funcID)"
            return "call \(name) argc:\(argCount) retc:\(retCount)"
        case .returnOp:
            return "return"
        case .jump(let offset):
            return "jump .L_\(String(format: "%04X", offset))"
        case .jumpFalse(let offset):
            return "jumpFalse .L_\(String(format: "%04X", offset))"
        case .pushImmediate(let type, let value):
            return "push \(formatImmediate(type: type, value: value))"
        case .bitwiseAnd(let v1, let v2):
            return "and \(formatVar(v1)) \(formatVar(v2))"
        case .bitwiseOr(let v1, let v2):
            return "or \(formatVar(v1)) \(formatVar(v2))"
        case .pushVar(let v):
            return "pushVar \(formatVar(v))"
        case .pushMultiVar(let v, let count):
            return "pushMultiVar \(formatVar(v)) x\(count)"
        case .not(let v):
            return "not \(formatVar(v))"
        case .negate(let v):
            return "negate \(formatVar(v))"
        case .pushVar2(let v):
            return "pushVar2 \(formatVar(v))"
        case .multiply(let v1, let v2):
            return "mul \(formatVar(v1)) \(formatVar(v2))"
        case .divide(let v1, let v2):
            return "div \(formatVar(v1)) \(formatVar(v2))"
        case .mod(let v1, let v2):
            return "mod \(formatVar(v1)) \(formatVar(v2))"
        case .add(let v1, let v2):
            return "add \(formatVar(v1)) \(formatVar(v2))"
        case .subtract(let v1, let v2):
            return "sub \(formatVar(v1)) \(formatVar(v2))"
        case .lessThan(let v1, let v2):
            return "lt \(formatVar(v1)) \(formatVar(v2))"
        case .lessThanEqual(let v1, let v2):
            return "le \(formatVar(v1)) \(formatVar(v2))"
        case .greaterThan(let v1, let v2):
            return "gt \(formatVar(v1)) \(formatVar(v2))"
        case .greaterThanEqual(let v1, let v2):
            return "ge \(formatVar(v1)) \(formatVar(v2))"
        case .equal(let v1, let v2):
            return "eq \(formatVar(v1)) \(formatVar(v2))"
        case .notEqual(let v1, let v2):
            return "ne \(formatVar(v1)) \(formatVar(v2))"
        case .setVar(let src, let tgt):
            return "setVar \(formatVar(tgt)) = \(formatVar(src))"
        case .copyStruct(let src, let dst, let len):
            return "copyStruct \(formatVar(dst)) <- \(formatVar(src)) len:\(len)"
        case .logicalAnd(let v1, let v2):
            return "andl \(formatVar(v1)) \(formatVar(v2))"
        case .logicalOr(let v1, let v2):
            return "orl \(formatVar(v1)) \(formatVar(v2))"
        case .printf(_, let argc):
            return "printf argc:\(argc)"
        case .yield(_, let argc):
            return "yield \(argc)"
        case .callStandard(let retCount, let argc):
            return "callStandard argc:\(argc) retc:\(retCount)"
        case .invalid(let id):
            return "INVALID(\(id))"
        }
    }

    private func formatVar(_ v: ColoScriptVar) -> String {
        if v.isLiteral {
            return "lit(\(v.valueType.name))"
        } else if v.isLocal {
            return "local(\(v.valueType.name))"
        } else {
            return "global(\(v.valueType.name))"
        }
    }

    private func formatImmediate(type: ColoValueType, value: UInt32) -> String {
        switch type {
        case .integer:
            let signed = Int32(bitPattern: value)
            if signed >= -256 && signed <= 0xFF {
                return "\(signed)"
            }
            return "0x\(String(value, radix: 16, uppercase: true))"
        case .float:
            let f = Float(bitPattern: value)
            return "\(f)"
        default:
            return "\(type.name) 0x\(String(value, radix: 16, uppercase: true))"
        }
    }

    // MARK: - Analysis

    /// Infer the number of arguments from local variable push instructions
    private func inferArgumentCount(_ instructions: [ColoScriptInstruction]) -> Int {
        var maxLocalIndex = -1
        for inst in instructions {
            switch inst.opcode {
            case .pushVar(let v), .pushVar2(let v), .not(let v), .negate(let v):
                if v.isLocal { maxLocalIndex = max(maxLocalIndex, 0) }
            case .pushMultiVar(let v, _):
                if v.isLocal { maxLocalIndex = max(maxLocalIndex, 0) }
            case .setVar(let src, let tgt):
                if src.isLocal { maxLocalIndex = max(maxLocalIndex, 0) }
                if tgt.isLocal { maxLocalIndex = max(maxLocalIndex, 0) }
            default: break
            }
        }
        // This is a rough heuristic — argument count inference from local var usage
        // is imprecise. A better approach would be to check call sites.
        return maxLocalIndex + 1
    }
}
