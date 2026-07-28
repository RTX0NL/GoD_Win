import GoDFoundation
import ScriptDecompiler
import Structs

/// Emits complete dialect source text for a Colosseum script — the exact
/// text `ColoScriptTextParser` + `ColoScriptCompiler` reproduce byte-exactly
/// (verified across the full US corpus by the stage-4 round trip).
public struct ColoScriptSourceEmitter {

    public let builtInFunctions: [Int: ScriptFunctionDef]
    public let enums: [String: Enum]

    public init(builtInFunctions: [Int: ScriptFunctionDef] = [:], enums: [String: Enum] = [:]) {
        self.builtInFunctions = builtInFunctions
        self.enums = enums
    }

    public func decompileToText(script: ColoScript, fileName: String, syntax: ColoScriptSourceHeader.Syntax = .swift) -> String {
    let exprBuilder = ColoExpressionBuilder()
    let compound = ColoExpressionCompound()
    let sourceHeader = ColoScriptSourceHeader()
    let formatter = ColoExprFormatter(
        builtInFunctions: builtInFunctions,
        enums: enums,
        stringResolver: { script.cString(at: $0) }
    )

    let comment = syntax == .python ? "#" : "//"
    var output = "\(comment) Decompiled from \(fileName) (Colosseum US)\n"
    output += "\(comment) \(script.functions.count) functions, \(script.totalInstructionCount) instructions\n\n"
    output += sourceHeader.preamble(for: script, syntax: syntax) + "\n\n"

    // Global-variable declarations: slot types inferred from the primitive
    // masks of static-index accesses (strong typing holds corpus-wide)
    var slotTypes = [Int: ColoValueType]()
    func recordSlotTypes(_ expr: ColoExpr) {
        switch expr {
        case .variable(let v, let indexExpr, _):
            if v.isGlobal, case .constant(.integer(let idx)) = indexExpr, slotTypes[Int(idx)] == nil {
                slotTypes[Int(idx)] = v.valueType
            }
            recordSlotTypes(indexExpr)
        case .variableAssignment(let a, let b): recordSlotTypes(a); recordSlotTypes(b)
        case .structAssignment(let a, let b, _): recordSlotTypes(a); recordSlotTypes(b)
        case .operation(_, let operands): operands.forEach(recordSlotTypes)
        case .call(_, _, let a): a.forEach(recordSlotTypes)
        case .callBuiltIn(let id, let a): recordSlotTypes(id); a.forEach(recordSlotTypes)
        case .printf(_, let a): a.forEach(recordSlotTypes)
        case .yield(let f): recordSlotTypes(f)
        case .returnResult(let v): recordSlotTypes(v)
        case .jumpFalse(let c, _): recordSlotTypes(c)
        case .ifStatement(let branches):
            for b in branches { recordSlotTypes(b.0); b.1.forEach(recordSlotTypes) }
        case .whileLoop(let c, let body): recordSlotTypes(c); body.forEach(recordSlotTypes)
        default: break
        }
    }

    // Determine which functions return a value: internal call sites with
    // returnCount 1, or a `return <value>` in the body
    var returnsValue = Set<Int>()
    var builtByRun = [Int: (expressions: [ColoExpr], argCount: Int)]()
    for run in script.codeRuns {
        let built = exprBuilder.buildExpressions(instructions: run.instructions)
        builtByRun[run.start] = built

        func scan(_ expr: ColoExpr) {
            switch expr {
            case .call(let target, let returnCount, let callArgs):
                if returnCount == 1 { returnsValue.insert(target) }
                callArgs.forEach(scan)
            case .callBuiltIn(let id, let callArgs): scan(id); callArgs.forEach(scan)
            case .variable(_, let inner, _): scan(inner)
            case .variableAssignment(let a, let b): scan(a); scan(b)
            case .structAssignment(let a, let b, _): scan(a); scan(b)
            case .operation(_, let operands): operands.forEach(scan)
            case .printf(_, let a): a.forEach(scan)
            case .yield(let f): scan(f)
            case .returnResult(let v): scan(v)
            case .jumpFalse(let c, _): scan(c)
            case .ifStatement(let branches):
                for b in branches { scan(b.0); b.1.forEach(scan) }
            case .whileLoop(let c, let body): scan(c); body.forEach(scan)
            default: break
            }
        }
        if let index = script.functionOffsets.firstIndex(of: UInt32(run.start)) {
            for expression in built.expressions {
                if case .returnResult = expression { returnsValue.insert(index) }
                scan(expression)
                recordSlotTypes(expression)
            }
        }
    }

    if script.globalVariableCount > 0 {
        let types = (0..<script.globalVariableCount).map { slotTypes[$0] }
        output += sourceHeader.gvarDeclarations(types: types, syntax: syntax).joined(separator: "\n") + "\n\n"
    }

    // Functions in file (emission) order — the function table is
    // rederived from this order plus each function's compiled size.
    for run in script.codeRuns {
        guard let index = script.functionOffsets.firstIndex(of: UInt32(run.start)),
              let built = builtByRun[run.start] else { continue }
        let hasReturnValue = returnsValue.contains(index)
        var fnFormatter = formatter
        fnFormatter.flavor = syntax
        fnFormatter.localArgBase = hasReturnValue ? 1 : 0
        let compounded = compound.compound(built.expressions)
        let displayArgCount = hasReturnValue ? max(0, built.argCount - 1) : built.argCount

        // Argument types from the masks of static local reads (rarely float)
        var argTypes = [ColoValueType](repeating: .integer, count: displayArgCount)
        func recordArgTypes(_ expr: ColoExpr) {
            switch expr {
            case .variable(let v, let indexExpr, _):
                if v.isLocal, !v.isLiteral, case .constant(.integer(let idx)) = indexExpr {
                    let display = Int(idx) - fnFormatter.localArgBase
                    if display >= 0, display < argTypes.count, v.valueType == .float {
                        argTypes[display] = .float
                    }
                }
                recordArgTypes(indexExpr)
            case .variableAssignment(let a, let b): recordArgTypes(a); recordArgTypes(b)
            case .structAssignment(let a, let b, _): recordArgTypes(a); recordArgTypes(b)
            case .operation(_, let operands): operands.forEach(recordArgTypes)
            case .call(_, _, let a): a.forEach(recordArgTypes)
            case .callBuiltIn(let id, let a): recordArgTypes(id); a.forEach(recordArgTypes)
            case .printf(_, let a): a.forEach(recordArgTypes)
            case .yield(let f): recordArgTypes(f)
            case .returnResult(let v): recordArgTypes(v)
            case .jumpFalse(let c, _): recordArgTypes(c)
            case .ifStatement(let branches):
                for b in branches { recordArgTypes(b.0); b.1.forEach(recordArgTypes) }
            case .whileLoop(let c, let body): recordArgTypes(c); body.forEach(recordArgTypes)
            default: break
            }
        }
        built.expressions.forEach(recordArgTypes)

        output += fnFormatter.formatFunction(
            index: index, name: "function_\(index)", argCount: displayArgCount,
            returnsValue: hasReturnValue, argTypes: argTypes, body: compounded) + "\n\n"
    }

    // Null table entries as stub declarations
    for (index, offset) in script.functionOffsets.enumerated() where offset == 0 {
        output += ColoScriptSourceHeader().nullFunctionStub(index: index, syntax: syntax) + "\n"
    }

    return output
}
}
