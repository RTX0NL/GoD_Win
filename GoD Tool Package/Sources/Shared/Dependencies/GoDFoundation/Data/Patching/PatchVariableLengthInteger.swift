//
//  PatchVariableLengthInteger.swift
//
//  The variable-width integer UPS and BPS store their sizes, offsets and
//  action lengths as. Both formats are byuu's and both use this encoding
//  unchanged, so it lives apart from either.
//
//  It is *not* LEB128, and the difference is one easily-missed subtraction.
//  byuu's encoder, verbatim:
//
//      loop {
//          x = offset & 0x7f
//          offset >>= 7
//          if (offset == 0) { write(0x80 | x); break; }
//          write(x);
//          offset--;
//      }
//
//  The `offset--` is what makes the encoding canonical — every value has
//  exactly one spelling, because the ranges a given byte count can express
//  are made disjoint rather than overlapping. Decoding has to undo it by
//  adding the running multiplier back on each continuation byte:
//
//      value = 0; shift = 1
//      loop {
//          x = read()
//          value += (x & 0x7f) * shift
//          if (x & 0x80) break
//          shift <<= 7
//          value += shift
//      }
//
//  A plain base-128 decoder reads every multi-byte value short, by an amount
//  that grows with the byte count — so small patches decode fine and large
//  ones go subtly wrong. Hence its own type and its own tests.
//

import Foundation

public enum PatchVariableLengthInteger {

    /// The canonical encoding of `value`.
    public static func encode(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes = [UInt8]()
        while true {
            let x = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining == 0 {
                bytes.append(0x80 | x)
                return bytes
            }
            bytes.append(x)
            remaining -= 1
        }
    }

    /// How many bytes `encode` would produce, without producing them.
    ///
    /// The serializer needs this for every hunk to lay out a patch before
    /// writing a byte of it.
    public static func encodedLength(of value: UInt64) -> Int {
        var remaining = value
        var count = 1
        while true {
            remaining >>= 7
            if remaining == 0 { return count }
            remaining -= 1
            count += 1
        }
    }

    /// Decode one integer, taking bytes from `nextByte` until one has its
    /// high bit set.
    ///
    /// - Throws: `.truncated` when the bytes run out first, `.overflow` when
    ///   the value cannot be held in 64 bits. Neither is reachable from a
    ///   well-formed patch, and both are reachable from a corrupt one.
    public static func decode(nextByte: () throws -> UInt8?) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 1
        while true {
            guard let byte = try nextByte() else {
                throw PatchVariableLengthIntegerError.truncated
            }
            let (scaled, scaleOverflow) = UInt64(byte & 0x7F).multipliedReportingOverflow(by: shift)
            guard !scaleOverflow else { throw PatchVariableLengthIntegerError.overflow }
            let (sum, sumOverflow) = value.addingReportingOverflow(scaled)
            guard !sumOverflow else { throw PatchVariableLengthIntegerError.overflow }
            value = sum
            if byte & 0x80 != 0 { return value }
            let (nextShift, shiftOverflow) = shift.multipliedReportingOverflow(by: 0x80)
            guard !shiftOverflow else { throw PatchVariableLengthIntegerError.overflow }
            shift = nextShift
            let (bumped, bumpOverflow) = value.addingReportingOverflow(shift)
            guard !bumpOverflow else { throw PatchVariableLengthIntegerError.overflow }
            value = bumped
        }
    }
}

public enum PatchVariableLengthIntegerError: Error, CustomStringConvertible {
    case truncated
    case overflow

    public var description: String {
        switch self {
        case .truncated: return "the bytes ended in the middle of a variable-width integer"
        case .overflow: return "a variable-width integer does not fit in 64 bits"
        }
    }
}
