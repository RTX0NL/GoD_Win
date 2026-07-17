//
//  ControlFlowGraphTests.swift
//
//  Exercises CFGBuilder: block splitting at labels / after jumps and
//  terminators, jump-target resolution (conditional false-edge, jumpIfTrue
//  condition negation, unconditional jump), offset→block mapping, the
//  implicit trailing-exit block, and empty input. BlockTerminator is
//  Equatable, so terminators are asserted directly.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class ControlFlowGraphTests: XCTestCase {

    private let builder = CFGBuilder()
    private func global(_ i: Int) -> IRVariable { IRVariable(storage: .global(index: i), valueType: .integer) }
    private var cond: ScriptExpr { .variable(global(0)) }
    private var e0: ScriptStatement { .expression(.callBuiltIn(functionID: 1, args: [], name: nil)) }
    private var e1: ScriptStatement { .expression(.callBuiltIn(functionID: 2, args: [], name: nil)) }

    // MARK: - Basic splitting

    func testEmptyInputProducesNoBlocks() {
        let cfg = builder.build(from: [])
        XCTAssertTrue(cfg.blocks.isEmpty)
        XCTAssertTrue(cfg.offsetToBlockID.isEmpty)
    }

    func testSingleReturnBlock() {
        let cfg = builder.build(from: [e0, .returnVoid])
        XCTAssertEqual(cfg.blocks.count, 1)
        XCTAssertEqual(cfg.blocks[0].statements, [e0])
        XCTAssertEqual(cfg.blocks[0].terminator, .returnVoid)
    }

    func testTrailingBlockWithoutTerminatorBecomesExit() {
        let cfg = builder.build(from: [e0])
        XCTAssertEqual(cfg.blocks.count, 1)
        XCTAssertEqual(cfg.blocks[0].terminator, .exit)
    }

    func testLabelSplitsIntoFallthroughBlocks() {
        let cfg = builder.build(from: [e0, .label(offset: 8), e1, .returnVoid])
        XCTAssertEqual(cfg.blocks.count, 2)
        XCTAssertEqual(cfg.blocks[0].statements, [e0])
        XCTAssertEqual(cfg.blocks[0].terminator, .fallthrough_(nextBlockID: 1))
        XCTAssertEqual(cfg.blocks[1].statements, [e1])
        XCTAssertEqual(cfg.blocks[1].startOffset, 8)
        XCTAssertEqual(cfg.blocks[1].terminator, .returnVoid)
        XCTAssertEqual(cfg.offsetToBlockID[8], 1)
    }

    func testExitTerminator() {
        let cfg = builder.build(from: [e0, .exit])
        XCTAssertEqual(cfg.blocks[0].terminator, .exit)
    }

    func testReturnValueTerminator() {
        let cfg = builder.build(from: [.returnValue(.constant(.integer(1)))])
        XCTAssertEqual(cfg.blocks.count, 1)
        XCTAssertEqual(cfg.blocks[0].terminator, .returnValue(.constant(.integer(1))))
    }

    // MARK: - Jump resolution

    func testConditionalFalseEdgeResolvesToLabelBlock() {
        // jumpIfFalse → falseBlockID should point at the labelled block.
        let cfg = builder.build(from: [
            .jumpIfFalse(condition: cond, target: 0x10),
            e1,
            .label(offset: 0x10),
            .returnVoid,
        ])
        XCTAssertEqual(cfg.blocks.count, 3)
        XCTAssertEqual(cfg.blocks[0].terminator, .conditional(condition: cond, trueBlockID: 1, falseBlockID: 2))
        XCTAssertEqual(cfg.blocks[1].terminator, .fallthrough_(nextBlockID: 2))
        XCTAssertEqual(cfg.blocks[2].terminator, .returnVoid)
    }

    func testJumpIfTrueNegatesCondition() {
        let cfg = builder.build(from: [
            .jumpIfTrue(condition: cond, target: 0x10),
            e1,
            .label(offset: 0x10),
            .returnVoid,
        ])
        XCTAssertEqual(cfg.blocks[0].terminator,
                       .conditional(condition: .unary(.not, cond), trueBlockID: 1, falseBlockID: 2))
    }

    func testUnconditionalJumpResolvesTarget() {
        let cfg = builder.build(from: [
            e0,
            .jump(target: 0x10),
            e1,
            .label(offset: 0x10),
            .returnVoid,
        ])
        // block0 ends in the jump; its target is the labelled block.
        XCTAssertEqual(cfg.blocks[0].statements, [e0])
        if case .jump(let targetID) = cfg.blocks[0].terminator {
            XCTAssertEqual(cfg.blocks[targetID].startOffset, 0x10)
        } else {
            XCTFail("expected jump terminator, got \(cfg.blocks[0].terminator)")
        }
    }

    func testJumpToUnknownOffsetClampsToNextBlock() {
        // Target 0x999 has no label; resolution falls back to blockID+1 (clamped).
        let cfg = builder.build(from: [
            .jump(target: 0x999),
            .returnVoid,
        ])
        if case .jump(let targetID) = cfg.blocks[0].terminator {
            XCTAssertGreaterThanOrEqual(targetID, 0)
            XCTAssertLessThan(targetID, cfg.blocks.count)
        } else {
            XCTFail("expected jump terminator")
        }
    }
}
