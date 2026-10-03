//
//  StructuredASTTests.swift
//
//  Drives CFGStructurer over CFGs produced by CFGBuilder from hand-built
//  statement sequences, covering the if-then, while-loop and if-then-else
//  pattern-matching paths plus the trivial / empty cases. ASTNode is
//  Equatable, so the simpler shapes are asserted directly; the if-else
//  shape is asserted via rendered output (the structurer folds the merge
//  block into the then-branch, which the formatter surfaces).
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class StructuredASTTests: XCTestCase {

    private let builder = CFGBuilder()
    private let structurer = CFGStructurer()
    private let fmt = ASTFormatter(syntax: SwiftScriptSyntax())

    private func global(_ i: Int) -> IRVariable { IRVariable(storage: .global(index: i), valueType: .integer) }
    private var cond: ScriptExpr { .variable(global(0)) }

    private func structure(_ statements: [ScriptStatement]) -> ASTNode {
        structurer.structure(builder.build(from: statements))
    }

    // MARK: - Trivial cases

    func testEmptyCFGStructuresToEmptyBlock() {
        XCTAssertEqual(structurer.structure(builder.build(from: [])), .block([]))
    }

    func testSingleReturnVoid() {
        XCTAssertEqual(structure([.returnVoid]), .returnVoid)
    }

    func testLinearBlockOfStatements() {
        let a = ScriptStatement.assign(target: global(1), value: .constant(.integer(1)))
        let b = ScriptStatement.yield(frames: 2)
        let ast = structure([a, b, .returnVoid])
        XCTAssertEqual(ast, .block([
            .assign(target: global(1), value: .constant(.integer(1))),
            .yield(frames: 2),
            .returnVoid,
        ]))
    }

    // MARK: - if-then

    func testIfThenPattern() {
        let bodyCall = ScriptExpr.callBuiltIn(functionID: 5, args: [], name: nil)
        let ast = structure([
            .jumpIfFalse(condition: cond, target: 0x10),
            .expression(bodyCall),
            .label(offset: 0x10),
            .returnVoid,
        ])
        XCTAssertEqual(ast, .block([
            .ifThen(condition: cond, body: .expression(bodyCall)),
            .returnVoid,
        ]))
    }

    // MARK: - while loop

    func testWhileLoopPattern() {
        let bodyCall = ScriptExpr.callBuiltIn(functionID: 6, args: [], name: nil)
        let ast = structure([
            .label(offset: 0),                              // loop head
            .jumpIfFalse(condition: cond, target: 0x100),   // exit test
            .expression(bodyCall),                          // body
            .jump(target: 0),                               // back-edge
            .label(offset: 0x100),                          // after loop
            .returnVoid,
        ])
        XCTAssertEqual(ast, .block([
            .whileLoop(condition: cond, body: .expression(bodyCall)),
            .returnVoid,
        ]))
    }

    // MARK: - if-then-else

    func testIfThenElsePattern() {
        let thenCall = ScriptExpr.callBuiltIn(functionID: 7, args: [], name: "thenFn")
        let elseCall = ScriptExpr.callBuiltIn(functionID: 8, args: [], name: "elseFn")
        let ast = structure([
            .jumpIfFalse(condition: cond, target: 0x10),   // to else
            .expression(thenCall),
            .jump(target: 0x20),                           // skip else → merge
            .label(offset: 0x10),
            .expression(elseCall),
            .label(offset: 0x20),
            .returnVoid,
        ])
        let rendered = fmt.formatNodeForTest(ast)
        XCTAssertTrue(rendered.contains("if global_0 {"), rendered)
        XCTAssertTrue(rendered.contains("thenFn()"), rendered)
        XCTAssertTrue(rendered.contains("} else {"), rendered)
        XCTAssertTrue(rendered.contains("elseFn()"), rendered)
        if case .ifThenElse = ast {} else {
            XCTFail("expected root ifThenElse, got \(ast)")
        }
    }
}

// Small helper to render a bare ASTNode (formatNode is private, so wrap it
// in a throwaway function to reuse the formatter's rendering).
private extension ASTFormatter {
    func formatNodeForTest(_ node: ASTNode) -> String {
        format(function: ASTFunction(index: 0, name: "f", argCount: 0, body: node))
    }
}
