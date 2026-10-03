//
//  VCDIFFInteger.swift
//
//  VCDIFF's integer encoding (RFC 3284 §2), which is *not* the one UPS and BPS
//  use.
//
//  Base 128, most significant digit first, with the high bit set on every byte
//  but the last:
//
//      123456789 → BA EF 9A 15
//
//  So where `PatchVariableLengthInteger` terminates on a *set* high bit and
//  counts up from the low digit, this terminates on a *clear* one and counts
//  down from the high digit. Two formats, two conventions, and nothing shared
//  between them but the idea.
//

import Foundation

enum VCDIFFInteger {

    static func encode(_ value: Int) -> [UInt8] {
        precondition(value >= 0, "VCDIFF integers are unsigned")
        var digits = [UInt8]()
        var remaining = value
        repeat {
            digits.append(UInt8(remaining & 0x7F))
            remaining >>= 7
        } while remaining != 0
        // Most significant first, continuation set on all but the last.
        var bytes = [UInt8]()
        for (index, digit) in digits.reversed().enumerated() {
            bytes.append(index == digits.count - 1 ? digit : digit | 0x80)
        }
        return bytes
    }

    static func encodedLength(of value: Int) -> Int {
        encode(value).count
    }

    /// Decode one integer, taking bytes from `nextByte`.
    ///
    /// Capped at 63 bits: a corrupt stream can otherwise ask for an integer
    /// that never ends, and a size that overflows would wrap into something
    /// plausible.
    static func decode(nextByte: () throws -> UInt8?) throws -> Int {
        var value = 0
        var count = 0
        while true {
            guard let byte = try nextByte() else {
                throw VCDIFFIntegerError.truncated
            }
            count += 1
            guard count <= 9 else { throw VCDIFFIntegerError.overflow }
            let (shifted, overflow) = value.multipliedReportingOverflow(by: 128)
            guard !overflow else { throw VCDIFFIntegerError.overflow }
            value = shifted + Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
    }
}

enum VCDIFFIntegerError: Error, CustomStringConvertible {
    case truncated
    case overflow

    var description: String {
        switch self {
        case .truncated: return "the bytes ended in the middle of an integer"
        case .overflow: return "an integer is too large to address"
        }
    }
}
