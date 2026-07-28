//
//  ColoScriptDecomp — temporary harness.
//
//  Decompiles Colosseum .scd scripts to Swift-syntax pseudocode using the
//  same pipeline as ColoDecompilerTests.testDecompileRealScript.
//
//  Usage: ColoScriptDecomp <output-dir> <script.scd> [...]
//

import Foundation
import GoDFoundation
import ScriptDecompiler
import Colosseum

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: ColoScriptDecomp <output-dir> <script.scd> [...]")
    print("       ColoScriptDecomp --scan <script.scd> [...]")
    exit(2)
}

// Shared decompile context
let builtInFunctionsByID = ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
    if let id = Int(pair.key) { result[id] = pair.value }
}
let engineEnums = Dictionary(
    ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
    uniquingKeysWith: { first, _ in first }
)

let sourceEmitter = ColoScriptSourceEmitter(builtInFunctions: builtInFunctionsByID, enums: engineEnums)
func decompileToText(script: ColoScript, fileName: String) -> String {
    sourceEmitter.decompileToText(script: script, fileName: fileName)
}

// Stage-4 debug: decompile, reparse, recompile one script and report the
// first instruction-level divergence per code run.
// usage: ColoScriptDecomp --stage4 <script.scd>
if args[1] == "--stage4" {
    let rawData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let script = try ColoScript(data: GoDData(data: rawData, byteOrder: .big))
    let text = decompileToText(script: script, fileName: args[2])
    var parser = ColoScriptTextParser(builtInFunctions: builtInFunctionsByID)
    let parsed = try parser.parse(text)
    let compiled = try ColoScriptCompiler().compile(parsed)
    let recompiled = try ColoScript(data: compiled)

    print("orig: funcs=\(script.numberOfFunctions) relocs=\(script.relocationCount) arena=\(script.globalVariableCount) len=\(script.rawData.length)")
    print("ours: funcs=\(recompiled.numberOfFunctions) relocs=\(recompiled.relocationCount) arena=\(recompiled.globalVariableCount) len=\(compiled.length)")
    for (a, b) in zip(script.codeRuns, recompiled.codeRuns) {
        guard let fnA = script.functionOffsets.firstIndex(of: UInt32(a.start)) else { continue }
        if a.instructions.map(\.opcode) == b.instructions.map(\.opcode) { continue }
        print("\nfn\(fnA) orig@0x\(String(a.start, radix: 16)) ours@0x\(String(b.start, radix: 16)) counts \(a.instructions.count)/\(b.instructions.count)")
        // Compare structurally: jump targets shift when lengths differ, so
        // normalize them away to find the real divergence
        func shape(_ opcode: ColoScriptOpcode) -> String {
            switch opcode {
            case .jump: return "jump"
            case .jumpFalse: return "jumpFalse"
            default: return "\(opcode)"
            }
        }
        for i in 0..<max(a.instructions.count, b.instructions.count) {
            let left = i < a.instructions.count ? shape(a.instructions[i].opcode) : "-"
            let right = i < b.instructions.count ? shape(b.instructions[i].opcode) : "-"
            if left != right {
                for j in max(0, i - 3)..<i {
                    print("   =  \(a.instructions[j].opcode)")
                }
                print("   != orig: \(left)")
                print("      ours: \(right)")
                for j in (i + 1)..<min(a.instructions.count, i + 6) {
                    print("      | orig: \(a.instructions[j].opcode)")
                }
                break
            }
        }
    }
    exit(0)
}

// Disasm mode: print the flat instruction listing for one function of a
// script, to compare program order against the decompiled output.
// usage: ColoScriptDecomp --disasm <script.scd> <functionIndex>
if args[1] == "--disasm", args.count >= 4, let fnIndex = Int(args[3]) {
    let rawData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let script = try ColoScript(data: GoDData(data: rawData, byteOrder: .big))
    guard fnIndex < script.functions.count else { print("no function \(fnIndex)"); exit(1) }
    let disasm = ColoScriptDisassembler()
    // Disassemble the whole script but only print the requested function's slice.
    print(disasm.disassemble(script))
    exit(0)
}

