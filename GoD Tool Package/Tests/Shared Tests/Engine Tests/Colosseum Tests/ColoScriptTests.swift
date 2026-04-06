import XCTest
import GoDFoundation
@testable import Colosseum

final class ColoScriptTests: XCTestCase {

    // MARK: - Opcode Encoding/Decoding

    func testDecodeNop() {
        let data = GoDData(byteStream: [0x00], byteOrder: .big)
        let result = ColoScriptOpcode.decode(from: data, at: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, .nop)
        XCTAssertEqual(result?.1, 1)
    }

    func testDecodeExit() {
        let data = GoDData(byteStream: [0x01], byteOrder: .big)
        let result = ColoScriptOpcode.decode(from: data, at: 0)
        XCTAssertEqual(result?.0, .exit)
    }

    func testDecodePushImmediate() {
        // opcode 8, type 2 (int), value 42 (0x0000002A)
        let data = GoDData(byteStream: [0x08, 0x02, 0x00, 0x00, 0x00, 0x2A], byteOrder: .big)
        let result = ColoScriptOpcode.decode(from: data, at: 0)
        XCTAssertNotNil(result)
        if case .pushImmediate(let type, let value) = result?.0 {
            XCTAssertEqual(type, .integer)
            XCTAssertEqual(value, 42)
        } else {
            XCTFail("Expected pushImmediate")
        }
        XCTAssertEqual(result?.1, 6)
    }

    func testDecodeJump() {
        // opcode 6, offset 0x00000100
        let data = GoDData(byteStream: [0x06, 0x00, 0x00, 0x01, 0x00], byteOrder: .big)
        let result = ColoScriptOpcode.decode(from: data, at: 0)
        if case .jump(let offset) = result?.0 {
            XCTAssertEqual(offset, 0x100)
        } else {
            XCTFail("Expected jump")
        }
    }

    func testDecodeCall() {
        // opcode 4, funcID 0x00000005, retCount 1, argCount 3
        let data = GoDData(byteStream: [0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x00, 0x03], byteOrder: .big)
        let result = ColoScriptOpcode.decode(from: data, at: 0)
        if case .call(let funcID, let retCount, let argCount) = result?.0 {
            XCTAssertEqual(funcID, 5)
            XCTAssertEqual(retCount, 1)
            XCTAssertEqual(argCount, 3)
        } else {
            XCTFail("Expected call")
        }
        XCTAssertEqual(result?.1, 9)
    }

    func testOpcodeRoundTrip() {
        let opcodes: [ColoScriptOpcode] = [
            .nop,
            .exit,
            .pushMinus1,
            .returnOp,
            .pushImmediate(type: .integer, value: 42),
            .pushImmediate(type: .float, value: 0x42280000), // 42.0f
            .jump(offset: 0x100),
            .jumpFalse(offset: 0x200),
            .call(functionID: 5, returnCount: 1, argCount: 3),
            .callStandard(returnCount: 0, argCount: 2),
        ]

        for original in opcodes {
            let encoded = original.encode()
            let data = GoDData(byteStream: encoded, byteOrder: .big)
            let decoded = ColoScriptOpcode.decode(from: data, at: 0)
            XCTAssertNotNil(decoded, "Failed to decode \(original)")
            XCTAssertEqual(decoded?.0, original, "Round-trip failed for \(original)")
            XCTAssertEqual(decoded?.1, encoded.count, "Length mismatch for \(original)")
        }
    }

    // MARK: - Variable Decoding

    func testVarDecodeGlobalInt() {
        let v = ColoScriptVar.decode(from: 0x02)  // type 2 = int, no flags
        XCTAssertEqual(v.valueType, .integer)
        XCTAssertTrue(v.isGlobal)
        XCTAssertFalse(v.isLocal)
        XCTAssertFalse(v.isLiteral)
    }

    func testVarDecodeLocalFloat() {
        let v = ColoScriptVar.decode(from: 0x43)  // 0x40 | 0x03 = local float
        XCTAssertEqual(v.valueType, .float)
        XCTAssertTrue(v.isLocal)
        XCTAssertFalse(v.isLiteral)
    }

    func testVarDecodeLiteralInt() {
        let v = ColoScriptVar.decode(from: 0x82)  // 0x80 | 0x02 = literal int
        XCTAssertEqual(v.valueType, .integer)
        XCTAssertTrue(v.isLiteral)
        XCTAssertFalse(v.isLocal)
    }

    // MARK: - Script Parsing

    func testParseMinimalScript() throws {
        // Minimal script: 1 function that just exits
        var bytes = [UInt8]()
        // Header (24 bytes)
        bytes += [0x01, 0x00]  // scriptTypeID = 0x100
        bytes += [0x00, 0x00]  // padding
        bytes += [0x00, 0x01]  // numberOfFunctions = 1
        bytes += [0x00, 0x00]  // unknown
        bytes += [0x00, 0x00, 0x00, 0x00]  // padding
        bytes += [0x00, 0x00, 0x00, 0x1C]  // codeStartPointer1 = 28
        bytes += [0x00, 0x00, 0x00, 0x1C]  // codeStartPointer2 = 28
        bytes += [0x00, 0x00, 0x00, 0x00]  // padding
        // Function table: 1 entry pointing to offset 28
        bytes += [0x00, 0x00, 0x00, 0x1C]  // function 0 → offset 28
        // Bytecode at offset 28: just exit
        bytes += [0x01]  // exit

        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let script = try ColoScript(data: data)

        XCTAssertEqual(script.scriptTypeID, 0x100)
        XCTAssertEqual(script.numberOfFunctions, 1)
        XCTAssertEqual(script.functions.count, 1)
        XCTAssertEqual(script.functions[0].count, 1)
        XCTAssertEqual(script.functions[0][0].opcode, .exit)
    }

    func testDisassembleMinimalScript() throws {
        var bytes = [UInt8]()
        bytes += [0x01, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x01, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x1C]
        bytes += [0x00, 0x00, 0x00, 0x1C]
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x1C]
        bytes += [0x01]

        let data = GoDData(byteStream: bytes, byteOrder: .big)
        let script = try ColoScript(data: data)
        let disasm = ColoScriptDisassembler()
        let output = disasm.disassemble(script)

        XCTAssertTrue(output.contains("function_0"))
        XCTAssertTrue(output.contains("exit"))
    }
}
