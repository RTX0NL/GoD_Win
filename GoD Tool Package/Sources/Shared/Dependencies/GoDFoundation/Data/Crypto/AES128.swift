import Foundation

/// Pure Swift AES-128-CBC implementation (FIPS 197).
/// Used for Wii disc partition encryption/decryption.
public struct AES128CBC {

    /// Decrypt data using AES-128-CBC. Input length must be a multiple of 16.
    public static func decrypt(data: GoDData, key: [UInt8], iv: [UInt8]) -> GoDData {
        let result = decrypt(bytes: data.rawBytes, key: key, iv: iv)
        return GoDData(byteStream: result.map(Int.init), byteOrder: data.byteOrder)
    }

    /// Encrypt data using AES-128-CBC. Input length must be a multiple of 16.
    public static func encrypt(data: GoDData, key: [UInt8], iv: [UInt8]) -> GoDData {
        let result = encrypt(bytes: data.rawBytes, key: key, iv: iv)
        return GoDData(byteStream: result.map(Int.init), byteOrder: data.byteOrder)
    }

    /// Decrypt raw bytes using AES-128-CBC. No padding is applied or removed.
    public static func decrypt(bytes: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8] {
        precondition(key.count == 16, "AES-128 requires a 16-byte key")
        precondition(iv.count == 16, "AES-128-CBC requires a 16-byte IV")
        precondition(bytes.count % 16 == 0, "Input must be a multiple of 16 bytes")

        let roundKeys = expandKey(key)
        var output = [UInt8](repeating: 0, count: bytes.count)
        var previousBlock = iv

        for blockIndex in stride(from: 0, to: bytes.count, by: 16) {
            let cipherBlock = Array(bytes[blockIndex..<blockIndex + 16])
            var state = cipherBlock
            decryptBlock(&state, roundKeys: roundKeys)
            for i in 0..<16 {
                output[blockIndex + i] = state[i] ^ previousBlock[i]
            }
            previousBlock = cipherBlock
        }

        return output
    }

    /// Encrypt raw bytes using AES-128-CBC. No padding is applied.
    public static func encrypt(bytes: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8] {
        precondition(key.count == 16, "AES-128 requires a 16-byte key")
        precondition(iv.count == 16, "AES-128-CBC requires a 16-byte IV")
        precondition(bytes.count % 16 == 0, "Input must be a multiple of 16 bytes")

        let roundKeys = expandKey(key)
        var output = [UInt8](repeating: 0, count: bytes.count)
        var previousBlock = iv

        for blockIndex in stride(from: 0, to: bytes.count, by: 16) {
            var state = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                state[i] = bytes[blockIndex + i] ^ previousBlock[i]
            }
            encryptBlock(&state, roundKeys: roundKeys)
            for i in 0..<16 {
                output[blockIndex + i] = state[i]
            }
            previousBlock = Array(output[blockIndex..<blockIndex + 16])
        }

