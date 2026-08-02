//
//  RVZPacking.swift
//
//  RVZ's lossless "packing" pass: a preprocessor that sits between the
//  disc data and the Zstd/LZMA/bzip2 compressor. Nintendo junk on GC/
//  Wii discs comes from a deterministic PRNG (a Lagged Fibonacci
//  Generator) that RVZ can reproduce given a 68-byte seed; the
//  packing layer replaces long junk runs with `(size | MSB_flag) +
//  seed` markers so the compressor doesn't have to actually represent
//  them.
//
//  Wire format:
//
//    repeat until end-of-stream:
//        size = read_u32_be()
//        if (size & 0x80000000) == 0:
//            literal: read `size` bytes, output verbatim
//        else:
//            packed:  size &= 0x7FFFFFFF
//                     read 68 bytes of seed, generate `size` bytes
//                     from the PRNG
//
//  Reference:
//    dolphin-emu/dolphin `docs/WiaAndRvz.md`
//    Documentation/File Formats/Shared/RVZ - Dolphin Disc Image.md
//
//  The PRNG mixing step + byte-extraction happen to match NKit's
//  `JunkStream` exactly (same j=32, k=521 LFG, same `>> 24 / >> 18 /
//  >> 8 / raw` byte layout). Only the seeding differs: RVZ takes the
//  17 initial state words directly from an inline 68-byte seed, while
//  JunkStream derives them from (gameID, disc, blockIndex).
//

import Foundation

public enum RVZPacking {

    // MARK: - PRNG

    public struct PRNG {
        private var buffer: [UInt32]     // 521 state words
        private var wordCursor: Int      // next word to emit
        /// Bytes already consumed from the current word (0..<4). Tracks
        /// partial-word state across `read` calls so a caller can pull
        /// odd-sized chunks and the stream stays consistent.
        private var byteCursor: Int = 0
        private var initialized = false

        /// Seed must be exactly 68 bytes (17 big-endian UInt32 words).
        public init(seed: [UInt8]) {
            precondition(seed.count == 68, "RVZ packing seed must be 68 bytes (17 × UInt32 BE)")
            var buf = [UInt32](repeating: 0, count: 521)
            for i in 0..<17 {
                let base = i * 4
                buf[i] = (UInt32(seed[base]) << 24)
                    | (UInt32(seed[base + 1]) << 16)
                    | (UInt32(seed[base + 2]) << 8)
                    | UInt32(seed[base + 3])
            }
            // Extend to 521 words via the LFG recurrence.
            for i in 17..<521 {
                buf[i] = (buf[i - 17] &<< 23) ^ (buf[i - 16] >> 9) ^ buf[i - 1]
            }
            self.buffer = buf
            self.wordCursor = 0
        }

        /// Advance the LFG state by one cycle (XOR each word with its
        /// mate 32 positions ahead/behind). Called 4 times at init and
        /// once after every 521 emitted words.
        private mutating func mix() {
            // First 32 words pair with buffer[i + 521 - 32] = buffer[i + 489].
            for i in 0..<32 {
                buffer[i] ^= buffer[i + 489]
            }
            // Remaining words pair with buffer[i - 32].
            for i in 32..<521 {
                buffer[i] ^= buffer[i - 32]
            }
        }

        /// Produce `count` PRNG bytes. Safe to call with odd sizes —
        /// partial-word state is preserved between calls.
        public mutating func read(_ count: Int) -> [UInt8] {
            if !initialized {
                for _ in 0..<4 { mix() }
                initialized = true
                wordCursor = 0
                byteCursor = 0
            }
            var out = [UInt8]()
            out.reserveCapacity(count)
            var remaining = count
            while remaining > 0 {
                if wordCursor >= 521 {
                    mix()
                    wordCursor = 0
                    byteCursor = 0
                }
                let w = buffer[wordCursor]
                // Extract 4 bytes from the current word. Non-standard
                // `>> 18` for byte 1 — same as NKit JunkStream.
                let bytesOfWord: [UInt8] = [
                    UInt8(truncatingIfNeeded: w >> 24),
                    UInt8(truncatingIfNeeded: w >> 18),
                    UInt8(truncatingIfNeeded: w >> 8),
                    UInt8(truncatingIfNeeded: w),
                ]
                while byteCursor < 4 && remaining > 0 {
                    out.append(bytesOfWord[byteCursor])
                    byteCursor += 1
                    remaining -= 1
                }
                if byteCursor >= 4 {
                    byteCursor = 0
                    wordCursor += 1
                }
            }
            return out
        }
    }

