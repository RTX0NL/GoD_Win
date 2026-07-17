//
//  ASTFormatterTests.swift
//
//  Renders hand-built ASTs through ASTFormatter with both the Swift and
//  Python syntaxes, checking node formatting (assign, expression, if /
//  if-else / while, return, yield, label, goto, memcpy), expression
//  formatting (constants incl. the small-int/hex threshold, variables,
//  ops, calls with builtin-name resolution), and the syntax structs'
//  header/keyword output.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class ASTFormatterTests: XCTestCase {

    private func global(_ i: Int) -> IRVariable { IRVariable(storage: .global(index: i), valueType: .integer) }

    private let swiftFmt = ASTFormatter(syntax: SwiftScriptSyntax(), builtInNames: [3: "wait"])
    private let pyFmt = ASTFormatter(syntax: PythonScriptSyntax(), builtInNames: [3: "wait"])

    // MARK: - Expression formatting

    func testConstantFormatting() {
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.integer(100))), "100")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.integer(-1))), "-1")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.integer(300))), "0x12C")     // > 0xFF → hex
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.integer(-300))), "0xFFFFFED4")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.float(1.5))), "1.5")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.void)), "void")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.string(2))), "string(2)")
        XCTAssertEqual(swiftFmt.formatExpr(.constant(.unknown(type: 1, rawValue: 0xFF))), "raw(1, 0xff)")
    }

    func testVariableFormatting() {
        XCTAssertEqual(swiftFmt.formatExpr(.variable(global(4))), "global_4")
        XCTAssertEqual(swiftFmt.formatExpr(.variable(IRVariable(storage: .local(index: 3), valueType: .integer))), "arg3")
        XCTAssertEqual(swiftFmt.formatExpr(.variable(IRVariable(storage: .local(index: -2), valueType: .integer))), "local_2")
        XCTAssertEqual(swiftFmt.formatExpr(.variable(IRVariable(storage: .literal, valueType: .integer))), "lit")
        XCTAssertEqual(swiftFmt.formatExpr(.variable(IRVariable(storage: .lastResult, valueType: .integer))), "result")
        XCTAssertEqual(swiftFmt.formatExpr(.lastResult), "result")
    }

    func testOperatorAndCallFormatting() {
        XCTAssertEqual(swiftFmt.formatExpr(.binary(.add, .constant(.integer(1)), .constant(.integer(2)))), "(1 + 2)")
        XCTAssertEqual(swiftFmt.formatExpr(.unary(.not, .variable(global(0)))), "!global_0")
        XCTAssertEqual(swiftFmt.formatExpr(.callScript(functionIndex: 5, args: [], name: nil)), "function_5()")
        XCTAssertEqual(swiftFmt.formatExpr(.callScript(functionIndex: 5, args: [.constant(.integer(1))], name: "foo")), "foo(1)")
        // Builtin name resolves through builtInNames when the expr has no explicit name.
        XCTAssertEqual(swiftFmt.formatExpr(.callBuiltIn(functionID: 3, args: [], name: nil)), "wait()")
        XCTAssertEqual(swiftFmt.formatExpr(.callBuiltIn(functionID: 8, args: [], name: nil)), "builtin_8()")
        XCTAssertEqual(swiftFmt.formatExpr(.printf(args: [.constant(.string(0))])), "printf(string(0))")
    }

    // MARK: - Swift node formatting

    func testSwiftFullFunction() {
        let fn = ASTFunction(index: 0, name: "test", argCount: 1, body: .block([
            .assign(target: global(0), value: .constant(.integer(5))),
            .expression(.callBuiltIn(functionID: 3, args: [], name: nil)),
            .copyMemory(dest: global(1), source: global(2), length: 8),
            .ifThen(condition: .variable(global(0)), body: .returnVoid),
            .whileLoop(condition: .variable(global(0)), body: .yield(frames: 2)),
            .returnValue(.constant(.integer(0x1234))),
            .label("L0"),
            .goto_("L0"),
            .nop,
        ]))
        let out = swiftFmt.format(function: fn)
        let lines = out.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "func test(arg0: Int) {")
        XCTAssertEqual(lines.last, "}")
        XCTAssertTrue(out.contains("\n    global_0 = 5\n"), out)
        XCTAssertTrue(out.contains("\n    wait()\n"), out)
        XCTAssertTrue(out.contains("\n    memcpy(global_1, global_2, 8)\n"), out)
        XCTAssertTrue(out.contains("    if global_0 {"), out)
        XCTAssertTrue(out.contains("        return"), out)      // then body indented one deeper
        XCTAssertTrue(out.contains("    while global_0 {"), out)
        XCTAssertTrue(out.contains("        yield(2)"), out)
        XCTAssertTrue(out.contains("    return 0x1234"), out)
        XCTAssertTrue(out.contains("    // L0:"), out)
        XCTAssertTrue(out.contains("    goto L0"), out)
    }

    func testSwiftIfThenElse() {
        let fn = ASTFunction(index: 0, name: "f", argCount: 0, body:
            .ifThenElse(condition: .variable(global(0)),
                        thenBody: .returnValue(.constant(.integer(1))),
                        elseBody: .returnVoid))
        let out = swiftFmt.format(function: fn)
        XCTAssertTrue(out.contains("    if global_0 {"), out)
        XCTAssertTrue(out.contains("    } else {"), out)         // brace style joins close + else
        XCTAssertTrue(out.contains("        return 1"), out)
    }

    // MARK: - Python node formatting

    func testPythonFullFunction() {
        let fn = ASTFunction(index: 0, name: "test", argCount: 2, body: .block([
            .assign(target: global(0), value: .constant(.integer(5))),
            .ifThen(condition: .variable(global(0)), body: .returnVoid),
        ]))
        let out = pyFmt.format(function: fn)
        let lines = out.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "def test(arg0, arg1):")
        XCTAssertFalse(out.contains("}"), "Python output uses indentation, not braces")
        XCTAssertTrue(out.contains("    if global_0:"), out)
        XCTAssertTrue(out.contains("        return"), out)
    }

    func testPythonIfThenElse() {
        let fn = ASTFunction(index: 0, name: "f", argCount: 0, body:
            .ifThenElse(condition: .variable(global(0)),
                        thenBody: .returnValue(.constant(.integer(1))),
                        elseBody: .returnVoid))
        let out = pyFmt.format(function: fn)
        XCTAssertTrue(out.contains("    if global_0:"), out)
        XCTAssertTrue(out.contains("    else:"), out)           // no-brace else on its own line
    }

    // MARK: - Multiple functions

    func testFormatMultipleFunctionsJoined() {
        let a = ASTFunction(index: 0, name: "a", argCount: 0, body: .returnVoid)
        let b = ASTFunction(index: 1, name: "b", argCount: 0, body: .returnVoid)
        let out = swiftFmt.format(functions: [a, b])
        XCTAssertTrue(out.contains("func a() {"), out)
        XCTAssertTrue(out.contains("func b() {"), out)
        XCTAssertTrue(out.contains("}\n\nfunc b"), out)          // blank line between
    }

    // MARK: - Syntax structs directly

    func testSwiftSyntaxKeywords() {
        let s = SwiftScriptSyntax()
        XCTAssertEqual(s.functionHeader(name: "f", args: ["a", "b"]), "func f(a: Int, b: Int) ")
        XCTAssertEqual(s.blockOpen(), "{")
        XCTAssertEqual(s.blockClose(), "}")
        XCTAssertEqual(s.ifHeader(condition: "x"), "if x ")
        XCTAssertEqual(s.elseHeader(), "else ")
        XCTAssertEqual(s.elseIfHeader(condition: "x"), "else if x ")
        XCTAssertEqual(s.whileHeader(condition: "x"), "while x ")
        XCTAssertEqual(s.returnStatement(value: "5"), "return 5")
        XCTAssertEqual(s.returnStatement(value: nil), "return")
        XCTAssertTrue(s.usesBraces)
    }

    func testPythonSyntaxKeywords() {
        let s = PythonScriptSyntax()
        XCTAssertEqual(s.functionHeader(name: "f", args: ["a", "b"]), "def f(a, b)")
        XCTAssertEqual(s.blockOpen(), ":")
        XCTAssertNil(s.blockClose())
        XCTAssertEqual(s.ifHeader(condition: "x"), "if x")
        XCTAssertEqual(s.elseHeader(), "else")
        XCTAssertEqual(s.elseIfHeader(condition: "x"), "elif x")
        XCTAssertEqual(s.whileHeader(condition: "x"), "while x")
        XCTAssertEqual(s.returnStatement(value: "5"), "return 5")
        XCTAssertEqual(s.returnStatement(value: nil), "return")
        XCTAssertFalse(s.usesBraces)
    }
}
