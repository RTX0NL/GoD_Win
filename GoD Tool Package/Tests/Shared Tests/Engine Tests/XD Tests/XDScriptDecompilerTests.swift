//
//  XDScriptDecompilerTests.swift
//
//  XD script (`.scd`) decompilation. The synthetic scripts are assembled
//  word by word, so each test pins one behaviour of the builder, the
//  compounder or the formatter. GODDESS_XD_SCRIPTS points the corpus test
//  at a folder of real `.scd` files (searched recursively).
//

import XCTest
import Foundation
import GoDFoundation
@testable import XD

final class XDScriptDecompilerTests: XCTestCase {

    // MARK: - Assembling a script

    private enum Op {
        static func word(_ opcode: UInt32, _ sub: Int = 0, _ param: Int = 0) -> UInt32 {
            opcode << 24 | UInt32(sub & 0xFF) << 16 | UInt32(UInt16(truncatingIfNeeded: param))
        }
        static func int(_ value: Int32) -> [UInt32] { [word(2, 1), UInt32(bitPattern: value)] }
        static func loadResult() -> [UInt32] { [word(3, 2)] }
        static func loadLocal(_ index: Int) -> [UInt32] { [word(3, 1, index)] }
        static func setLocal(_ index: Int) -> [UInt32] { [word(4, 1, index)] }
        static func setVector(_ dimension: Int, local index: Int) -> [UInt32] { [word(5, dimension << 4 | 1, index)] }
        static func op(_ op: XDScriptOperator) -> [UInt32] { [word(1, op.rawValue)] }
        static func callStandard(_ classID: Int, _ method: Int, args: Int) -> [UInt32] {
            [word(9, classID, method)] + (args > 0 ? [word(6, args)] : [])
        }
        static func call(_ address: Int, args: Int) -> [UInt32] {
            [7 << 24 | UInt32(address)] + (args > 0 ? [word(6, args)] : [])
        }
        static func jumpIfFalse(_ target: Int) -> [UInt32] { [11 << 24 | UInt32(target)] }
        static func jump(_ target: Int) -> [UInt32] { [12 << 24 | UInt32(target)] }
        static func ret() -> [UInt32] { [word(8)] }
    }