// Variable-usage analysis: walk the expression trees of every script and
// report (a) local-variable index usage per function vs the argument counts
// seen at internal call sites — to establish whether true function-scoped
// locals exist — and (b) every global access whose index is a computed
// expression rather than a constant — to evaluate the array hypothesis.
// usage: ColoScriptDecomp --analyze-vars <script.scd> [...]
if args[1] == "--analyze-vars" {
    let formatter = ColoExprFormatter()

    struct FunctionInfo {
        var maxLocalConst = -1
        var localWriteIndices = Set<Int>()
        var computedLocal = [String]()
        var callSiteArgcs = Set<Int>()   // argc of `call` exprs targeting this function
        var returnsValue = false
    }

    var computedGlobals = [String]()     // "file fn: <expr> (context)"
    var localExceedsArgc = [String]()
    var fileCount = 0

    for scriptPath in args.dropFirst(2) {
        let url = URL(fileURLWithPath: scriptPath)
        let name = url.deletingPathExtension().lastPathComponent
        guard let rawData = try? Data(contentsOf: url),
              let script = try? ColoScript(data: GoDData(data: rawData, byteOrder: .big)) else { continue }
        fileCount += 1

        var infos = [Int: FunctionInfo]()

        func walk(_ expr: ColoExpr, functionIndex: Int, isWrite: Bool = false) {
            switch expr {
            case .constant:
                break
            case .variable(let v, let indexExpr, _):
                if case .constant(.integer(let idx)) = indexExpr {
                    if v.isLocal {
                        infos[functionIndex, default: .init()].maxLocalConst =
                            max(infos[functionIndex, default: .init()].maxLocalConst, Int(idx))
                        if isWrite { infos[functionIndex, default: .init()].localWriteIndices.insert(Int(idx)) }
                    }
                } else if !v.isLiteral {
                    let text = "\(name) fn\(functionIndex): [\(formatter.formatExpr(indexExpr))] \(isWrite ? "write" : "read") (\(v.isGlobal ? "global" : "local"))"
                    if v.isGlobal { computedGlobals.append(text) }
                    else { infos[functionIndex, default: .init()].computedLocal.append(text) }
                }
                walk(indexExpr, functionIndex: functionIndex)
            case .variableAssignment(let target, let value):
                walk(target, functionIndex: functionIndex, isWrite: true)
                walk(value, functionIndex: functionIndex)
            case .structAssignment(let a, let b, _):
                walk(a, functionIndex: functionIndex, isWrite: true)
                walk(b, functionIndex: functionIndex)
            case .operation(_, let operands):
                operands.forEach { walk($0, functionIndex: functionIndex) }
            case .call(let target, let returnCount, let callArgs):
                infos[target, default: .init()].callSiteArgcs.insert(callArgs.count)
                if returnCount == 1 { infos[target, default: .init()].returnsValue = true }
                callArgs.forEach { walk($0, functionIndex: functionIndex) }
            case .callBuiltIn(let id, let callArgs):
                walk(id, functionIndex: functionIndex)
                callArgs.forEach { walk($0, functionIndex: functionIndex) }
            case .printf(_, let callArgs):
                callArgs.forEach { walk($0, functionIndex: functionIndex) }
            case .yield(let frames):
                walk(frames, functionIndex: functionIndex)
            case .returnResult(let value):
                walk(value, functionIndex: functionIndex)
            case .jumpFalse(let condition, _):
                walk(condition, functionIndex: functionIndex)
            case .ifStatement(let branches):
                for branch in branches {
                    walk(branch.0, functionIndex: functionIndex)
                    branch.1.forEach { walk($0, functionIndex: functionIndex) }
                }
            case .whileLoop(let condition, let body):
                walk(condition, functionIndex: functionIndex)
                body.forEach { walk($0, functionIndex: functionIndex) }
            case .returnVoid, .jump, .location, .exit, .nop:
                break
            }
        }

        for run in script.codeRuns {
            guard let index = script.functionOffsets.firstIndex(of: UInt32(run.start)) else { continue }
            let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: run.instructions)
            expressions.forEach { walk($0, functionIndex: index) }
        }

        // Compare local usage against internal call sites
        for (fn, info) in infos.sorted(by: { $0.key < $1.key }) {
            guard !info.callSiteArgcs.isEmpty else { continue }
            let maxArgc = info.callSiteArgcs.max() ?? 0
            // local0 is the return-value slot; args occupy local1... in callee?
            // Report any local index beyond what call-site args can explain.
            if info.maxLocalConst + 1 > maxArgc {
                localExceedsArgc.append("\(name) fn\(fn): maxLocal=\(info.maxLocalConst) callArgcs=\(info.callSiteArgcs.sorted()) writes=\(info.localWriteIndices.sorted()) retc1=\(info.returnsValue)")
            }
        }
    }

    print("analyzed \(fileCount) files")
    print("\nfunctions whose local usage exceeds call-site argc (\(localExceedsArgc.count)):")
    localExceedsArgc.prefix(40).forEach { print("  \($0)") }
    print("\ncomputed GLOBAL index expressions (\(computedGlobals.count)):")
    computedGlobals.forEach { print("  \($0)") }
    exit(0)
}

