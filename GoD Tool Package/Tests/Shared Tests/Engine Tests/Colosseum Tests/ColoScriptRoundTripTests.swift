import XCTest
import GoDFoundation
import ScriptDecompiler
import Structs
@testable import Colosseum

/// Round-trip coverage for the Colosseum script pipeline:
/// binary → instructions → expressions → structures, and back at every layer.
///
/// Layer under test per section:
/// 1. Opcode codec — every opcode, decode(encode(x)) == x and byte lengths
/// 2. File assembly — ColoScript parse → ColoScriptAssembler byte-exact
/// 3. Expression lowering — buildExpressions → ColoExprLowering == input
/// 4. Structure passes — compound → uncompound → lowering == input
/// 5. Full corpus — every real script (skips when the corpus is absent)
final class ColoScriptRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func makeVar(_ mask: UInt8) -> ColoScriptVar { .decode(from: mask) }

    /// The enum set the dump/build operations resolve against — the game
    /// engine's own, which is what `engines` defaults to.
    private var engineEnums: [String: Enum] {
        Dictionary(
            ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Assemble instruction bytes into a minimal single-function script file
    private func makeScript(bytecode: [UInt8], functionCount: Int = 1) throws -> ColoScript {
        var bytes = [UInt8]()
        bytes += [0x01, 0x00]              // scriptTypeID
        bytes += [0x01, 0x01]              // headerField2 (constant in real data)
        bytes += [0x00, UInt8(functionCount)]
        bytes += [0x00, 0x00]              // relocation count
        bytes += [0x00, 0x2A]              // compilerMetadata
        bytes += [0x00, 0x00]              // relocatedFlag
        let codeStart = 24 + functionCount * 4
        bytes += withUnsafeBytes(of: UInt32(codeStart).bigEndian) { Array($0) }  // reloc table (empty)
        bytes += withUnsafeBytes(of: UInt32(codeStart).bigEndian) { Array($0) }  // globals arena (empty)
        bytes += [0x00, 0x00, 0x00, 0x00]  // runtimeNextPointer
        for _ in 0..<functionCount {
            bytes += withUnsafeBytes(of: UInt32(codeStart).bigEndian) { Array($0) }
        }
        bytes += bytecode
        return try ColoScript(data: GoDData(byteStream: bytes, byteOrder: .big))
    }

    /// instructions → expressions → instructions, asserting exact equality
    private func assertExpressionRoundTrip(
        _ opcodes: [ColoScriptOpcode],
        startOffset: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var instructions = [ColoScriptInstruction]()
        var offset = startOffset
        for opcode in opcodes {
            instructions.append(ColoScriptInstruction(offset: offset, opcode: opcode))
            offset += opcode.length
        }
        let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: instructions)
        XCTAssertEqual(try ColoExprLowering().lower(expressions, startOffset: startOffset), instructions,
                       file: file, line: line)
    }

    /// instructions → expressions → compound → uncompound → instructions
    private func assertStructureRoundTrip(
        _ opcodes: [ColoScriptOpcode],
        startOffset: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var instructions = [ColoScriptInstruction]()
        var offset = startOffset
        for opcode in opcodes {
            instructions.append(ColoScriptInstruction(offset: offset, opcode: opcode))
            offset += opcode.length
        }
        let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: instructions)
        let compounded = ColoExpressionCompound().compound(expressions)
        let flattened = ColoExprUncompound().uncompound(compounded)
        XCTAssertEqual(try ColoExprLowering().lower(flattened, startOffset: startOffset), instructions,
                       file: file, line: line)
    }

    // MARK: - 1. Opcode codec: every opcode round-trips byte-exactly

    func testEveryOpcodeEncodesAndDecodesExactly() {
        let intLit = makeVar(0x82), floatLit = makeVar(0x83)
        let intGlobal = makeVar(0x02), floatGlobal = makeVar(0x03)
        let intLocal = makeVar(0x42), voidFlag = makeVar(0x20)

        let allOpcodes: [ColoScriptOpcode] = [
            .nop,                                                             // 0
            .exit,                                                            // 1
            .pushMinus1,                                                      // 2
            .pop(unused: makeVar(0x81), count: 0),                            // 3 (void form)
            .pop(unused: intLit, count: 1),                                   // 3 (int form)
            .call(functionID: 5, returnCount: 1, argCount: 3),                // 4
            .returnOp,                                                        // 5
            .jump(offset: 0x1234),                                            // 6
            .jumpFalse(offset: 0xFFFF),                                       // 7
            .pushImmediate(type: .integer, value: 0xFFFFFFFF),                // 8 (-1)
            .pushImmediate(type: .float, value: Float(42.5).bitPattern),      // 8
            .pushImmediate(type: .void, value: 7),                            // 8
            .bitwiseAnd(var1: intLit, var2: intGlobal),                       // 13
            .bitwiseOr(var1: intGlobal, var2: intLit),                        // 14
            .pushVar(var1: voidFlag),                                         // 15
            .pushMultiVar(var1: intLocal, count: 1),                          // 16
            .pushMultiVar(var1: voidFlag, count: 3),                          // 16 (multi)
            .not(var1: intLit),                                               // 17
            .negate(var1: floatLit),                                          // 18
            .pushVar2(var1: intGlobal),                                       // 19
            .multiply(var1: intLocal, var2: floatLit),                        // 20
            .divide(var1: intLit, var2: intLit),                              // 21
            .mod(var1: intLit, var2: intGlobal),                              // 22
            .add(var1: intGlobal, var2: intLit),                              // 23
            .subtract(var1: intLit, var2: intLocal),                          // 24
            .lessThan(var1: intLit, var2: intGlobal),                         // 25
            .lessThanEqual(var1: intLit, var2: intGlobal),                    // 26
            .greaterThan(var1: intLit, var2: intGlobal),                      // 27
            .greaterThanEqual(var1: intLit, var2: intGlobal),                 // 28
            .equal(var1: intLit, var2: intLit),                               // 29
            .notEqual(var1: intLit, var2: intLit),                            // 30
            .setVar(source: intLit, target: floatGlobal),                     // 31
            .copyStruct(source: intGlobal, dest: intGlobal, length: 0x20),    // 32
            .logicalAnd(var1: intLit, var2: intLit),                          // 33
            .logicalOr(var1: intLit, var2: intLit),                           // 34
            .printf(unused: 0, argCount: 2),                                  // 35
            .yield(unused: 0, argCount: 1),                                   // 36
            .callStandard(returnCount: 1, argCount: 4),                       // 37
            .invalid(id: 9),                                                  // 9-12
            .invalid(id: 10),
            .invalid(id: 11),
            .invalid(id: 12),
            .invalid(id: 200),
        ]

        // Every opcode ID 0…37 must be exercised
        let coveredIDs = Set(allOpcodes.map { $0.opcodeID })
        for id in UInt8(0)...37 {
            XCTAssertTrue(coveredIDs.contains(id), "Opcode ID \(id) not covered")
        }

        for original in allOpcodes {
            let encoded = original.encode()
            XCTAssertEqual(encoded.count, original.length, "Length mismatch for \(original)")
            let data = GoDData(byteStream: encoded, byteOrder: .big)
            guard let (decoded, consumed) = ColoScriptOpcode.decode(from: data, at: 0) else {
                XCTFail("Failed to decode \(original)")
                continue
            }
            XCTAssertEqual(decoded, original, "Decode(encode) mismatch for \(original)")
            XCTAssertEqual(consumed, encoded.count, "Consumed length mismatch for \(original)")
            XCTAssertEqual(decoded.encode(), encoded, "Re-encode mismatch for \(original)")
        }
    }

    func testEveryObservedVarMaskRoundTrips() {
        // Every mask byte observed in the Colosseum US corpus, plus boundaries
        let observedMasks: [UInt8] = [0x02, 0x03, 0x20, 0x42, 0x43, 0x81, 0x82, 0x83, 0xC2]
        for mask in observedMasks + [0x00, 0x1F, 0x60, 0xFF] {
            let variable = ColoScriptVar.decode(from: mask)
            XCTAssertEqual(variable.mask, mask, "Var mask 0x\(String(mask, radix: 16)) did not round-trip")
        }
    }

    // MARK: - 2. File assembly

    func testAssembleMinimalScriptByteExact() throws {
        let script = try makeScript(bytecode: [0x05, 0x01])  // returnOp, exit
        XCTAssertEqual(ColoScriptAssembler.assemble(script).rawBytes, script.rawData.rawBytes)
    }

    func testAssemblePreservesHeaderRelocationsAndGlobals() throws {
        // Mirrors the relocated real files (D1_labo_1F et al.): one relocation
        // entry pointing at a pushImmediate operand that holds the offset of a
        // string at the file tail, plus a two-slot globals arena.
        var bytes = [UInt8]()
        bytes += [0x02, 0x00]              // scriptTypeID
        bytes += [0x01, 0x01]              // headerField2
        bytes += [0x00, 0x02]              // 2 functions
        bytes += [0x00, 0x01]              // 1 relocation
        bytes += [0x01, 0x44]              // compilerMetadata (must survive verbatim)
        bytes += [0x00, 0x00]              // relocatedFlag (0 on disk)
        bytes += [0x00, 0x00, 0x00, 0x20]  // reloc table @0x20
        bytes += [0x00, 0x00, 0x00, 0x24]  // globals arena @0x24 (table end)
        bytes += [0x00, 0x00, 0x00, 0x00]  // runtimeNextPointer
        bytes += [0x00, 0x00, 0x00, 0x2C]  // function 0 → 0x2C
        bytes += [0x00, 0x00, 0x00, 0x00]  // function 1 → null
        bytes += [0x00, 0x00, 0x00, 0x2E]  // reloc: fixup site = imm operand @0x2E
        bytes += [0x00, 0x00, 0x00, 0x00]  // globals arena [0x24..0x2C): 2 slots
        bytes += [0x00, 0x00, 0x00, 0x00]
        // code @0x2C: pushImmediate(int, stringOffset 0x3F); printf; pop; return; exit
        bytes += [0x08, 0x02, 0x00, 0x00, 0x00, 0x3F]  // 0x2C (operand @0x2E)
        bytes += [0x23, 0x00, 0x00, 0x00, 0x01]        // 0x32 printf argc 1
        bytes += [0x03, 0x81, 0x00, 0x00]              // 0x37 pop void
        bytes += [0x05, 0x01]                          // 0x3B return, exit
        bytes += [0x00, 0x00]                          // 0x3D pad
        bytes += Array("hi".utf8) + [0x00]             // 0x3F string data in tail
        let script = try ColoScript(data: GoDData(byteStream: bytes, byteOrder: .big))
        XCTAssertEqual(script.relocationCount, 1)
        XCTAssertEqual(script.relocations, [0x2E])
        XCTAssertTrue(script.isRelocatedOperand(at: 0x2E))
        XCTAssertEqual(script.compilerMetadata, 0x144)
        XCTAssertEqual(script.globalVariableCount, 2)
        XCTAssertEqual(script.functions[1], [], "Null offset must yield an empty function")
        XCTAssertEqual(script.cString(at: 0x3F), "hi")
        XCTAssertEqual(ColoScriptAssembler.assemble(script).rawBytes, bytes)
    }

    func testParseSharedFunctionOffsets() throws {
        // Two table entries pointing at the same bytecode share one run
        var bytes = [UInt8]()
        bytes += [0x01, 0x00, 0x01, 0x01, 0x00, 0x02, 0x00, 0x00]
        bytes += [0x00, 0x2A, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x20]  // function 0 → 0x20
        bytes += [0x00, 0x00, 0x00, 0x20]  // function 1 → 0x20 (duplicate)
        bytes += [0x05, 0x01]

        let script = try ColoScript(data: GoDData(byteStream: bytes, byteOrder: .big))
        XCTAssertEqual(script.codeRuns.count, 1)
        XCTAssertEqual(script.functions[0], script.functions[1])
        XCTAssertEqual(ColoScriptAssembler.assemble(script).rawBytes, bytes)
    }

    // MARK: - 3. Expression lowering, one test per expression type

    private let intLit = ColoScriptVar.decode(from: 0x82)
    private let floatLit = ColoScriptVar.decode(from: 0x83)
    private let voidPop = ColoScriptVar.decode(from: 0x81)
    private let intGlobal = ColoScriptVar.decode(from: 0x02)
    private let floatGlobal = ColoScriptVar.decode(from: 0x03)
    private let intLocal = ColoScriptVar.decode(from: 0x42)

    func testLowerConstants() {
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 42),
            .pushImmediate(type: .integer, value: 0xFFFFFFFF),  // -1 immediate (real corpus form)
            .pushImmediate(type: .float, value: Float(0.6).bitPattern),
            .returnOp,
        ])
    }

    func testLowerVariableReadForms() {
        // pushMultiVar is the default read; pushVar is a distinct rarer form —
        // both must survive the expression layer
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 279),
            .pushMultiVar(var1: intGlobal, count: 1),
            .pushImmediate(type: .integer, value: 280),
            .pushVar(var1: intGlobal),
            .equal(var1: intLit, var2: intLit),
            .jumpFalse(offset: 40),
            .returnOp,
        ])
    }

    func testLowerUnaryOperations() {
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 1),
            .not(var1: intLit),
            .jumpFalse(offset: 20),
            .returnOp,
        ])
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // object ref
            .pushImmediate(type: .integer, value: 0x20),   // function ID
            .pushImmediate(type: .float, value: Float(1.5).bitPattern),
            .negate(var1: floatLit),                       // argument: -1.5
            .callStandard(returnCount: 1, argCount: 2),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerEveryBinaryOperator() {
        let binaryOps: [(ColoScriptVar, ColoScriptVar) -> ColoScriptOpcode] = [
            { .bitwiseAnd(var1: $0, var2: $1) }, { .bitwiseOr(var1: $0, var2: $1) },
            { .multiply(var1: $0, var2: $1) }, { .divide(var1: $0, var2: $1) },
            { .mod(var1: $0, var2: $1) }, { .add(var1: $0, var2: $1) },
            { .subtract(var1: $0, var2: $1) }, { .lessThan(var1: $0, var2: $1) },
            { .lessThanEqual(var1: $0, var2: $1) }, { .greaterThan(var1: $0, var2: $1) },
            { .greaterThanEqual(var1: $0, var2: $1) }, { .equal(var1: $0, var2: $1) },
            { .notEqual(var1: $0, var2: $1) }, { .logicalAnd(var1: $0, var2: $1) },
            { .logicalOr(var1: $0, var2: $1) },
        ]
        for makeOp in binaryOps {
            assertExpressionRoundTrip([
                .pushImmediate(type: .integer, value: 5),   // LHS
                .pushImmediate(type: .integer, value: 3),   // RHS
                makeOp(intLit, intLit),
                .jumpFalse(offset: 100),
                .returnOp,
            ])
        }
    }

    func testLowerAssignmentPopsFollowTargetType() {
        // int target → pop 0x82; float target → pop 0x83
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 279),
            .pushImmediate(type: .integer, value: 1),
            .setVar(source: intLit, target: intGlobal),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 12),
            .pushImmediate(type: .integer, value: 3),
            .setVar(source: intLit, target: floatGlobal),
            .pop(unused: floatLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerScriptCallVoid() {
        // returnCount 0: no return slot, void pop with count 0
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 1),
            .pushMultiVar(var1: intLocal, count: 1),
            .call(functionID: 9, returnCount: 0, argCount: 1),
            .pop(unused: voidPop, count: 0),
            .returnOp,
        ])
    }

    func testLowerScriptCallWithReturnSlot() {
        // returnCount 1: `local0` return slot pushed below the arguments
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // return slot
            .pushImmediate(type: .integer, value: 7),      // argument
            .call(functionID: 18, returnCount: 1, argCount: 1),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerBuiltInCall() {
        // object ref, constant ID, args, callStandard, int pop
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // object ref
            .pushImmediate(type: .integer, value: 0x9D),   // function ID
            .pushImmediate(type: .float, value: Float(0.6).bitPattern),
            .callStandard(returnCount: 1, argCount: 2),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerBuiltInCallWithComputedID() {
        // D4_tower_1F_2 pattern: the builtin ID is a script call's result
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // object ref
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // return slot for call
            .call(functionID: 9, returnCount: 1, argCount: 0),  // → dynamic ID
            .pushImmediate(type: .integer, value: 1),
            .callStandard(returnCount: 1, argCount: 2),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerMultiPushDuplication() {
        // pushMultiVar count 3 feeds three arguments of one call
        let voidFlagGlobal = ColoScriptVar.decode(from: 0x20)
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushMultiVar(var1: intLocal, count: 1),       // object ref
            .pushImmediate(type: .integer, value: 23),     // function ID
            .pushImmediate(type: .integer, value: 4),
            .pushMultiVar(var1: voidFlagGlobal, count: 3), // one push, three values
            .callStandard(returnCount: 1, argCount: 4),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
    }

    func testLowerYieldAndPrintf() {
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 1),
            .yield(unused: 0, argCount: 1),
            .pop(unused: voidPop, count: 0),
            .returnOp,
        ])
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0x1000),  // format string offset
            .pushImmediate(type: .integer, value: 5),
            .printf(unused: 0, argCount: 2),
            .pop(unused: voidPop, count: 0),
            .returnOp,
        ])
    }

    func testLowerReturnValuePattern() {
        // `return 1` = imm 0, value, setVar → local0, pop, returnOp
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushImmediate(type: .integer, value: 1),
            .setVar(source: intLit, target: intLocal),
            .pop(unused: intLit, count: 1),
            .returnOp,
        ])
        // Trailing implicit terminator after a value return (double return)
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 0),
            .pushImmediate(type: .integer, value: 1),
            .setVar(source: intLit, target: intLocal),
            .pop(unused: intLit, count: 1),
            .returnOp,
            .returnOp,
        ])
    }

    func testLowerExitAndStructAssignment() {
        assertExpressionRoundTrip([
            .returnOp,
            .exit,
        ])
        assertExpressionRoundTrip([
            .pushImmediate(type: .integer, value: 1),
            .pushImmediate(type: .integer, value: 2),
            .copyStruct(source: intGlobal, dest: intGlobal, length: 0x10),
            .returnOp,
        ])
    }

    // MARK: - 4. Structure (compound/uncompound) round trips

    func testStructureRoundTripPlainIf() {
        assertStructureRoundTrip([
            .pushImmediate(type: .integer, value: 1),      // 0
            .jumpFalse(offset: 26),                        // 6: over the yield
            .pushImmediate(type: .integer, value: 1),      // 11
            .yield(unused: 0, argCount: 1),                // 17
            .pop(unused: voidPop, count: 0),               // 22
            .returnOp,                                     // 26
        ])
    }

    func testStructureRoundTripDeadConstantIf() {
        // `if 1 { … }` must NOT be mistaken for an else branch
        assertStructureRoundTrip([
            .pushImmediate(type: .integer, value: 1),
            .jumpFalse(offset: 11),
            .returnOp,                                     // offset 11 target = next
        ])
    }

    func testStructureRoundTripIfElse() {
        // if c { yield 1 } else { yield 2 }
        assertStructureRoundTrip([
            .pushImmediate(type: .integer, value: 279),    // 0
            .pushMultiVar(var1: intGlobal, count: 1),      // 6
            .jumpFalse(offset: 35),                        // 10: to else
            .pushImmediate(type: .integer, value: 1),      // 15: then: yield 1
            .yield(unused: 0, argCount: 1),                // 21
            .pop(unused: voidPop, count: 0),               // 26
            .jump(offset: 50),                             // 30: over else
            .pushImmediate(type: .integer, value: 2),      // 35: else: yield 2
            .yield(unused: 0, argCount: 1),                // 41
            .pop(unused: voidPop, count: 0),               // 46
            .returnOp,                                     // 50
        ])
    }

    func testStructureRoundTripWhileLoop() {
        // while gvar5 { yield 1 }
        assertStructureRoundTrip([
            .pushImmediate(type: .integer, value: 5),      // 0: loop top
            .pushMultiVar(var1: intGlobal, count: 1),      // 6
            .jumpFalse(offset: 35),                        // 10: exit loop
            .pushImmediate(type: .integer, value: 1),      // 15
            .yield(unused: 0, argCount: 1),                // 21
            .pop(unused: voidPop, count: 0),               // 26
            .jump(offset: 0),                              // 30: back to top
            .returnOp,                                     // 35
        ])
    }

    func testStructureRoundTripWhileTrueWithLeadingIf() {
        // D2_out pattern: if !c { call } followed by while(1) whose top is the
        // same offset as the if's end — the shared marker must survive both passes
        assertStructureRoundTrip([
            .pushImmediate(type: .integer, value: 1),      // 0
            .not(var1: intLit),                            // 6
            .jumpFalse(offset: 36),                        // 8: if end == while top
            .pushImmediate(type: .integer, value: 1),      // 13
            .pushMultiVar(var1: intLocal, count: 1),       // 19
            .call(functionID: 9, returnCount: 0, argCount: 1),  // 23
            .pop(unused: voidPop, count: 0),               // 32
            .pushImmediate(type: .integer, value: 1),      // 36: while top
            .jumpFalse(offset: 67),                        // 42
            .pushImmediate(type: .integer, value: 1),      // 47
            .yield(unused: 0, argCount: 1),                // 53
            .pop(unused: voidPop, count: 0),               // 58
            .jump(offset: 36),                             // 62
            .returnOp,                                     // 67
        ])
    }

    // MARK: - 5. Full corpus (skips when the project dump is absent)

    func testCorpusRoundTripAllStages() throws {
        let corpusPath = ProcessInfo.processInfo.environment["GODDESS_COLO_SCRIPT_CORPUS"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/Colo US project/Build/Unpacked/Assets/Scripts"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: corpusPath),
              !names.isEmpty else {
            throw XCTSkip("Colosseum script corpus not present")
        }

        var failures = [String]()
        var checked = 0
        for name in names.sorted() where name.hasSuffix(".scd") {
            let raw = try Data(contentsOf: URL(fileURLWithPath: corpusPath).appendingPathComponent(name))
            let script = try ColoScript(data: GoDData(data: raw, byteOrder: .big))
            checked += 1

            // Stage 1: file-level byte-exact reassembly
            if ColoScriptAssembler.assemble(script).rawBytes != [UInt8](raw) {
                failures.append("\(name): stage 1 (reassembly) not byte-exact")
                continue
            }

            // Stages 2+3: expression and structure round trips per code run
            for run in script.codeRuns {
                let (expressions, _) = ColoExpressionBuilder().buildExpressions(instructions: run.instructions)
                if (try? ColoExprLowering().lower(expressions, startOffset: run.start)) != run.instructions {
                    failures.append("\(name): stage 2 (expressions) diverged in run @0x\(String(run.start, radix: 16))")
                    break
                }
                let structured = ColoExpressionCompound().compound(expressions)
                let flattened = ColoExprUncompound().uncompound(structured)
                if (try? ColoExprLowering().lower(flattened, startOffset: run.start)) != run.instructions {
                    failures.append("\(name): stage 3 (structures) diverged in run @0x\(String(run.start, radix: 16))")
                    break
                }
            }

            // Stages 4+5: full source-text round trips (Swift and Python
            // dialects), with the enums the operations resolve — so the
            // corpus is what checks that an `EnumName.case` argument comes
            // back as the value it was rendered from. `GroupID` and
            // `ResourceID` are on 19 of the character builtins, which every
            // map script calls, so this is the only place the enum path gets
            // exercised at scale.
            let builtins = ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [Int: ScriptFunctionDef]()) { result, pair in
                if let id = Int(pair.key) { result[id] = pair.value }
            }
            let emitter = ColoScriptSourceEmitter(builtInFunctions: builtins, enums: engineEnums)
            for syntax in [ColoScriptSourceHeader.Syntax.swift, .python] {
                let text = emitter.decompileToText(script: script, fileName: name, syntax: syntax)
                var parser = ColoScriptTextParser(builtInFunctions: builtins, enums: engineEnums)
                do {
                    let compiled = try ColoScriptCompiler().compile(parser.parse(text)).rawBytes
                    if compiled != [UInt8](raw) {
                        failures.append("\(name): \(syntax) source round trip not byte-exact")
                    }
                } catch {
                    failures.append("\(name): \(syntax) source round trip failed — \(error)")
                }
            }
        }

        XCTAssertGreaterThan(checked, 0)
        XCTAssertEqual(failures, [], "Round-trip failures:\n\(failures.joined(separator: "\n"))")
    }
}
