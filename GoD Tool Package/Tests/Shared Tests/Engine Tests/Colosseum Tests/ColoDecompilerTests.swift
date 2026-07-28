import XCTest
import GoDFoundation
import ScriptDecompiler
@testable import Colosseum

final class ColoDecompilerTests: XCTestCase {

    // MARK: - Full Pipeline on Synthetic Script

    func testDecompileSimpleFunction() throws {
        // Build a minimal script with: if (arg == 42) { callStandard(7, ...) } return
        var bytes = [UInt8]()

        // Header (24 bytes)
        bytes += [0x01, 0x00, 0x00, 0x00]  // scriptTypeID, padding
        bytes += [0x00, 0x01, 0x00, 0x00]  // 1 function, unknown
        bytes += [0x00, 0x00, 0x00, 0x00]  // padding
        bytes += [0x00, 0x00, 0x00, 0x1C]  // codeStart1
        bytes += [0x00, 0x00, 0x00, 0x1C]  // codeStart2
        bytes += [0x00, 0x00, 0x00, 0x00]  // padding

        // Function table: function 0 at offset 28
        let codeStart = 28
        bytes += [0x00, 0x00, 0x00, UInt8(codeStart)]

        // Bytecode for function 0:
        // pushImmediate int 42
        bytes += [0x08, 0x02, 0x00, 0x00, 0x00, 0x2A]  // offset 28, len 6
        // pushImmediate int 42
        bytes += [0x08, 0x02, 0x00, 0x00, 0x00, 0x2A]  // offset 34, len 6
        // equal (int, int)
        bytes += [0x1D, 0x82, 0x82]  // offset 40, len 3 (opcode 29)
        // jumpFalse to return (offset 28+6+6+3+5+5+1 = 54)
        let returnOffset = codeStart + 6 + 6 + 3 + 5 + 5 + 1
        bytes += [0x07]  // jumpFalse
        bytes += [UInt8((returnOffset >> 24) & 0xFF), UInt8((returnOffset >> 16) & 0xFF),
                  UInt8((returnOffset >> 8) & 0xFF), UInt8(returnOffset & 0xFF)]  // offset 43, len 5
        // yield 1
        bytes += [0x24, 0x00, 0x00, 0x00, 0x01]  // offset 48, len 5
        // return
        bytes += [0x05]  // offset 53, len 1
        // exit
        bytes += [0x01]  // offset 54, len 1

        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let script = try ColoScript(data: data)

        // Translate to IR
        let translator = ColoScriptIRTranslator()
        let irScript = translator.translate(script)

        XCTAssertEqual(irScript.functions.count, 1)
        XCTAssertFalse(irScript.functions[0].instructions.isEmpty)

        // Stack decompile
        let stackDecompiler = StackDecompiler()
        let statements = stackDecompiler.decompile(irScript.functions[0])
        XCTAssertFalse(statements.isEmpty)

        // Build CFG
        let cfgBuilder = CFGBuilder()
        let cfg = cfgBuilder.build(from: statements)
        XCTAssertFalse(cfg.blocks.isEmpty)

        // Structure AST
        let structurer = CFGStructurer()
        let ast = structurer.structure(cfg)

        // Format as Swift
        let swiftFormatter = ASTFormatter(syntax: SwiftScriptSyntax())
        let function = ASTFunction(index: 0, name: "test_function", argCount: 0, body: ast)
        let swiftOutput = swiftFormatter.format(function: function)

        print("=== Swift Output ===")
        print(swiftOutput)
        XCTAssertTrue(swiftOutput.contains("func test_function"))

        // Format as Python
        let pythonFormatter = ASTFormatter(syntax: PythonScriptSyntax())
        let pythonFunction = ASTFunction(index: 0, name: "test_function", argCount: 0, body: ast)
        let pythonOutput = pythonFormatter.format(function: pythonFunction)

        print("=== Python Output ===")
        print(pythonOutput)
        XCTAssertTrue(pythonOutput.contains("def test_function"))
    }

    // MARK: - Real Script Test

    func testDecompileRealScript() throws {
        let path = "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Build/Unpacked/Assets/Scripts/M1_out.scd"
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("Skipping real script test — file not found")
            return
        }

        let data = GoDData(data: rawData, byteOrder: .big)
        let script = try ColoScript(data: data)

        let exprBuilder = ColoExpressionBuilder()
        let compound = ColoExpressionCompound()
        let builtInFunctions = ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
        let enums = Dictionary(
            ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let formatter = ColoExprFormatter(builtInFunctions: builtInFunctions, enums: enums)

        var output = ""
        var funcCount = 0
        for (index, instructions) in script.functions.enumerated() {
            guard !instructions.isEmpty else { continue }
            let (expressions, argCount) = exprBuilder.buildExpressions(instructions: instructions)
            let compounded = compound.compound(expressions)
            output += formatter.formatFunction(index: index, name: "function_\(index)", argCount: argCount, body: compounded) + "\n\n"
            funcCount += 1
        }

        print("Decompiled \(funcCount) functions from M1_out.scd")
        print("Output length: \(output.count) characters")
        print(output)

        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("func function_"))
        // Verify variable wrapping is working
        XCTAssertTrue(output.contains("gvar") || output.contains("arg"), "Should have variable references")
    }
}
