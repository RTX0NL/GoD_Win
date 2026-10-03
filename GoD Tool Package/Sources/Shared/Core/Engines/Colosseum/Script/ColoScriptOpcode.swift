import GoDFoundation

/// Colosseum script opcodes (38 total, byte-encoded, variable-length instructions)
public enum ColoScriptOpcode: Equatable {
    case nop                                                          // 0, 1 byte
    case exit                                                         // 1, 1 byte
    case pushMinus1                                                   // 2, 1 byte
    case pop(unused: ColoScriptVar, count: UInt16)                    // 3, 4 bytes
    case call(functionID: UInt32, returnCount: UInt16, argCount: UInt16) // 4, 9 bytes
    case returnOp                                                     // 5, 1 byte
    case jump(offset: UInt32)                                         // 6, 5 bytes
    case jumpFalse(offset: UInt32)                                    // 7, 5 bytes
    case pushImmediate(type: ColoValueType, value: UInt32)            // 8, 6 bytes
    // 9-12 invalid
    case bitwiseAnd(var1: ColoScriptVar, var2: ColoScriptVar)         // 13, 3 bytes
    case bitwiseOr(var1: ColoScriptVar, var2: ColoScriptVar)          // 14, 3 bytes
    case pushVar(var1: ColoScriptVar)                                 // 15, 2 bytes
    case pushMultiVar(var1: ColoScriptVar, count: UInt16)             // 16, 4 bytes
    case not(var1: ColoScriptVar)                                     // 17, 2 bytes
    case negate(var1: ColoScriptVar)                                  // 18, 2 bytes
    case pushVar2(var1: ColoScriptVar)                                // 19, 2 bytes
    case multiply(var1: ColoScriptVar, var2: ColoScriptVar)           // 20, 3 bytes
    case divide(var1: ColoScriptVar, var2: ColoScriptVar)             // 21, 3 bytes
    case mod(var1: ColoScriptVar, var2: ColoScriptVar)                // 22, 3 bytes
    case add(var1: ColoScriptVar, var2: ColoScriptVar)                // 23, 3 bytes
    case subtract(var1: ColoScriptVar, var2: ColoScriptVar)           // 24, 3 bytes
    case lessThan(var1: ColoScriptVar, var2: ColoScriptVar)           // 25, 3 bytes
    case lessThanEqual(var1: ColoScriptVar, var2: ColoScriptVar)      // 26, 3 bytes
    case greaterThan(var1: ColoScriptVar, var2: ColoScriptVar)        // 27, 3 bytes
    case greaterThanEqual(var1: ColoScriptVar, var2: ColoScriptVar)   // 28, 3 bytes
    case equal(var1: ColoScriptVar, var2: ColoScriptVar)              // 29, 3 bytes
    case notEqual(var1: ColoScriptVar, var2: ColoScriptVar)           // 30, 3 bytes
    case setVar(source: ColoScriptVar, target: ColoScriptVar)         // 31, 3 bytes
    case copyStruct(source: ColoScriptVar, dest: ColoScriptVar, length: UInt16) // 32, 5 bytes
    case logicalAnd(var1: ColoScriptVar, var2: ColoScriptVar)         // 33, 3 bytes
    case logicalOr(var1: ColoScriptVar, var2: ColoScriptVar)          // 34, 3 bytes
    case printf(unused: UInt16, argCount: UInt16)                     // 35, 5 bytes
    case yield(unused: UInt16, argCount: UInt16)                      // 36, 5 bytes
    case callStandard(returnCount: UInt16, argCount: UInt16)          // 37, 5 bytes
    case invalid(id: UInt8)                                           // ?, 1 byte

    public var opcodeID: UInt8 {
        switch self {
        case .nop: return 0
        case .exit: return 1
        case .pushMinus1: return 2
        case .pop: return 3
        case .call: return 4
        case .returnOp: return 5
        case .jump: return 6
        case .jumpFalse: return 7
        case .pushImmediate: return 8
        case .bitwiseAnd: return 13
        case .bitwiseOr: return 14
        case .pushVar: return 15
        case .pushMultiVar: return 16
        case .not: return 17
        case .negate: return 18
        case .pushVar2: return 19
        case .multiply: return 20
        case .divide: return 21
        case .mod: return 22
        case .add: return 23
        case .subtract: return 24
        case .lessThan: return 25
        case .lessThanEqual: return 26
        case .greaterThan: return 27
        case .greaterThanEqual: return 28
        case .equal: return 29
        case .notEqual: return 30
        case .setVar: return 31
        case .copyStruct: return 32
        case .logicalAnd: return 33
        case .logicalOr: return 34
        case .printf: return 35
        case .yield: return 36
        case .callStandard: return 37
        case .invalid(let id): return id
        }
    }

    public var length: Int {
        switch self {
        case .nop, .exit, .pushMinus1, .returnOp: return 1
        case .invalid: return 1
        case .pushVar, .not, .negate, .pushVar2: return 2
        case .bitwiseAnd, .bitwiseOr, .multiply, .divide, .mod,
             .add, .subtract, .lessThan, .lessThanEqual,
             .greaterThan, .greaterThanEqual, .equal, .notEqual,
             .setVar, .logicalAnd, .logicalOr: return 3
        case .pop, .pushMultiVar: return 4
        case .jump, .jumpFalse, .copyStruct, .printf, .yield, .callStandard: return 5
        case .pushImmediate: return 6
        case .call: return 9
        }
    }

