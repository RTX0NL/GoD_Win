//
//  ScriptExpressionTests.swift
//
//  Covers ScriptExpr.summary across every node variant (constants,
//  variables, binary/unary ops, script/builtin calls with and without
//  names, printf) and ScriptStatement equality.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class ScriptExpressionTests: XCTestCase {

    // MARK: - Constant summaries

    func testConstantSummaries() {
        XCTAssertEqual(ScriptExpr.constant(.integer(42)).summary, "42")
        XCTAssertEqual(ScriptExpr.constant(.float(1.5)).summary, "1.5")
        XCTAssertEqual(ScriptExpr.constant(.void).summary, "void")
        XCTAssertEqual(ScriptExpr.constant(.string(7)).summary, "string(7)")
        XCTAssertEqual(ScriptExpr.constant(.unknown(type: 3, rawValue: 0xAB)).summary, "raw(3, 0xab)")
    }

    // MARK: - Variable summaries

    func testVariableSummaries() {
        func summary(_ storage: IRVariable.Storage) -> String {
            ScriptExpr.variable(IRVariable(storage: storage, valueType: .integer)).summary
        }
        XCTAssertEqual(summary(.global(index: 2)), "global_2")
        XCTAssertEqual(summary(.local(index: 5)), "local_5")
        XCTAssertEqual(summary(.literal), "lit")
        XCTAssertEqual(summary(.lastResult), "result")
    }

    func testLastResultSummary() {
        XCTAssertEqual(ScriptExpr.lastResult.summary, "result")
    }

    // MARK: - Operator summaries

    func testBinarySummary() {
        let expr = ScriptExpr.binary(.add, .constant(.integer(1)), .constant(.integer(2)))
        XCTAssertEqual(expr.summary, "(1 + 2)")
    }

    func testUnarySummary() {
        let expr = ScriptExpr.unary(.not, .variable(IRVariable(storage: .global(index: 0), valueType: .integer)))
        XCTAssertEqual(expr.summary, "!global_0")
    }

    func testNestedExpressionSummary() {
        let inner = ScriptExpr.binary(.multiply, .constant(.integer(2)), .constant(.integer(3)))
        let outer = ScriptExpr.binary(.add, .constant(.integer(1)), inner)
        XCTAssertEqual(outer.summary, "(1 + (2 * 3))")
    }

    // MARK: - Call summaries

    func testScriptCallSummaryWithName() {
        let expr = ScriptExpr.callScript(functionIndex: 3, args: [.constant(.integer(1))], name: "myFunc")
        XCTAssertEqual(expr.summary, "myFunc(1)")
    }

    func testScriptCallSummaryWithoutName() {
        let expr = ScriptExpr.callScript(functionIndex: 3, args: [], name: nil)
        XCTAssertEqual(expr.summary, "function_3()")
    }

    func testBuiltInCallSummaryFallsBackToID() {
        let expr = ScriptExpr.callBuiltIn(functionID: 9, args: [.constant(.integer(1)), .constant(.integer(2))], name: nil)
        XCTAssertEqual(expr.summary, "builtin_9(1, 2)")
    }

    func testBuiltInCallSummaryWithName() {
        let expr = ScriptExpr.callBuiltIn(functionID: 9, args: [], name: "wait")
        XCTAssertEqual(expr.summary, "wait()")
    }

    func testPrintfSummary() {
        let expr = ScriptExpr.printf(args: [.constant(.string(0)), .constant(.integer(5))])
        XCTAssertEqual(expr.summary, "printf(string(0), 5)")
    }

    // MARK: - ScriptStatement equality

    func testStatementEquality() {
        let v = IRVariable(storage: .global(index: 1), valueType: .integer)
        XCTAssertEqual(ScriptStatement.assign(target: v, value: .constant(.integer(1))),
                       .assign(target: v, value: .constant(.integer(1))))
        XCTAssertNotEqual(ScriptStatement.returnVoid, .exit)
        XCTAssertEqual(ScriptStatement.yield(frames: 3), .yield(frames: 3))
        XCTAssertNotEqual(ScriptStatement.jump(target: 1), .jump(target: 2))
        XCTAssertEqual(ScriptStatement.label(offset: 0x10), .label(offset: 0x10))
    }
}