        return output
    }

    // MARK: - AES Core

    private static func encryptBlock(_ state: inout [UInt8], roundKeys: [[UInt8]]) {
        addRoundKey(&state, roundKey: roundKeys[0])
        for round in 1..<10 {
            subBytes(&state)
            shiftRows(&state)
            mixColumns(&state)
            addRoundKey(&state, roundKey: roundKeys[round])
        }
        subBytes(&state)
        shiftRows(&state)
        addRoundKey(&state, roundKey: roundKeys[10])
    }

    private static func decryptBlock(_ state: inout [UInt8], roundKeys: [[UInt8]]) {
        addRoundKey(&state, roundKey: roundKeys[10])
        for round in stride(from: 9, through: 1, by: -1) {
            invShiftRows(&state)
            invSubBytes(&state)
            addRoundKey(&state, roundKey: roundKeys[round])
            invMixColumns(&state)
        }
        invShiftRows(&state)
        invSubBytes(&state)
        addRoundKey(&state, roundKey: roundKeys[0])
    }

    // MARK: - Key Expansion

    private static func expandKey(_ key: [UInt8]) -> [[UInt8]] {
        let nk = 4     // Key length in 32-bit words (AES-128)
        let nr = 10    // Number of rounds
        let totalWords = 4 * (nr + 1)

        var w = [[UInt8]](repeating: [0, 0, 0, 0], count: totalWords)

        for i in 0..<nk {
            w[i] = Array(key[4*i..<4*i+4])
        }

        for i in nk..<totalWords {
            var temp = w[i - 1]
            if i % nk == 0 {
                // RotWord
                let t = temp[0]
                temp[0] = temp[1]
                temp[1] = temp[2]
                temp[2] = temp[3]
                temp[3] = t
                // SubWord
                for j in 0..<4 {
                    temp[j] = sbox[Int(temp[j])]
                }
                // XOR with Rcon
                temp[0] ^= rcon[i / nk]
            }
            for j in 0..<4 {
                w[i][j] = w[i - nk][j] ^ temp[j]
            }
        }

        // Group into round keys (16 bytes each)
        var roundKeys = [[UInt8]]()
        for round in 0...nr {
            var roundKey = [UInt8](repeating: 0, count: 16)
            for col in 0..<4 {
                for row in 0..<4 {
                    roundKey[col * 4 + row] = w[round * 4 + col][row]
                }
            }
            roundKeys.append(roundKey)
        }
        return roundKeys
    }

    // MARK: - Round Operations

    private static func addRoundKey(_ state: inout [UInt8], roundKey: [UInt8]) {
        for i in 0..<16 {
            state[i] ^= roundKey[i]
        }
    }

    private static func subBytes(_ state: inout [UInt8]) {
        for i in 0..<16 {
            state[i] = sbox[Int(state[i])]
        }
    }

    private static func invSubBytes(_ state: inout [UInt8]) {
        for i in 0..<16 {
            state[i] = invSbox[Int(state[i])]
        }
    }

    /// State is stored column-major: index = col*4 + row
    private static func shiftRows(_ state: inout [UInt8]) {
        // Row 1: shift left by 1
        let t1 = state[1]
        state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t1
        // Row 2: shift left by 2
        let t20 = state[2]; let t21 = state[6]
        state[2] = state[10]; state[6] = state[14]; state[10] = t20; state[14] = t21
        // Row 3: shift left by 3 (= right by 1)
        let t3 = state[15]
        state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t3
    }

    private static func invShiftRows(_ state: inout [UInt8]) {
        // Row 1: shift right by 1
        let t1 = state[13]
        state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = t1
        // Row 2: shift right by 2
        let t20 = state[2]; let t21 = state[6]
        state[2] = state[10]; state[6] = state[14]; state[10] = t20; state[14] = t21
        // Row 3: shift right by 3 (= left by 1)
        let t3 = state[3]
        state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = t3
    }

    private static func mixColumns(_ state: inout [UInt8]) {
        for col in 0..<4 {
            let i = col * 4
            let s0 = state[i], s1 = state[i+1], s2 = state[i+2], s3 = state[i+3]
            state[i]   = gmul2[Int(s0)] ^ gmul3[Int(s1)] ^ s2 ^ s3
            state[i+1] = s0 ^ gmul2[Int(s1)] ^ gmul3[Int(s2)] ^ s3
            state[i+2] = s0 ^ s1 ^ gmul2[Int(s2)] ^ gmul3[Int(s3)]
            state[i+3] = gmul3[Int(s0)] ^ s1 ^ s2 ^ gmul2[Int(s3)]
        }
    }

    private static func invMixColumns(_ state: inout [UInt8]) {
        for col in 0..<4 {
            let i = col * 4
            let s0 = state[i], s1 = state[i+1], s2 = state[i+2], s3 = state[i+3]
            state[i]   = gmul14[Int(s0)] ^ gmul11[Int(s1)] ^ gmul13[Int(s2)] ^ gmul9[Int(s3)]
            state[i+1] = gmul9[Int(s0)] ^ gmul14[Int(s1)] ^ gmul11[Int(s2)] ^ gmul13[Int(s3)]
            state[i+2] = gmul13[Int(s0)] ^ gmul9[Int(s1)] ^ gmul14[Int(s2)] ^ gmul11[Int(s3)]
            state[i+3] = gmul11[Int(s0)] ^ gmul13[Int(s1)] ^ gmul9[Int(s2)] ^ gmul14[Int(s3)]
        }
    }

    // MARK: - Lookup Tables

    private static let rcon: [UInt8] = [
        0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36
    ]

    private static let sbox: [UInt8] = [
        0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
        0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
        0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
        0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
        0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
        0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
        0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
        0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
        0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
        0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
        0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
        0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
        0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
        0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
        0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
        0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
    ]

    private static let invSbox: [UInt8] = [
        0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
        0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
        0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
        0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
        0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
        0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
        0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
        0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
        0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
        0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
        0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
        0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
        0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
        0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
        0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
        0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D,
    ]

    // GF(2^8) multiplication lookup tables for MixColumns
    private static let gmul2: [UInt8] = (0..<256).map { i -> UInt8 in
        let v = UInt8(i)
        return (v & 0x80 != 0) ? (v << 1) ^ 0x1B : v << 1
    }

    private static let gmul3: [UInt8] = (0..<256).map { i -> UInt8 in
        let v = UInt8(i)
        return gmul2[Int(v)] ^ v
    }

    // Inverse MixColumns tables
    private static let gmul9: [UInt8] = buildGmulTable(9)
    private static let gmul11: [UInt8] = buildGmulTable(11)
    private static let gmul13: [UInt8] = buildGmulTable(13)
    private static let gmul14: [UInt8] = buildGmulTable(14)

    private static func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var a = a
        var b = b
        for _ in 0..<8 {
            if b & 1 != 0 {
                result ^= a
            }
            let highBit = a & 0x80
            a <<= 1
            if highBit != 0 {
                a ^= 0x1B
            }
            b >>= 1
        }
        return result
    }

    private static func buildGmulTable(_ factor: UInt8) -> [UInt8] {
        (0..<256).map { gmul(UInt8($0), factor) }
    }
}