// Per-file global-index census for the array hypothesis: direct constant
// indices vs computed-index shapes vs arena capacity.
// usage: ColoScriptDecomp --globals-census <script.scd> [...]
if args[1] == "--globals-census" {
    // Parenthesized rendering so the expression tree shape is unambiguous
    func paren(_ expr: ColoExpr) -> String {
        switch expr {
        case .constant(.integer(let v)): return "\(v)"
        case .constant(.float(let v)): return "\(v)"
        case .constant(let c): return "<\(c)>"
        case .variable(let v, let inner, _):
            if v.isGlobal { return "g(\(paren(inner)))" }
            if v.isLocal { return "l(\(paren(inner)))" }
            return paren(inner)
        case .operation(let op, let operands) where operands.count == 2:
            return "(\(paren(operands[1])) \(op.symbol) \(paren(operands[0])))"
        case .operation(let op, let operands) where operands.count == 1:
            return "\(op.symbol)\(paren(operands[0]))"
        default: return "<\(expr)>"
        }
    }
    for scriptPath in args.dropFirst(2) {
        let url = URL(fileURLWithPath: scriptPath)
        let name = url.deletingPathExtension().lastPathComponent
        guard let rawData = try? Data(contentsOf: url),
              let script = try? ColoScript(data: GoDData(data: rawData, byteOrder: .big)) else { continue }

        var direct = Set<Int>()
        var computed = [String]()

        func walk(_ expr: ColoExpr) {
            switch expr {
            case .constant: break
            case .variable(let v, let indexExpr, _):
                if v.isGlobal {
                    if case .constant(.integer(let idx)) = indexExpr { direct.insert(Int(idx)) }
                    else { computed.append(paren(indexExpr)) }
                }
                walk(indexExpr)
            case .variableAssignment(let a, let b): walk(a); walk(b)
            case .structAssignment(let a, let b, _): walk(a); walk(b)
            case .operation(_, let operands): operands.forEach(walk)
            case .call(_, _, let a): a.forEach(walk)
            case .callBuiltIn(let id, let a): walk(id); a.forEach(walk)
            case .printf(_, let a): a.forEach(walk)
            case .yield(let f): walk(f)
            case .returnResult(let v): walk(v)
            case .jumpFalse(let c, _): walk(c)
            case .ifStatement(let branches):
                for b in branches { walk(b.0); b.1.forEach(walk) }
            case .whileLoop(let c, let body): walk(c); body.forEach(walk)
            case .returnVoid, .jump, .location, .exit, .nop: break
            }
        }

        for run in script.codeRuns {
            let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: run.instructions)
            expressions.forEach(walk)
        }

        guard !computed.isEmpty || script.globalVariableCount > 0 else { continue }
        print("\(name): arenaSlots=\(script.globalVariableCount) direct=\(direct.sorted())")
        if !computed.isEmpty {
            var shapes = [String: Int]()
            computed.forEach { shapes[$0, default: 0] += 1 }
            for (shape, count) in shapes.sorted(by: { $0.key < $1.key }) {
                print("    computed [\(shape)] ×\(count)")
            }
        }
    }
    exit(0)
}

