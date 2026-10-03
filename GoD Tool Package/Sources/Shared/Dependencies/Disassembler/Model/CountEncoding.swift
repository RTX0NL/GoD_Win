import GoDFoundation
import Structs

/// Reading and writing a table's entry count at the width a `count` chunk
/// declares. Big-endian, as every GameCube and Wii module is.
public extension IntegerProperties {

    /// The value `bytes` holds, sign-extended for a signed type. `bytes` must
    /// be exactly `length` long.
    func countValue(of bytes: [UInt8]) -> Int64 {
        var value: UInt64 = 0
        for byte in bytes { value = value << 8 | UInt64(byte) }
        guard isSigned, length < 8 else { return Int64(bitPattern: value) }
        let signBit: UInt64 = 1 << UInt64(length * 8 - 1)
        return value & signBit != 0 ? Int64(bitPattern: value | ~(signBit << 1 &- 1)) : Int64(value)
    }

    /// `count` as `length` big-endian bytes, or nil when it doesn't fit —
    /// a table of 300 rows can't be counted by a `uint8`, and truncating it
    /// would tell the game the table is 44 rows long.
    func countBytes(_ count: Int) -> [UInt8]? {
        // A count is an `Int`, so any 64-bit type (and a `uint` of 63 bits
        // or more) holds every value it can take; computing its maximum
        // would overflow.
        let bits = length * 8
        let valueBits = isSigned ? bits - 1 : bits
        let maximum: Int64 = valueBits >= 63 ? .max : (1 << Int64(valueBits)) - 1
        guard count >= 0, Int64(count) <= maximum else { return nil }
        let value = UInt64(count)
        return (0 ..< length).map { UInt8((value >> UInt64((length - 1 - $0) * 8)) & 0xFF) }
    }
}