    /// Decode an instruction from binary data at the given offset.
    /// Returns the decoded opcode and number of bytes consumed.
    public static func decode(from data: GoDData, at offset: Int) -> (ColoScriptOpcode, Int)? {
        guard offset < data.length else { return nil }
        let opcode: UInt8 = data.readSafely(atAddress: offset)

        func readVar(_ off: Int) -> ColoScriptVar {
            let byte: UInt8 = data.readSafely(atAddress: off)
            return .decode(from: byte)
        }
        func readU16(_ off: Int) -> UInt16 { data.readSafely(atAddress: off) }
        func readU32(_ off: Int) -> UInt32 { data.readSafely(atAddress: off) }

        switch opcode {
        case 0: return (.nop, 1)
        case 1: return (.exit, 1)
        case 2: return (.pushMinus1, 1)
        case 3: return (.pop(unused: readVar(offset + 1), count: readU16(offset + 2)), 4)
        case 4: return (.call(functionID: readU32(offset + 1), returnCount: readU16(offset + 5), argCount: readU16(offset + 7)), 9)
        case 5: return (.returnOp, 1)
        case 6: return (.jump(offset: readU32(offset + 1)), 5)
        case 7: return (.jumpFalse(offset: readU32(offset + 1)), 5)
        case 8:
            let typeByte: UInt8 = data.readSafely(atAddress: offset + 1)
            let value = readU32(offset + 2)
            return (.pushImmediate(type: .from(id: Int(typeByte)), value: value), 6)
        case 9, 10, 11, 12:
            return (.invalid(id: opcode), 1)
        case 13: return (.bitwiseAnd(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 14: return (.bitwiseOr(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 15: return (.pushVar(var1: readVar(offset + 1)), 2)
        case 16: return (.pushMultiVar(var1: readVar(offset + 1), count: readU16(offset + 2)), 4)
        case 17: return (.not(var1: readVar(offset + 1)), 2)
        case 18: return (.negate(var1: readVar(offset + 1)), 2)
        case 19: return (.pushVar2(var1: readVar(offset + 1)), 2)
        case 20: return (.multiply(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 21: return (.divide(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 22: return (.mod(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 23: return (.add(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 24: return (.subtract(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 25: return (.lessThan(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 26: return (.lessThanEqual(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 27: return (.greaterThan(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 28: return (.greaterThanEqual(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 29: return (.equal(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 30: return (.notEqual(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 31: return (.setVar(source: readVar(offset + 1), target: readVar(offset + 2)), 3)
        case 32: return (.copyStruct(source: readVar(offset + 1), dest: readVar(offset + 2), length: readU16(offset + 3)), 5)
        case 33: return (.logicalAnd(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 34: return (.logicalOr(var1: readVar(offset + 1), var2: readVar(offset + 2)), 3)
        case 35: return (.printf(unused: readU16(offset + 1), argCount: readU16(offset + 3)), 5)
        case 36: return (.yield(unused: readU16(offset + 1), argCount: readU16(offset + 3)), 5)
        case 37: return (.callStandard(returnCount: readU16(offset + 1), argCount: readU16(offset + 3)), 5)
        default: return (.invalid(id: opcode), 1)
        }
    }

    public func encode() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.append(opcodeID)

        switch self {
        case .nop, .exit, .pushMinus1, .returnOp, .invalid:
            break
        case .pop(let unused, let count):
            bytes.append(unused.mask)
            bytes.append(UInt8(count >> 8))
            bytes.append(UInt8(count & 0xFF))
        case .call(let funcID, let retCount, let argCount):
            bytes += withUnsafeBytes(of: funcID.bigEndian) { Array($0) }
            bytes += withUnsafeBytes(of: retCount.bigEndian) { Array($0) }
            bytes += withUnsafeBytes(of: argCount.bigEndian) { Array($0) }
        case .jump(let off), .jumpFalse(let off):
            bytes += withUnsafeBytes(of: off.bigEndian) { Array($0) }
        case .pushImmediate(let type, let value):
            bytes.append(UInt8(type.id))
            bytes += withUnsafeBytes(of: value.bigEndian) { Array($0) }
        case .pushVar(let v), .not(let v), .negate(let v), .pushVar2(let v):
            bytes.append(v.mask)
        case .pushMultiVar(let v, let count):
            bytes.append(v.mask)
            bytes += withUnsafeBytes(of: count.bigEndian) { Array($0) }
        case .bitwiseAnd(let v1, let v2), .bitwiseOr(let v1, let v2),
             .multiply(let v1, let v2), .divide(let v1, let v2), .mod(let v1, let v2),
             .add(let v1, let v2), .subtract(let v1, let v2),
             .lessThan(let v1, let v2), .lessThanEqual(let v1, let v2),
             .greaterThan(let v1, let v2), .greaterThanEqual(let v1, let v2),
             .equal(let v1, let v2), .notEqual(let v1, let v2),
             .setVar(let v1, let v2), .logicalAnd(let v1, let v2), .logicalOr(let v1, let v2):
            bytes.append(v1.mask)
            bytes.append(v2.mask)
        case .copyStruct(let src, let dst, let len):
            bytes.append(src.mask)
            bytes.append(dst.mask)
            bytes += withUnsafeBytes(of: len.bigEndian) { Array($0) }
        case .printf(let unused, let argc), .yield(let unused, let argc):
            bytes += withUnsafeBytes(of: unused.bigEndian) { Array($0) }
            bytes += withUnsafeBytes(of: argc.bigEndian) { Array($0) }
        case .callStandard(let retCount, let argc):
            bytes += withUnsafeBytes(of: retCount.bigEndian) { Array($0) }
            bytes += withUnsafeBytes(of: argc.bigEndian) { Array($0) }
        }

        return bytes
    }
}
