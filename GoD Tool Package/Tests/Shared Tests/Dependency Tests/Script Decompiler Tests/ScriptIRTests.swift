//
//  ScriptIRTests.swift
//
//  Pure-value coverage for the IR layer: IROp classification helpers
//  (isTerminator / jumpTarget / isConditionalJump), IRInstruction /
//  IRVariable / IRFunction / IRScript construction and equality, and the
//  operator raw values.
//

import XCTest
import GoDFoundation
@testable import ScriptDecompiler

final class ScriptIRTests: XCTestCase {

    // MARK: - IROp.isTerminator

    func testTerminators() {
        let terminators: [IROp] = [
            .jump(target: 0), .jumpIfFalse(target: 0), .jumpIfTrue(target: 0),
            .returnVoid, .returnValue, .exit,
        ]
        for op in terminators {
            XCTAssertTrue(op.isTerminator, "\(op) should terminate a block")
        }
    }

    func testNonTerminators() {
        let nonTerminators: [IROp] = [
            .pushConstant(.void), .pushVariable(IRVariable(storage: .literal, valueType: .integer)),
            .pop(count: 1), .binaryOp(.add), .unaryOp(.not),
            .callScript(functionIndex: 0, argCount: 0, returnCount: 0),
            .yield(frames: 1), .printf(argCount: 0), .nop,
        ]
        for op in nonTerminators {
            XCTAssertFalse(op.isTerminator, "\(op) should not terminate a block")
        }
    }

    // MARK: - IROp.jumpTarget / isConditionalJump

    func testJumpTargets() {
        XCTAssertEqual(IROp.jump(target: 0x40).jumpTarget, 0x40)
        XCTAssertEqual(IROp.jumpIfFalse(target: 0x08).jumpTarget, 0x08)
        XCTAssertEqual(IROp.jumpIfTrue(target: 0x0C).jumpTarget, 0x0C)
        XCTAssertNil(IROp.nop.jumpTarget)
        XCTAssertNil(IROp.returnVoid.jumpTarget)
    }

    func testIsConditionalJump() {
        XCTAssertTrue(IROp.jumpIfFalse(target: 0).isConditionalJump)
        XCTAssertTrue(IROp.jumpIfTrue(target: 0).isConditionalJump)
        XCTAssertFalse(IROp.jump(target: 0).isConditionalJump)
        XCTAssertFalse(IROp.nop.isConditionalJump)
    }

    // MARK: - Construction & equality

    func testInstructionStoresFields() {
        let inst = IRInstruction(offset: 0x10, op: .nop)
        XCTAssertEqual(inst.offset, 0x10)
        XCTAssertEqual(inst.op, .nop)
    }

    func testIROpEquality() {
        XCTAssertEqual(IROp.pushConstant(.integer(5)), .pushConstant(.integer(5)))
        XCTAssertNotEqual(IROp.pushConstant(.integer(5)), .pushConstant(.integer(6)))
        XCTAssertNotEqual(IROp.jump(target: 1), .jump(target: 2))
    }

    func testIRConstantEquality() {
        XCTAssertEqual(IRConstant.float(1.5), .float(1.5))
        XCTAssertEqual(IRConstant.string(3), .string(3))
        XCTAssertEqual(IRConstant.unknown(type: 1, rawValue: 0xFF), .unknown(type: 1, rawValue: 0xFF))
        XCTAssertNotEqual(IRConstant.void, .integer(0))
    }

    func testIRVariableStoresStorageAndType() {
        let v = IRVariable(storage: .global(index: 4), valueType: .float)
        XCTAssertEqual(v.storage, .global(index: 4))
        XCTAssertEqual(v.valueType, .float)
        XCTAssertNotEqual(v, IRVariable(storage: .local(index: 4), valueType: .float))
    }

    func testIRValueTypeEquality() {
        XCTAssertEqual(IRValueType.unknown(id: 2), .unknown(id: 2))
        XCTAssertNotEqual(IRValueType.unknown(id: 2), .unknown(id: 3))
        XCTAssertNotEqual(IRValueType.integer, .float)
    }

    func testFunctionAndScriptConstruction() {
        let fn = IRFunction(index: 2, argCount: 1,
                            instructions: [IRInstruction(offset: 0, op: .returnVoid)],
                            name: "doThing")
        XCTAssertEqual(fn.index, 2)
        XCTAssertEqual(fn.argCount, 1)
        XCTAssertEqual(fn.name, "doThing")
        XCTAssertEqual(fn.instructions.count, 1)

        let script = IRScript(functions: [fn])
        XCTAssertEqual(script.functions.count, 1)
        XCTAssertNil(IRFunction(index: 0, argCount: 0, instructions: []).name)
    }

    // MARK: - Operator raw values

    func testBinaryOperatorRawValues() {
        XCTAssertEqual(IRBinaryOperator.add.rawValue, "+")
        XCTAssertEqual(IRBinaryOperator.logicalAnd.rawValue, "&&")
        XCTAssertEqual(IRBinaryOperator.greaterThanEqual.rawValue, ">=")
        XCTAssertEqual(IRBinaryOperator.notEqual.rawValue, "!=")
    }

    func testUnaryOperatorRawValues() {
        XCTAssertEqual(IRUnaryOperator.not.rawValue, "!")
        XCTAssertEqual(IRUnaryOperator.negate.rawValue, "-")
    }
}
