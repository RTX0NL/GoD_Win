//
//  StackDecompilerTests.swift
//
//  Drives the stack-based IR → statement decompiler with hand-built
//  IRFunctions, asserting expression-tree reconstruction, statement
//  emission, argument ordering, the builtin-ID-from-stack special case,
//  label insertion at jump targets, and stack-underflow tolerance.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class StackDecompilerTests: XCTestCase {

    private let sut = StackDecompiler()

    private func decompile(_ ops: [IROp]) -> [ScriptStatement] {
        let instructions = ops.enumerated().map { IRInstruction(offset: $0.offset * 4, op: $0.element) }
        return sut.decompile(IRFunction(index: 0, argCount: 0, instructions: instructions))
    }

    private func global(_ i: Int) -> IRVariable { IRVariable(storage: .global(index: i), valueType: .integer) }

    // MARK: - Expression reconstruction

    func testBinaryExpressionRebuild() {
        let stmts = decompile([
            .pushConstant(.integer(1)),
            .pushConstant(.integer(2)),
            .binaryOp(.add),
            .assign(target: global(0), source: IRVariable(storage: .literal, valueType: .integer)),
        ])
        XCTAssertEqual(stmts, [
            .assign(target: global(0), value: .binary(.add, .constant(.integer(1)), .constant(.integer(2)))),
        ])
    }

    func testUnaryExpressionRebuild() {
        let stmts = decompile([
            .pushConstant(.integer(5)),
            .unaryOp(.negate),
            .returnValue,
        ])
        XCTAssertEqual(stmts, [.returnValue(.unary(.negate, .constant(.integer(5))))])
    }

    func testPushLastResultVariable() {
        let stmts = decompile([
            .pushVariable(IRVariable(storage: .lastResult, valueType: .integer)),
            .returnValue,
        ])
        XCTAssertEqual(stmts, [.returnValue(.lastResult)])
    }

    // MARK: - Calls

    func testCallScriptWithReturnPushesOntoStack() {
        let stmts = decompile([
            .callScript(functionIndex: 5, argCount: 0, returnCount: 1),
            .returnValue,
        ])
        XCTAssertEqual(stmts, [.returnValue(.callScript(functionIndex: 5, args: [], name: nil))])
    }

    func testCallScriptWithoutReturnEmitsExpressionStatement() {
        let stmts = decompile([
            .pushConstant(.integer(1)),
            .pushConstant(.integer(2)),
            .callScript(functionIndex: 7, argCount: 2, returnCount: 0),
        ])
        // Args are pushed left-to-right; popArgs reverses so order is preserved.
        XCTAssertEqual(stmts, [
            .expression(.callScript(functionIndex: 7,
                                    args: [.constant(.integer(1)), .constant(.integer(2))],
                                    name: nil)),
        ])
    }

    func testCallBuiltInTakesFunctionIDFromFirstStackArg() {
        let stmts = decompile([
            .pushConstant(.integer(99)),   // function ID immediate
            .pushConstant(.integer(7)),    // actual argument
            .callBuiltIn(functionID: 0, argCount: 2, returnCount: 0),
        ])
        XCTAssertEqual(stmts, [
            .expression(.callBuiltIn(functionID: 99, args: [.constant(.integer(7))], name: nil)),
        ])
    }

    func testCallBuiltInFallsBackToDeclaredIDWhenFirstArgNotConstant() {
        let stmts = decompile([
            .pushVariable(global(3)),
            .callBuiltIn(functionID: 12, argCount: 1, returnCount: 1),
            .returnValue,
        ])
        XCTAssertEqual(stmts, [
            .returnValue(.callBuiltIn(functionID: 12, args: [.variable(global(3))], name: nil)),
        ])
    }

    // MARK: - Simple statements

    func testCopyMemoryYieldPrintfExit() {
        let dest = global(1), source = global(2)
        let stmts = decompile([
            .copyMemory(dest: dest, source: source, length: 16),
            .yield(frames: 3),
            .pushConstant(.string(0)),
            .printf(argCount: 1),
            .exit,
        ])
        XCTAssertEqual(stmts, [
            .copyMemory(dest: dest, source: source, length: 16),
            .yield(frames: 3),
            .expression(.printf(args: [.constant(.string(0))])),
            .exit,
        ])
    }

    func testReturnVoidAndNop() {
        let stmts = decompile([.nop, .returnVoid])
        XCTAssertEqual(stmts, [.returnVoid])   // nop emits nothing
    }

    func testPopDiscardsStackEntries() {
        let stmts = decompile([
            .pushConstant(.integer(1)),
            .pushConstant(.integer(2)),
            .pop(count: 2),
            .returnVoid,
        ])
        XCTAssertEqual(stmts, [.returnVoid])
    }

    // MARK: - Conditional jumps

    func testJumpIfFalseCarriesCondition() {
        let stmts = decompile([
            .pushVariable(global(0)),
            .jumpIfFalse(target: 0x40),
        ])
        XCTAssertEqual(stmts, [.jumpIfFalse(condition: .variable(global(0)), target: 0x40)])
    }

    func testJumpIfTrueCarriesCondition() {
        let stmts = decompile([
            .pushVariable(global(0)),
            .jumpIfTrue(target: 0x40),
        ])
        XCTAssertEqual(stmts, [.jumpIfTrue(condition: .variable(global(0)), target: 0x40)])
    }

    // MARK: - Label insertion

    func testLabelInsertedAtJumpTarget() {
        // jump target 8 lands on the returnVoid instruction (offset 8).
        let instructions = [
            IRInstruction(offset: 0, op: .jump(target: 8)),
            IRInstruction(offset: 4, op: .nop),
            IRInstruction(offset: 8, op: .returnVoid),
        ]
        let stmts = sut.decompile(IRFunction(index: 0, argCount: 0, instructions: instructions))
        XCTAssertEqual(stmts, [
            .jump(target: 8),
            .label(offset: 8),
            .returnVoid,
        ])
    }

    // MARK: - Underflow tolerance

    func testBinaryOpOnEmptyStackUsesVoidConstants() {
        let stmts = decompile([
            .binaryOp(.add),
            .returnValue,
        ])
        XCTAssertEqual(stmts, [.returnValue(.binary(.add, .constant(.void), .constant(.void)))])
    }

    func testPopMoreThanAvailableDoesNotCrash() {
        let stmts = decompile([
            .pushConstant(.integer(1)),
            .pop(count: 5),
            .returnVoid,
        ])
        XCTAssertEqual(stmts, [.returnVoid])
    }
}