// Builtin-argument census + primitive type consistency.
// For every callStandard invocation: record per (functionID, argPosition) the
// kinds of values passed (constants with ranges, float constants, gvar reads,
// arg reads, call results, expressions). For every gvar slot: the set of
// primitive type masks used to access it (int vs float consistency).
// usage: ColoScriptDecomp --builtin-census <script.scd> [...]
if args[1] == "--builtin-census" {
    struct ArgStats {
        var intConstants = [Int32]()
        var floatCount = 0
        var gvarReads = 0
        var argReads = 0
        var callResults = 0
        var builtinResults = 0
        var expressions = 0
        var total = 0
    }
    var stats = [Int: [Int: ArgStats]]()      // funcID -> argPos -> stats
    var returnUsed = [Int: Int]()              // funcID -> value-context uses
    var returnDiscarded = [Int: Int]()
    var slotTypes = [String: Set<Int>]()       // "file:slot" -> primitive type ids used
    var argCounts = [Int: Set<Int>]()

    func classify(_ expr: ColoExpr, into s: inout ArgStats) {
        s.total += 1
        switch expr {
        case .constant(.integer(let v)): s.intConstants.append(v)
        case .constant(.float): s.floatCount += 1
        case .variable(let v, _, _) where v.isGlobal: s.gvarReads += 1
        case .variable(let v, _, _) where v.isLocal: s.argReads += 1
        case .call: s.callResults += 1
        case .callBuiltIn: s.builtinResults += 1
        default: s.expressions += 1
        }
    }

    for scriptPath in args.dropFirst(2) {
        let url = URL(fileURLWithPath: scriptPath)
        let name = url.deletingPathExtension().lastPathComponent
        guard let rawData = try? Data(contentsOf: url),
              let script = try? ColoScript(data: GoDData(data: rawData, byteOrder: .big)) else { continue }

        func walk(_ expr: ColoExpr, valueContext: Bool) {
            switch expr {
            case .variable(let v, let indexExpr, _):
                if v.isGlobal, case .constant(.integer(let idx)) = indexExpr {
                    slotTypes["\(name):\(idx)", default: []].insert(v.valueType.id)
                }
                walk(indexExpr, valueContext: true)
            case .variableAssignment(let a, let b): walk(a, valueContext: true); walk(b, valueContext: true)
            case .structAssignment(let a, let b, _): walk(a, valueContext: true); walk(b, valueContext: true)
            case .operation(_, let operands): operands.forEach { walk($0, valueContext: true) }
            case .call(_, _, let a): a.forEach { walk($0, valueContext: true) }
            case .callBuiltIn(let idExpr, let callArgs):
                if case .constant(.integer(let id)) = idExpr {
                    let fid = Int(id)
                    argCounts[fid, default: []].insert(callArgs.count)
                    if stats[fid] == nil { stats[fid] = [:] }  // count zero-arg builtins too
                    for (pos, arg) in callArgs.enumerated() {
                        classify(arg, into: &stats[fid, default: [:]][pos, default: ArgStats()])
                    }
                    if valueContext { returnUsed[fid, default: 0] += 1 }
                    else { returnDiscarded[fid, default: 0] += 1 }
                }
                walk(idExpr, valueContext: true)
                callArgs.forEach { walk($0, valueContext: true) }
            case .printf(_, let a): a.forEach { walk($0, valueContext: true) }
            case .yield(let f): walk(f, valueContext: true)
            case .returnResult(let v): walk(v, valueContext: true)
            case .jumpFalse(let c, _): walk(c, valueContext: true)
            case .ifStatement(let branches):
                for b in branches { walk(b.0, valueContext: true); b.1.forEach { walk($0, valueContext: false) } }
            case .whileLoop(let c, let body): walk(c, valueContext: true); body.forEach { walk($0, valueContext: false) }
            default: break
            }
        }

        for run in script.codeRuns {
            let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: run.instructions)
            expressions.forEach { walk($0, valueContext: false) }
        }
    }

    // Primitive consistency
    let mixed = slotTypes.filter { $0.value.count > 1 }
    print("gvar slots accessed: \(slotTypes.count); slots with MIXED primitive types: \(mixed.count)")
    mixed.sorted(by: { $0.key < $1.key }).prefix(20).forEach { print("  mixed: \($0.key) types=\($0.value.sorted())") }

    // Per-builtin table
    print("\nbuiltin usage (id, calls, args -> per-arg summary):")
    for (fid, argMap) in stats.sorted(by: { $0.key < $1.key }) {
        let calls = (returnUsed[fid] ?? 0) + (returnDiscarded[fid] ?? 0)
        var line = "id \(fid) calls=\(calls) argcs=\(argCounts[fid]?.sorted() ?? []) retUsed=\(returnUsed[fid] ?? 0)"
        print(line)
        for (pos, s) in argMap.sorted(by: { $0.key < $1.key }) {
            line = "    arg\(pos): n=\(s.total)"
            if !s.intConstants.isEmpty {
                let sorted = s.intConstants.sorted()
                let uniq = Set(sorted)
                line += " ints=\(s.intConstants.count) range=[\(sorted.first!)..\(sorted.last!)] uniq=\(uniq.count)"
                if uniq.count <= 6 { line += " values=\(uniq.sorted())" }
            }
            if s.floatCount > 0 { line += " floats=\(s.floatCount)" }
            if s.gvarReads > 0 { line += " gvars=\(s.gvarReads)" }
            if s.argReads > 0 { line += " args=\(s.argReads)" }
            if s.callResults > 0 { line += " callResults=\(s.callResults)" }
            if s.builtinResults > 0 { line += " builtinResults=\(s.builtinResults)" }
            if s.expressions > 0 { line += " exprs=\(s.expressions)" }
            print(line)
        }
    }
    exit(0)
}

