//
//  NKitChecksum.swift
//
//  CRC-32 (IEEE 802.3, poly 0xEDB88320, init 0xFFFFFFFF, reflected,
//  xorout 0xFFFFFFFF) and the "CRC force" algorithm NKit uses at
//  offset 0x20C of every `.nkit.iso`.
//
//  NKit writes the target CRC (the original disc's CRC) at 0x208 so
//  Redump hashes match without running a restore. But writing that
//  byte changes the file's own CRC. The force trick: pick a 4-byte
//  value to write at 0x20C so that when the whole `.nkit.iso` is
//  CRC'd, the result equals the target CRC. Because CRC is linear
//  in GF(2), this is a constant-time polynomial-math calculation,
//  not a brute-force search.
//
//  This is a faithful port of NKit's `Checksums/CrcForce.cs`, which
//  in turn implements Nayuki's algorithm
//  (https://www.nayuki.io/res/forcing-a-files-crc-to-any-value).
//

import Foundation

public enum CRC32 {

    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    /// Compute CRC-32 of the entire byte sequence.
    public static func compute(_ bytes: [UInt8]) -> UInt32 {
        return update(0xFFFF_FFFF, bytes: bytes) ^ 0xFFFF_FFFF
    }

    /// Incremental update. Pass `0xFFFF_FFFF` as the initial value and
    /// XOR with `0xFFFF_FFFF` on the final read to get the standard
    /// CRC-32.
    public static func update(_ crc: UInt32, bytes: [UInt8]) -> UInt32 {
        var c = crc
        for b in bytes {
            let idx = Int((c ^ UInt32(b)) & 0xFF)
            c = table[idx] ^ (c >> 8)
        }
        return c
    }

    public static func update(_ crc: UInt32, byte: UInt8) -> UInt32 {
        let idx = Int((crc ^ UInt32(byte)) & 0xFF)
        return table[idx] ^ (crc >> 8)
    }
}

// MARK: - CRC Force (Nayuki / NKit)

public enum CRCForce {

    /// CRC-32 polynomial, unreflected, including the implicit x^32
    /// term (33 bits = 0x1_04C1_1DB7).
    private static let POLYNOMIAL: UInt64 = 0x1_04C1_1DB7

    /// Compute the 4-byte value to write into a file at `offset` so
    /// that the file's CRC-32 becomes `newCRC`. The file MUST contain
    /// zeros at `offset..<offset+4` when `currentCRC` is measured —
    /// callers zero the slot first, compute the CRC, then call this.
    /// After writing the returned value at `offset` (big-endian order),
    /// `CRC32.compute(file) == newCRC`.
    ///
    /// This matches NKit's usage pattern (existingOffsetValue = 0).
    /// Faithful port of `CrcForce.Calculate` from Nanook/NKitv1,
    /// which in turn implements Nayuki's CRC-force algorithm.
    public static func calculate(
        currentCRC: UInt32,
        length: UInt64,
        newCRC: UInt32,
        offset: UInt64
    ) -> UInt32 {
        let newCRCr = reverseBits(newCRC)
        let crcR = reverseBits(currentCRC)
        var delta = crcR ^ newCRCr

        // delta * x^{-((length - offset) * 8)}  mod POLYNOMIAL
        //
        // Exponent is the number of bits between the slot's start and
        // the file's end. Nayuki's convention; NKit preserves it.
        let shift = (length &- offset) &* 8
        let reciprocal = reciprocalMod(powMod(2, shift))
        delta = UInt32(truncatingIfNeeded: multiplyMod(reciprocal, UInt64(delta) & 0xFFFF_FFFF))

        // XOR with 0 (existing is zero by convention), then byte-swap
        // for big-endian writing.
        return swapBytes(reverseBits(delta))
    }

    // MARK: - GF(2)[x] polynomial math modulo POLYNOMIAL

    private static func multiplyMod(_ xIn: UInt64, _ yIn: UInt64) -> UInt64 {
        var x = xIn
        var y = yIn
        var z: UInt64 = 0
        while y != 0 {
            z ^= x &* (y & 1)
            y >>= 1
            x <<= 1
            if ((x >> 32) & 1) != 0 {
                x ^= POLYNOMIAL
            }
        }
        return z
    }

    private static func powMod(_ xIn: UInt64, _ yIn: UInt64) -> UInt64 {
        var x = xIn
        var y = yIn
        var z: UInt64 = 1
        while y != 0 {
            if (y & 1) != 0 {
                z = multiplyMod(z, x)
            }
            x = multiplyMod(x, x)
            y >>= 1
        }
        return z
    }

    /// Returns `(quotient, remainder)` of `x / y` over GF(2)[x].
    private static func divideAndRemainder(_ xIn: UInt64, _ y: UInt64) -> (UInt64, UInt64) {
        precondition(y != 0, "Division by zero")
        if xIn == 0 { return (0, 0) }
        var x = xIn
        let ydeg = degree(y)
        var z: UInt64 = 0
        var i = degree(x) - ydeg
        while i >= 0 {
            if ((x >> (i + ydeg)) & 1) != 0 {
                x ^= y << i
                z |= UInt64(1) << i
            }
            i -= 1
        }
        return (z, x)
    }

    /// Modular multiplicative inverse of `xIn` modulo POLYNOMIAL.
    private static func reciprocalMod(_ xIn: UInt64) -> UInt64 {
        var x = POLYNOMIAL
        var y = xIn
        var a: UInt64 = 0
        var b: UInt64 = 1
        while y != 0 {
            let (q, r) = divideAndRemainder(x, y)
            let c = a ^ multiplyMod(q, b)
            x = y
            y = r
            a = b
            b = c
        }
        precondition(x == 1, "Reciprocal does not exist")
        return a
    }

    private static func degree(_ x: UInt64) -> Int {
        guard x != 0 else { return -1 }
        return 63 - leadingZeros(x)
    }

    private static func leadingZeros(_ value: UInt64) -> Int {
        var v = value
        var shifted = 0
        while v != 0 {
            v >>= 1
            shifted += 1
        }
        return 64 - shifted
    }

    // MARK: - Byte/bit fiddling

    private static func reverseBits(_ x: UInt32) -> UInt32 {
        var result: UInt32 = 0
        for i in 0..<32 {
            result = (result << 1) | ((x >> i) & 1)
        }
        return result
    }

    private static func swapBytes(_ x: UInt32) -> UInt32 {
        let h = (x >> 16) | (x << 16)
        return ((h & 0xFF00_FF00) >> 8) | ((h & 0x00FF_00FF) << 8)
    }
}