    private func bytes(_ word: UInt32) -> [UInt8] {
        [UInt8(word >> 24), UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0xFF), UInt8(word & 0xFF)]
    }

    /// A `.scd` holding `functions`, laid out one after the other in CODE.
    /// Each section is a 0x20-byte header (size at +4, count at +0x10).
    private func script(_ functions: [[UInt32]]) throws -> XDScript {
        func section(_ tag: String, count: Int = 0, body: [UInt8] = []) -> [UInt8] {
            var header = Array(tag.utf8) + bytes(UInt32(0x20 + body.count)) + [UInt8](repeating: 0, count: 8)
            header += bytes(UInt32(count)) + [UInt8](repeating: 0, count: 12)
            return header + body
        }
        var offsets = [Int]()
        var code = [UInt32]()
        for function in functions {
            offsets.append(code.count)
            code += function
        }
        let table = offsets.flatMap { bytes(UInt32($0)) + bytes(0) }
        var out = [UInt8](repeating: 0, count: 0x10)                       // TCOD
        out += section("FTBL", count: functions.count, body: table)
        out += section("HEAD")
        out += section("CODE", body: code.flatMap(bytes))
        out += section("GVAR") + section("STRG") + section("VECT") + section("GIRI") + section("ARRY")
        return try XDScript(data: GoDData(byteStream: out, byteOrder: .big))
    }

    private func decompile(_ functions: [[UInt32]]) throws -> String {
        XDScriptDecompiler().decompile(try script(functions), fileName: "test.scd")
    }

    // MARK: - Statements

    /// A call's value goes to `result`, so a value pushed before the call is
    /// still the operand afterwards: `getFlag(…)` then `if 0x190 <= result`.
    func testACallIsAStatementAndItsValueIsResult() throws {
        let text = try decompile([
            Op.int(0x190) + Op.int(0x3C4) + Op.callStandard(0, 133, args: 1)
                + Op.loadResult() + Op.op(.lessThanEqual) + Op.jumpIfFalse(10)
                + Op.callStandard(0, 129, args: 0)
                + Op.ret(),
        ])
        let getFlag = try XCTUnwrap(text.range(of: "Standard.getFlag(0x3C4)"), text)
        let condition = try XCTUnwrap(text.range(of: "if (0x190 <= result) {"), text)
        XCTAssertLessThan(getFlag.lowerBound, condition.lowerBound, text)
        XCTAssertFalse(text.contains("\n    0x190\n"), "no stray operand:\n\(text)")
    }

    func testStatementsKeepTheirOrderAcrossAJump() throws {
        let text = try decompile([
            Op.int(1) + Op.setLocal(-1) + Op.int(2) + Op.setLocal(-2) + Op.jump(7) + Op.ret(),
        ])
        let first = try XCTUnwrap(text.range(of: "local1 = 1"), text)
        let second = try XCTUnwrap(text.range(of: "local2 = 2"), text)
        XCTAssertLessThan(first.lowerBound, second.lowerBound, text)
    }

    func testAVectorComponentAssignmentIsKept() throws {
        let text = try decompile([Op.int(3) + Op.setVector(1, local: -1) + Op.ret()])
        XCTAssertTrue(text.contains("local1.vy = 3"), text)
    }

    /// A component read prints the way an assignment to one does.
    func testAVectorComponentReadIsPostfix() throws {
        let text = try decompile([Op.loadLocal(-1) + Op.op(.getVZ) + Op.setLocal(-2) + Op.ret()])
        XCTAssertTrue(text.contains("local2 = local1.vz"), text)
    }

    /// Scripts on the disc store empty function names; a call to one prints
    /// under the name the function itself is printed with.
    func testACallToAnUnnamedFunctionUsesItsPrintedName() throws {
        let text = try decompile([Op.call(2, args: 0) + Op.ret(), Op.ret()])
        XCTAssertTrue(text.contains("    function_1()"), text)
        XCTAssertFalse(text.contains("\n    ()"), text)
    }

    // MARK: - Structure

    func testALabelAndAJumpBackToItAreAWhileTrueLoop() throws {
        // 0: call; 1: jump 0
        let text = try decompile([Op.callStandard(43, 1, args: 0) + Op.jump(0) + Op.ret()])
        XCTAssertTrue(text.contains("while true {"), text)
        XCTAssertFalse(text.contains("goto"), text)
    }

    /// `if a { …; goto END }; if b { …; goto END }; …; END:` is an
    /// if / else-if chain.
    func testAChainOfIfsJumpingToOneEndIsAnElseIfChain() throws {
        // 0-2: int, jumpIfFalse 5 | 3: call | 4: jump 13
        // 5-7: int, jumpIfFalse 10 | 8: call | 9: jump 13
        // 10: call | 11-12: int | 13: return
        let text = try decompile([
            Op.int(1) + Op.jumpIfFalse(5) + Op.callStandard(0, 129, args: 0) + Op.jump(13)
                + Op.int(2) + Op.jumpIfFalse(10) + Op.callStandard(0, 130, args: 0) + Op.jump(13)
                + Op.callStandard(0, 131, args: 0) + Op.int(0) + Op.ret(),
        ])
        XCTAssertTrue(text.contains("} else if 2 {"), text)
        XCTAssertTrue(text.contains("} else {"), text)
        XCTAssertFalse(text.contains("goto"), text)
    }

    /// A conditional jump backwards is no `if`; it used to swallow the rest
    /// of the function into one.
    func testABackwardConditionalJumpStaysAGoto() throws {
        // 0: call | 1-2: int | 3: jumpIfFalse 0 | 4: call | 5: return
        let text = try decompile([
            Op.callStandard(0, 129, args: 0) + Op.int(1) + Op.jumpIfFalse(0)
                + Op.callStandard(0, 130, args: 0) + Op.ret(),
        ])
        XCTAssertTrue(text.contains("goto L_0"), text)
        XCTAssertTrue(text.contains("L_0:"), text)
        XCTAssertTrue(text.contains("\n    Standard.setFlagToFalse()"), "after the jump, not inside it:\n\(text)")
    }

    // MARK: - Real scripts

    /// Every call instruction in a function shows up exactly once in the
    /// structured output, so the compounders neither drop nor repeat
    /// statements.
    func testEveryRealScriptDecompilesAndKeepsEveryCall() throws {
        guard let folder = ProcessInfo.processInfo.environment["GODDESS_XD_SCRIPTS"],
              let enumerator = FileManager.default.enumerator(atPath: folder) else {
            throw XCTSkip("Set GODDESS_XD_SCRIPTS to a folder of XD .scd files")
        }
        let files = enumerator.compactMap { $0 as? String }.filter { $0.hasSuffix(".scd") }.sorted()
        XCTAssertFalse(files.isEmpty)
        let builder = XDExpressionBuilder()
        let compound = XDExpressionCompound()
        for path in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(path))
            let script = try XDScript(data: GoDData(byteStream: [UInt8](data), byteOrder: .big))
            for (index, instructions) in script.functionInstructions.enumerated() {
                let calls = instructions.filter { $0.opcodeID == .callStandard || $0.opcodeID == .call }.count
                let tree = compound.compound(builder.buildExpressions(instructions: instructions, script: script).expressions)
                XCTAssertEqual(Self.callCount(tree), calls, "\(path) function \(index)")
            }
            let text = XDScriptDecompiler().decompile(script, fileName: path)
            XCTAssertNil(text.range(of: #"\bClass\d+\.|\.method\d+\("#, options: .regularExpression),
                         "\(path): a class or method without a name")
        }
    }

    private static func callCount(_ exprs: [XDExpr]) -> Int {
        exprs.reduce(0) { total, expr in
            switch expr {
            case .call, .callStandard:
                return total + 1
            case .ifStatement(let branches):
                return total + branches.reduce(0) { $0 + callCount($1.1) }
            case .whileLoop(_, let body):
                return total + callCount(body)
            default:
                return total
            }
        }
    }
}