    // MARK: - Stream model

    /// One segment of a packed stream. Either literal bytes or a PRNG
    /// run produced from a 68-byte seed.
    public enum Segment: Equatable {
        case literal(bytes: [UInt8])
        case packed(size: UInt32, seed: [UInt8])

        public var expandedByteLength: Int {
            switch self {
            case .literal(let b): return b.count
            case .packed(let s, _): return Int(s)
            }
        }
    }

    // MARK: - Decode

    /// Parse `bytes` as a packed stream and return the decoded
    /// segments. Stops when the cursor reaches the end of input.
    public static func decode(_ bytes: [UInt8]) throws -> [Segment] {
        var out = [Segment]()
        var cursor = 0
        while cursor < bytes.count {
            guard cursor + 4 <= bytes.count else {
                throw DecodeError.truncated
            }
            let size = (UInt32(bytes[cursor]) << 24)
                | (UInt32(bytes[cursor + 1]) << 16)
                | (UInt32(bytes[cursor + 2]) << 8)
                | UInt32(bytes[cursor + 3])
            cursor += 4
            if (size & 0x8000_0000) == 0 {
                // Literal: next `size` bytes are raw data.
                let n = Int(size)
                guard cursor + n <= bytes.count else {
                    throw DecodeError.truncated
                }
                out.append(.literal(bytes: Array(bytes[cursor..<(cursor + n)])))
                cursor += n
            } else {
                // Packed: 68-byte seed follows; `size` (MSB stripped)
                // bytes are PRNG-generated.
                let realSize = size & 0x7FFF_FFFF
                guard cursor + 68 <= bytes.count else {
                    throw DecodeError.truncated
                }
                let seed = Array(bytes[cursor..<(cursor + 68)])
                cursor += 68
                out.append(.packed(size: realSize, seed: seed))
            }
        }
        return out
    }

    /// Expand a segment list into its byte stream.
    public static func expand(_ segments: [Segment]) -> [UInt8] {
        var out = [UInt8]()
        for s in segments {
            switch s {
            case .literal(let b):
                out.append(contentsOf: b)
            case .packed(let size, let seed):
                var prng = PRNG(seed: seed)
                out.append(contentsOf: prng.read(Int(size)))
            }
        }
        return out
    }

    // MARK: - Encode

    /// Serialize a segment list to its on-wire byte representation.
    /// Literal sizes must fit in 31 bits (`size < 0x80000000`); packed
    /// sizes must have the MSB clear before encoding (the MSB is set
    /// by the encoder).
    public static func encode(_ segments: [Segment]) -> [UInt8] {
        var out = [UInt8]()
        for s in segments {
            switch s {
            case .literal(let b):
                precondition(b.count < 0x8000_0000, "literal segment too large")
                let size = UInt32(b.count)
                appendUInt32BE(size, into: &out)
                out.append(contentsOf: b)
            case .packed(let size, let seed):
                precondition(seed.count == 68, "packed seed must be 68 bytes")
                precondition(size < 0x8000_0000, "packed size must fit in 31 bits")
                let tagged = size | 0x8000_0000
                appendUInt32BE(tagged, into: &out)
                out.append(contentsOf: seed)
            }
        }
        return out
    }

    // MARK: - Errors

    public enum DecodeError: Error {
        case truncated
    }

    // MARK: - Byte helpers

    private static func appendUInt32BE(_ v: UInt32, into out: inout [UInt8]) {
        out.append(UInt8(truncatingIfNeeded: v >> 24))
        out.append(UInt8(truncatingIfNeeded: v >> 16))
        out.append(UInt8(truncatingIfNeeded: v >> 8))
        out.append(UInt8(truncatingIfNeeded: v))
    }
}
