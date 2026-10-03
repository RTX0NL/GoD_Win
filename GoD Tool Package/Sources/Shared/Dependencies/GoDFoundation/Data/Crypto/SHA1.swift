import Foundation

/// Pure Swift SHA-1 implementation (FIPS 180-4).
/// Used for Wii disc hash chain verification and ticket signing.
public struct SHA1 {

    public static func hash(_ data: GoDData) -> GoDData {
        let digest = hash(data.rawBytes)
        return GoDData(byteStream: digest.map(Int.init), byteOrder: .big)
    }

    public static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var message = bytes

        // Pre-processing: padding
        let originalLength = UInt64(bytes.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        // Append original length in bits as big-endian 64-bit
        for i in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: originalLength >> i))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        // Process each 512-bit (64-byte) block
        let blockCount = message.count / 64
        for block in 0..<blockCount {
            let blockStart = block * 64

            // Prepare message schedule
            var w = [UInt32](repeating: 0, count: 80)
            for t in 0..<16 {
                let offset = blockStart + t * 4
                w[t] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for t in 16..<80 {
                w[t] = rotateLeft(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], by: 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for t in 0..<80 {
                let f: UInt32
                let k: UInt32

                switch t {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }

                let temp = rotateLeft(a, by: 5) &+ f &+ e &+ k &+ w[t]
                e = d
                d = c
                c = rotateLeft(b, by: 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        // Produce the 20-byte digest
        var digest = [UInt8](repeating: 0, count: 20)
        for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
            digest[i * 4]     = UInt8(truncatingIfNeeded: h >> 24)
            digest[i * 4 + 1] = UInt8(truncatingIfNeeded: h >> 16)
            digest[i * 4 + 2] = UInt8(truncatingIfNeeded: h >> 8)
            digest[i * 4 + 3] = UInt8(truncatingIfNeeded: h)
        }
        return digest
    }

    private static func rotateLeft(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
