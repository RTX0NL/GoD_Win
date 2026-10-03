//
//  Adler32.swift
//  GoDFoundation
//
//  Adler-32 (RFC 1950 §9): two 16-bit sums modulo 65521, packed high-sum-first.
//
//  Here for one caller, the same way CRC-32 arrived for two: xdelta3 stamps
//  each window of a VCDIFF patch with the Adler-32 of the bytes it decodes to,
//  which is a free check that our decode of somebody else's patch is right.
//

import Foundation

public enum Adler32 {

    private static let modulus: UInt32 = 65521

    public static func compute(_ bytes: [UInt8]) -> UInt32 {
        var low: UInt32 = 1
        var high: UInt32 = 0
        // 5552 is the most bytes that can be summed before the 32-bit high sum
        // can overflow, so the modulo is taken per block rather than per byte.
        var index = 0
        while index < bytes.count {
            let end = min(index + 5552, bytes.count)
            for cursor in index ..< end {
                low += UInt32(bytes[cursor])
                high += low
            }
            low %= modulus
            high %= modulus
            index = end
        }
        return (high << 16) | low
    }
}
