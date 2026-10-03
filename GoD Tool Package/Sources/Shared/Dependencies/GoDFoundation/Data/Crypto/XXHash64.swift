//
//  XXHash64.swift
//
//  Yann Collet's XXH64, a fast non-cryptographic hash. Present because a
//  Zstandard frame may carry the low 32 bits of the XXH64 of its content as
//  an integrity check, and a decoder that skipped it would report success
//  on a stream it had silently mis-decoded.
//
//  Sits beside CRC32 rather than with the compression codecs: like CRC32 it
//  is a checksum several formats happen to share, not a codec.
//
//  Reference: Cyan4973/xxHash `doc/xxhash_spec.md`
//

import Foundation

public enum XXHash64 {

    private static let prime1: UInt64 = 11400714785074694791
    private static let prime2: UInt64 = 14029467366897019727
    private static let prime3: UInt64 = 1609587929392839161
    private static let prime4: UInt64 = 9650029242287828579
    private static let prime5: UInt64 = 2870177450012600261

    public static func hash(_ bytes: [UInt8], seed: UInt64 = 0) -> UInt64 {
        hash(bytes[...], seed: seed)
    }

    public static func hash(_ bytes: ArraySlice<UInt8>, seed: UInt64 = 0) -> UInt64 {
        let start = bytes.startIndex
        let end = bytes.endIndex
        let length = bytes.count
        var cursor = start
        var accumulator: UInt64

        if length >= 32 {
            var v1 = seed &+ prime1 &+ prime2
            var v2 = seed &+ prime2
            var v3 = seed
            var v4 = seed &- prime1
            let stripeEnd = end - 32
            while cursor <= stripeEnd {
                v1 = round(v1, readLE64(bytes, cursor))
                v2 = round(v2, readLE64(bytes, cursor + 8))
                v3 = round(v3, readLE64(bytes, cursor + 16))
                v4 = round(v4, readLE64(bytes, cursor + 24))
                cursor += 32
            }
            accumulator = rotl(v1, 1) &+ rotl(v2, 7) &+ rotl(v3, 12) &+ rotl(v4, 18)
            accumulator = mergeRound(accumulator, v1)
            accumulator = mergeRound(accumulator, v2)
            accumulator = mergeRound(accumulator, v3)
            accumulator = mergeRound(accumulator, v4)
        } else {
            accumulator = seed &+ prime5
        }

        accumulator = accumulator &+ UInt64(length)

        while cursor + 8 <= end {
            let k = round(0, readLE64(bytes, cursor))
            accumulator ^= k
            accumulator = rotl(accumulator, 27) &* prime1 &+ prime4
            cursor += 8
        }
        if cursor + 4 <= end {
            accumulator ^= UInt64(readLE32(bytes, cursor)) &* prime1
            accumulator = rotl(accumulator, 23) &* prime2 &+ prime3
            cursor += 4
        }
        while cursor < end {
            accumulator ^= UInt64(bytes[cursor]) &* prime5
            accumulator = rotl(accumulator, 11) &* prime1
            cursor += 1
        }

        accumulator ^= accumulator >> 33
        accumulator = accumulator &* prime2
        accumulator ^= accumulator >> 29
        accumulator = accumulator &* prime3
        accumulator ^= accumulator >> 32
        return accumulator
    }

    // MARK: - Mixing

    @inline(__always)
    private static func round(_ accumulator: UInt64, _ input: UInt64) -> UInt64 {
        var value = accumulator &+ (input &* prime2)
        value = rotl(value, 31)
        return value &* prime1
    }

    @inline(__always)
    private static func mergeRound(_ accumulator: UInt64, _ value: UInt64) -> UInt64 {
        let rounded = round(0, value)
        return ((accumulator ^ rounded) &* prime1) &+ prime4
    }

    @inline(__always)
    private static func rotl(_ value: UInt64, _ count: UInt64) -> UInt64 {
        (value << count) | (value >> (64 - count))
    }

    @inline(__always)
    private static func readLE64(_ bytes: ArraySlice<UInt8>, _ index: Int) -> UInt64 {
        UInt64(bytes[index])
            | UInt64(bytes[index + 1]) << 8
            | UInt64(bytes[index + 2]) << 16
            | UInt64(bytes[index + 3]) << 24
            | UInt64(bytes[index + 4]) << 32
            | UInt64(bytes[index + 5]) << 40
            | UInt64(bytes[index + 6]) << 48
            | UInt64(bytes[index + 7]) << 56
    }

    @inline(__always)
    private static func readLE32(_ bytes: ArraySlice<UInt8>, _ index: Int) -> UInt32 {
        UInt32(bytes[index])
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16
            | UInt32(bytes[index + 3]) << 24
    }
}
