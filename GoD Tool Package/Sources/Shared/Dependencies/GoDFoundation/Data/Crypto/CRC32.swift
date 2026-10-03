//
//  CRC32.swift
//  GoDFoundation
//
//  CRC-32 (IEEE 802.3: polynomial 0xEDB88320, init 0xFFFFFFFF, reflected,
//  final XOR 0xFFFFFFFF).
//
//  Here rather than in a game engine for the same reason AES and SHA-1 are:
//  it is a pure byte-level algorithm with no game knowledge. Two callers need
//  it — NKit's disc checksums, and the LZSS header Battle Revolution writes
//  over each entry's uncompressed payload.
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

    /// CRC-32 of a readable, pulled in windows.
    ///
    /// Here rather than at a call site because the alternative is `allData`,
    /// and the sources that need checksumming are exactly the ones that must
    /// not be buffered: a disc image, a patch, a lazily patched view.
    ///
    /// `range` limits it to part of the source — a patch format whose footer
    /// stores the checksum of everything ahead of it needs that.
    ///
    /// A source that fails a read part way through yields a checksum over what
    /// it did produce. That cannot be mistaken for success: the value won't
    /// match whatever it is being compared against, so a broken source
    /// surfaces as a checksum error rather than as silent acceptance.
    public static func compute(
        _ readable: GoDReadable,
        bytes range: Range<Int>? = nil,
        windowSize: Int = 8 << 20
    ) -> UInt32 {
        let window = max(1, windowSize)
        let bounds = range ?? 0 ..< readable.length
        var crc: UInt32 = 0xFFFF_FFFF
        var offset = bounds.lowerBound
        while offset < bounds.upperBound {
            let count = min(window, bounds.upperBound - offset)
            var read = 0
            autoreleasepool {
                guard let chunk = readable.read(atAddress: offset, length: count) else { return }
                crc = update(crc, bytes: chunk.rawBytes)
                read = max(1, chunk.length)
            }
            guard read > 0 else { break }
            offset += read
        }
        return crc ^ 0xFFFF_FFFF
    }
}