// Round-trip mode: for every script, run each rebuild stage and compare the
// output against the original bytes. Reports per-stage pass counts and the
// first divergence for failing files.
// usage: ColoScriptDecomp --roundtrip <script.scd> [...]
if args[1] == "--roundtrip" {
    var stagePass = [Int](repeating: 0, count: 5)
    var parsed = 0, failures = [String]()
    var nonZeroPadFiles = [String]()

    func firstDiff(_ a: [UInt8], _ b: [UInt8]) -> Int? {
        for i in 0..<min(a.count, b.count) where a[i] != b[i] { return i }
        return a.count == b.count ? nil : min(a.count, b.count)
    }
    func hexContext(_ bytes: [UInt8], around offset: Int) -> String {
        let lo = max(0, offset - 8), hi = min(bytes.count, offset + 8)
        return bytes[lo..<hi].map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    for scriptPath in args.dropFirst(2) {
        let url = URL(fileURLWithPath: scriptPath)
        let name = url.lastPathComponent
        guard let rawData = try? Data(contentsOf: url) else { print("READFAIL \(name)"); continue }
        let original = [UInt8](rawData)
        do {
            let script = try ColoScript(data: GoDData(data: rawData, byteOrder: .big))
            parsed += 1

            // Flag structural anomalies: a non-zero globals arena, or non-zero
            // trailing bytes in a file with no relocations (relocated files
            // legitimately keep their string data in the tail region)
            let arena = script.globalsArena.rawBytes
            let pads = script.codeRuns.flatMap { $0.trailingData.rawBytes }
            if arena.contains(where: { $0 != 0 })
                || (script.relocations.isEmpty && pads.contains(where: { $0 != 0 })) {
                nonZeroPadFiles.append(name)
            }

            // Stage 1: binary -> instructions -> binary
            let rebuilt = ColoScriptAssembler.assemble(script).rawBytes
            if let diff = firstDiff(original, rebuilt) {
                failures.append("stage1 \(name): first diff @0x\(String(diff, radix: 16))"
                    + " sizes \(original.count)/\(rebuilt.count)"
                    + "\n  orig: \(hexContext(original, around: diff))"
                    + "\n  ours: \(hexContext(rebuilt, around: diff))")
            } else {
                stagePass[0] += 1
            }

            // Stage 2: binary -> expressions -> instructions -> binary
            let lowering = ColoExprLowering()
            var stage2OK = true
            var rebuiltRuns = [ColoScript.CodeRun]()
            for run in script.codeRuns {
                let (expressions, _) = ColoExpressionBuilder().buildExpressions(
                    instructions: run.instructions)
                let lowered = lowering.lower(expressions, startOffset: run.start)
                if lowered != run.instructions {
                    stage2OK = false
                    let firstMismatch = zip(lowered, run.instructions).enumerated()
                        .first(where: { $0.element.0 != $0.element.1 })
                    var detail = "count \(lowered.count)/\(run.instructions.count)"
                    if let (i, pair) = firstMismatch {
                        detail += " first mismatch #\(i) @0x\(String(pair.1.offset, radix: 16)): ours=\(pair.0.opcode) orig=\(pair.1.opcode)"
                    }
                    failures.append("stage2 \(name) run@0x\(String(run.start, radix: 16)): \(detail)")
                    break
                }
                rebuiltRuns.append(ColoScript.CodeRun(
                    start: run.start, instructions: lowered, trailingData: run.trailingData))
            }
            if stage2OK { stagePass[1] += 1 }

            // Stage 3: expressions -> compound (if/while) -> uncompound -> instructions
            var stage3OK = true
            for run in script.codeRuns {
                let (expressions, _) = ColoExpressionBuilder().buildExpressions(
                    instructions: run.instructions)
                let compounded = ColoExpressionCompound().compound(expressions)
                let flattened = ColoExprUncompound().uncompound(compounded)
                let lowered = lowering.lower(flattened, startOffset: run.start)
                if lowered != run.instructions {
                    stage3OK = false
                    let firstMismatch = zip(lowered, run.instructions).enumerated()
                        .first(where: { $0.element.0 != $0.element.1 })
                    var detail = "count \(lowered.count)/\(run.instructions.count)"
                    if let (i, pair) = firstMismatch {
                        detail += " first mismatch #\(i) @0x\(String(pair.1.offset, radix: 16)): ours=\(pair.0.opcode) orig=\(pair.1.opcode)"
                    }
                    failures.append("stage3 \(name) run@0x\(String(run.start, radix: 16)): \(detail)")
                    break
                }
            }
            if stage3OK { stagePass[2] += 1 }

            // Stage 4: binary -> decompiled source text -> parse -> compile -> binary
            do {
                let text = decompileToText(script: script, fileName: name)
                var parser = ColoScriptTextParser(builtInFunctions: builtInFunctionsByID)
                let parsed = try parser.parse(text)
                let compiled = try ColoScriptCompiler().compile(parsed).rawBytes
                if let diff = firstDiff(original, compiled) {
                    failures.append("stage4 \(name): first diff @0x\(String(diff, radix: 16))"
                        + " sizes \(original.count)/\(compiled.count)"
                        + "\n  orig: \(hexContext(original, around: diff))"
                        + "\n  ours: \(hexContext(compiled, around: diff))")
                } else {
                    stagePass[3] += 1
                }
            } catch {
                failures.append("stage4 \(name): \(error)")
            }

            // Stage 5: the same round trip through the Python dialect
            do {
                let text = sourceEmitter.decompileToText(script: script, fileName: name, syntax: .python)
                var parser = ColoScriptTextParser(builtInFunctions: builtInFunctionsByID)
                let parsed = try parser.parse(text)
                let compiled = try ColoScriptCompiler().compile(parsed).rawBytes
                if let diff = firstDiff(original, compiled) {
                    failures.append("stage5 \(name): first diff @0x\(String(diff, radix: 16))"
                        + " sizes \(original.count)/\(compiled.count)"
                        + "\n  orig: \(hexContext(original, around: diff))"
                        + "\n  ours: \(hexContext(compiled, around: diff))")
                } else {
                    stagePass[4] += 1
                }
            } catch {
                failures.append("stage5 \(name): \(error)")
            }
        } catch {
            failures.append("parse \(name): \(error)")
        }
    }

    let total = args.dropFirst(2).count
    print("round trip: \(parsed)/\(total) parsed")
    print("stage 1 (binary -> instructions -> binary): \(stagePass[0])/\(parsed) byte-exact")
    print("stage 2 (instructions -> expressions -> instructions): \(stagePass[1])/\(parsed) exact")
    print("stage 3 (expressions -> if/while structures -> instructions): \(stagePass[2])/\(parsed) exact")
    print("stage 4 (binary -> Swift source -> compile -> binary): \(stagePass[3])/\(parsed) byte-exact")
    print("stage 5 (binary -> Python source -> compile -> binary): \(stagePass[4])/\(parsed) byte-exact")
    if !nonZeroPadFiles.isEmpty {
        print("files with structural anomalies (\(nonZeroPadFiles.count)): \(nonZeroPadFiles.sorted().joined(separator: ", "))")
    }
    if !failures.isEmpty {
        print("\nfailures (\(failures.count)):")
        failures.prefix(40).forEach { print("  \($0)") }
        if failures.count > 40 { print("  ... and \(failures.count - 40) more") }
    }
    exit(failures.isEmpty ? 0 : 1)
}

// Scan mode: decode every instruction across the corpus and report
// occurrences of the legacy decompiler's known edge cases.
if args[1] == "--scan" {
    var multiVarGT1 = 0, multiVarEQ1 = 0, invalidOps = 0, yieldMultiArg = 0, backwardJumps = 0
    var emptyFunctions = 0, totalFunctions = 0, totalInstructions = 0
    var filesWithIssues = Set<String>()
    for scriptPath in args.dropFirst(2) {
        let url = URL(fileURLWithPath: scriptPath)
        let name = url.lastPathComponent
        guard let rawData = try? Data(contentsOf: url) else { print("READFAIL \(name)"); continue }
        do {
            let script = try ColoScript(data: GoDData(data: rawData, byteOrder: .big))
            for instructions in script.functions {
                totalFunctions += 1
                if instructions.isEmpty { emptyFunctions += 1 }
                for instruction in instructions {
                    totalInstructions += 1
                    switch instruction.opcode {
                    case .pushMultiVar(_, let count):
                        if count > 1 { multiVarGT1 += 1; filesWithIssues.insert("\(name): pushMultiVar count=\(count)") }
                        else { multiVarEQ1 += 1 }
                    case .invalid(let id):
                        invalidOps += 1; filesWithIssues.insert("\(name): invalid opcode \(id)")
                    case .yield(_, let argCount):
                        if argCount != 1 { yieldMultiArg += 1; filesWithIssues.insert("\(name): yield argCount=\(argCount)") }
                    case .jump(let target):
                        if Int(target) <= instruction.offset { backwardJumps += 1; filesWithIssues.insert("\(name): backward jump @\(instruction.offset) -> \(target)") }
                    case .jumpFalse(let target):
                        if Int(target) <= instruction.offset { backwardJumps += 1; filesWithIssues.insert("\(name): backward jumpFalse @\(instruction.offset) -> \(target)") }
                    default: break
                    }
                }
            }
        } catch {
            print("PARSEFAIL \(name): \(error)")
        }
    }
    print("scanned: \(totalFunctions) functions, \(totalInstructions) instructions")
    print("pushMultiVar count==1: \(multiVarEQ1), count>1: \(multiVarGT1)")
    print("invalid opcodes: \(invalidOps)")
    print("yield argCount != 1: \(yieldMultiArg)")
    print("empty functions: \(emptyFunctions)")
    if !filesWithIssues.isEmpty {
        print("\nfiles with edge cases:")
        filesWithIssues.sorted().forEach { print("  \($0)") }
    }
    exit(0)
}
let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

var failures = 0
for scriptPath in args.dropFirst(2) {
    let url = URL(fileURLWithPath: scriptPath)
    let name = url.deletingPathExtension().lastPathComponent
    do {
        let rawData = try Data(contentsOf: url)
        let script = try ColoScript(data: GoDData(data: rawData, byteOrder: .big))
        let output = decompileToText(script: script, fileName: url.lastPathComponent)
        let outFile = outputDir.appendingPathComponent("\(name).swift")
        try output.write(to: outFile, atomically: true, encoding: .utf8)
        let pythonOutput = sourceEmitter.decompileToText(script: script, fileName: url.lastPathComponent, syntax: .python)
        try pythonOutput.write(to: outputDir.appendingPathComponent("\(name).py"), atomically: true, encoding: .utf8)
        print("OK   \(name): \(script.codeRuns.count)/\(script.functions.count) functions -> \(outFile.lastPathComponent)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
exit(failures == 0 ? 0 : 1)
