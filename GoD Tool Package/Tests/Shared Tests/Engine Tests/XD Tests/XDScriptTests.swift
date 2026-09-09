import XCTest
import GoDFoundation
@testable import XD

final class XDScriptTests: XCTestCase {

    func testDecodeInstruction() {
        // loadImmediate int 42: opcode=2, subop=1(int), param=0, word2=42
        let word1: UInt32 = 0x02_01_0000  // opcode 2, subop 1, param 0
        let word2: UInt32 = 42
        let inst = XDScriptInstruction.decode(word1: word1, word2: word2, codeOffset: 0)

        XCTAssertEqual(inst.opcodeID, .loadImmediate)
        XCTAssertEqual(inst.subOpCode, 1)  // integer type
        XCTAssertEqual(inst.constantValue, 42)
        XCTAssertEqual(inst.wordCount, 2)
    }

    func testDecodeCallStandard() {
        // callStandard classID=35(Character), methodID=10
        let word1: UInt32 = 0x09_23_000A  // opcode 9, subop 0x23=35, param 10
        let inst = XDScriptInstruction.decode(word1: word1, word2: nil, codeOffset: 0)

        XCTAssertEqual(inst.opcodeID, .callStandard)
        XCTAssertEqual(inst.classID, 35)
        XCTAssertEqual(inst.methodID, 10)
        XCTAssertEqual(inst.wordCount, 1)
    }

    func testDecodeJump() {
        // jump to offset 0x100
        let word1: UInt32 = 0x0C_00_0100  // opcode 12, longParam=0x100
        let inst = XDScriptInstruction.decode(word1: word1, word2: nil, codeOffset: 0)

        XCTAssertEqual(inst.opcodeID, .jump)
        XCTAssertEqual(inst.longParameter, 0x100)
    }

    func testInstructionRoundTrip() {
        let word1: UInt32 = 0x02_01_0000
        let word2: UInt32 = 42
        let inst = XDScriptInstruction.decode(word1: word1, word2: word2, codeOffset: 0)
        let encoded = inst.encode()
        XCTAssertEqual(encoded.count, 2)
        XCTAssertEqual(encoded[0], word1)
        XCTAssertEqual(encoded[1], word2)
    }

    /// `GODDESS_XD_SCRIPT_SAMPLE` points at any XD `.scd`; the default is one
    /// from the unpacked US project (the FSYS unpack routes scripts to
    /// `/Assets/Scripts`).
    private static let samplePath = ProcessInfo.processInfo.environment["GODDESS_XD_SCRIPT_SAMPLE"]
        ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/XD project/Build/Unpacked/Assets/Scripts/M2_windmill_1F.scd"

    func testParseRealScript() throws {
        let path = Self.samplePath
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("no XD script sample at \(path)")
        }

        let data = GoDData(data: rawData, byteOrder: .big)
        let script = try XDScript(data: data)

        print("XD Script: \(script.functionCount) functions, \(script.totalInstructionCount) instructions")
        print("Globals: \(script.globalVars.count), Strings: \(script.strings.count)")
        print("Vectors: \(script.vectors.count), Characters: \(script.characterRefs.count)")

        for (i, f) in script.functions.enumerated() {
            print("  Function \(i): \(f.name ?? "?") at code offset \(f.codeOffset)")
        }

        XCTAssertGreaterThan(script.functionCount, 0)
        XCTAssertGreaterThan(script.totalInstructionCount, 0)
    }

    func testDecompileRealScript() throws {
        let path = Self.samplePath
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("no XD script sample at \(path)")
        }

        let data = GoDData(data: rawData, byteOrder: .big)
        let script = try XDScript(data: data)

        let exprBuilder = XDExpressionBuilder()
        let compound = XDExpressionCompound()
        let formatter = XDExprFormatter()

        var output = ""
        for (index, instructions) in script.functionInstructions.enumerated() {
            guard !instructions.isEmpty else { continue }
            let funcName = script.functions[index].name ?? "function_\(index)"
            let (expressions, argCount) = exprBuilder.buildExpressions(instructions: instructions, script: script)
            let compounded = compound.compound(expressions)
            output += formatter.formatFunction(name: funcName, argCount: argCount, body: compounded) + "\n\n"
        }

        print("=== XD Script Decompilation ===")
        print(output)

        XCTAssertFalse(output.isEmpty)
    }
}
