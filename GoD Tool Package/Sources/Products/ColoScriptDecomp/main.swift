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

// Shared context: built-in function names + enums for readable output.
let builtInFunctions = ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
    if let id = Int(pair.key) { result[id] = pair.value }
}
let enums = Dictionary(
    ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
    uniquingKeysWith: { first, _ in first }
)

var failures = 0
for scriptPath in args.dropFirst(2) {
    let url = URL(fileURLWithPath: scriptPath)
    let name = url.deletingPathExtension().lastPathComponent
    do {
        let rawData = try Data(contentsOf: url)
        let data = GoDData(data: rawData, byteOrder: .big)
        let script = try ColoScript(data: data)

        let exprBuilder = ColoExpressionBuilder()
        let compound = ColoExpressionCompound()
        let formatter = ColoExprFormatter(builtInFunctions: builtInFunctions, enums: enums)

        var output = "// Decompiled from \(url.lastPathComponent) (Colosseum US)\n"
        output += "// \(script.functions.count) functions, \(script.totalInstructionCount) instructions\n\n"

        var emitted = 0
        for (index, instructions) in script.functions.enumerated() {
            guard !instructions.isEmpty else { continue }
            let (expressions, argCount) = exprBuilder.buildExpressions(instructions: instructions)
            let compounded = compound.compound(expressions)
            output += formatter.formatFunction(index: index, name: "function_\(index)", argCount: argCount, body: compounded) + "\n\n"
            emitted += 1
        }

        let outFile = outputDir.appendingPathComponent("\(name).swift")
        try output.write(to: outFile, atomically: true, encoding: .utf8)
        print("OK   \(name): \(emitted)/\(script.functions.count) functions -> \(outFile.lastPathComponent)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
exit(failures == 0 ? 0 : 1)
