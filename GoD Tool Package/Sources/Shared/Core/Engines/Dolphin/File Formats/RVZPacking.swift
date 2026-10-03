//
//  RVZPacking.swift
//
//  RVZ's lossless "packing" pass: a preprocessor that sits between the disc
//  data and the Zstd/LZMA/bzip2 compressor. Nintendo junk on GC/Wii discs
//  comes from a deterministic PRNG (a Lagged Fibonacci Generator) that RVZ
//  can reproduce given a 68-byte seed, so the packing layer replaces long
//  junk runs with `(size | MSB_flag) + seed` markers and the compressor
//  never has to represent them.
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
//
//  **The generator is not seeded by the seed alone.** Junk on a disc is
//  generated in 32 KiB blocks, so before emitting, the PRNG is advanced by
//  `dataOffset % 0x8000` bytes, where `dataOffset` is where the output
//  lands: relative to the start of the disc for raw data, and relative to
//  the start of the partition's data for a Wii partition — where the
//  hashes are *not* counted, yet the modulus is still 32 KiB and not 31.
//  A decoder that ignores this reproduces the right bytes only for runs
//  that happen to start on a 32 KiB boundary.
//
//  Reference:
//    dolphin-emu/dolphin `docs/WiaAndRvz.md`, `Source/Core/DiscIO/
//    LaggedFibonacciGenerator.cpp`
//    Documentation/File Formats/Shared/RVZ - Dolphin Disc Image.md
//

import Foundation

public enum RVZPacking {

    /// Junk is generated per 32 KiB disc block, which is what a run's
    /// starting offset is reduced modulo before output begins.
    public static let junkBlockSize = 0x8000

    /// A seed is 17 big-endian `UInt32` words.
    public static let seedSize = 68

    // MARK: - PRNG

    /// The Lagged Fibonacci Generator (f = xor, j = 32, k = 521) that
    /// produced the disc's padding.
    ///
    /// The odd `>> 18` in the format's byte-extraction step is folded into
    /// the state at initialization rather than applied on the way out. That
    /// is exactly what the reference implementation does, and it is sound
    /// because the transform is a mask-and-shift — linear over XOR — so it
    /// commutes with the generator's own XOR-only advance step.
    public struct PRNG {

        static let words = 521
        static let lag = 32
        /// Bytes the buffer yields before it has to be advanced.
        static let bytesPerCycle = words * 4   // 2084

        private var buffer: [UInt32]
        private var positionBytes: Int

        /// Seed must be exactly 68 bytes (17 × `UInt32`, big-endian).
        public init(seed: [UInt8]) {
            precondition(seed.count == RVZPacking.seedSize,
                         "RVZ packing seed must be \(RVZPacking.seedSize) bytes (17 × UInt32 BE)")
            var buffer = [UInt32](repeating: 0, count: PRNG.words)
            for i in 0..<17 {
                let base = i * 4
                buffer[i] = (UInt32(seed[base]) << 24)
                    | (UInt32(seed[base + 1]) << 16)
                    | (UInt32(seed[base + 2]) << 8)
                    | UInt32(seed[base + 3])
            }
            for i in 17..<PRNG.words {
                buffer[i] = (buffer[i - 17] &<< 23) ^ (buffer[i - 16] >> 9) ^ buffer[i - 1]
            }
            // Fold in the "shift by 18, not 16" quirk of the output step.
            for i in 0..<PRNG.words {
                buffer[i] = (buffer[i] & 0xFF00_FFFF) | ((buffer[i] >> 2) & 0x00FF_0000)
            }
            self.buffer = buffer
            self.positionBytes = 0
            for _ in 0..<4 { advance() }
        }

        /// Advance the state by one full buffer.
        private mutating func advance() {
            for i in 0..<PRNG.lag {
                buffer[i] ^= buffer[i + PRNG.words - PRNG.lag]
            }
            for i in PRNG.lag..<PRNG.words {
                buffer[i] ^= buffer[i - PRNG.lag]
            }
        }

        /// Consume `count` bytes without producing them — how a run that
        /// does not start on a 32 KiB boundary is positioned.
        public mutating func forward(_ count: Int) {
            positionBytes += count
            while positionBytes >= PRNG.bytesPerCycle {
                advance()
                positionBytes -= PRNG.bytesPerCycle
            }
        }

        @inline(__always)
        private mutating func nextByte() -> UInt8 {
            let word = buffer[positionBytes >> 2]
            let byte = UInt8(truncatingIfNeeded: word >> (24 - 8 * (positionBytes & 3)))
            positionBytes += 1
            if positionBytes == PRNG.bytesPerCycle {
                advance()
                positionBytes = 0
            }
            return byte
        }

        /// Produce `count` PRNG bytes. Safe at any size — partial-word state
        /// is carried between calls.
        public mutating func read(_ count: Int) -> [UInt8] {
            var out = [UInt8]()
            out.reserveCapacity(count)
            for _ in 0..<count { out.append(nextByte()) }
            return out
        }

        /// Append `count` PRNG bytes to an existing buffer, which is what a
        /// chunk decoder wants — it is filling one output array.
        public mutating func read(_ count: Int, into out: inout [UInt8]) {
            for _ in 0..<count { out.append(nextByte()) }
        }
    }

    // MARK: - Stream model

    /// One segment of a packed stream: either literal bytes or a PRNG run.
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
                let n = Int(size)
                guard cursor + n <= bytes.count else {
                    throw DecodeError.truncated
                }
                out.append(.literal(bytes: Array(bytes[cursor..<(cursor + n)])))
                cursor += n
            } else {
                let realSize = size & 0x7FFF_FFFF
                guard cursor + seedSize <= bytes.count else {
                    throw DecodeError.truncated
                }
                out.append(.packed(size: realSize, seed: Array(bytes[cursor..<(cursor + seedSize)])))
                cursor += seedSize
            }
        }
        return out
    }

    /// Expand a segment list into its byte stream.
    ///
    /// - Parameter dataOffset: where the first byte lands, in the coordinate
    ///   space the run was packed against. Only the remainder modulo 32 KiB
    ///   matters, but passing the real offset keeps call sites honest.
    public static func expand(_ segments: [Segment], startingAtDataOffset dataOffset: Int = 0) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(segments.reduce(0) { $0 + $1.expandedByteLength })
        var offset = dataOffset
        for segment in segments {
            switch segment {
            case .literal(let bytes):
                out.append(contentsOf: bytes)
                offset += bytes.count
            case .packed(let size, let seed):
                var prng = PRNG(seed: seed)
                prng.forward(offset % junkBlockSize)
                prng.read(Int(size), into: &out)
                offset += Int(size)
            }
        }
        return out
    }

    /// Decode and expand a packed stream in one pass.
    ///
    /// The form a chunk decoder uses: it never materializes the segment
    /// list, so a literal run is copied once rather than twice.
    ///
    /// - Parameters:
    ///   - bytes: the packed stream, already decompressed.
    ///   - expandedSize: how many bytes the stream should produce. Checked,
    ///     because a short or long result means the stream was mis-framed
    ///     and every later offset in the chunk would be wrong.
    ///   - dataOffset: where the first output byte lands (see `expand`).
    public static func unpack(
        _ bytes: [UInt8],
        expandedSize: Int,
        dataOffset: Int
    ) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(expandedSize)
        var cursor = 0
        var offset = dataOffset
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
                let n = Int(size)
                guard cursor + n <= bytes.count else {
                    throw DecodeError.truncated
                }
                out.append(contentsOf: bytes[cursor..<(cursor + n)])
                cursor += n
                offset += n
            } else {
                let n = Int(size & 0x7FFF_FFFF)
                guard cursor + seedSize <= bytes.count else {
                    throw DecodeError.truncated
                }
                var prng = PRNG(seed: Array(bytes[cursor..<(cursor + seedSize)]))
                cursor += seedSize
                prng.forward(offset % junkBlockSize)
                prng.read(n, into: &out)
                offset += n
            }
        }
        guard out.count == expandedSize else {
            throw DecodeError.unexpectedSize(expected: expandedSize, found: out.count)
        }
        return out
    }

    // MARK: - Encode

    public static func encode(_ segments: [Segment]) -> [UInt8] {
        var out = [UInt8]()
        for s in segments {
            switch s {
            case .literal(let b):
                precondition(b.count < 0x8000_0000, "literal segment too large")
                appendUInt32BE(UInt32(b.count), into: &out)
                out.append(contentsOf: b)
            case .packed(let size, let seed):
                precondition(seed.count == seedSize, "packed seed must be \(seedSize) bytes")
                precondition(size < 0x8000_0000, "packed size must fit in 31 bits")
                appendUInt32BE(size | 0x8000_0000, into: &out)
                out.append(contentsOf: seed)
            }
        }
        return out
    }

    // MARK: - Errors

    public enum DecodeError: Error, CustomStringConvertible {
        case truncated
        case unexpectedSize(expected: Int, found: Int)

        public var description: String {
            switch self {
            case .truncated:
                return "RVZ packed stream ends mid-segment"
            case let .unexpectedSize(expected, found):
                return "RVZ packed stream expands to \(found) bytes, not the \(expected) its group declares"
            }
        }
    }

    // MARK: - Byte helpers

    private static func appendUInt32BE(_ v: UInt32, into out: inout [UInt8]) {
        out.append(UInt8(truncatingIfNeeded: v >> 24))
        out.append(UInt8(truncatingIfNeeded: v >> 16))
        out.append(UInt8(truncatingIfNeeded: v >> 8))
        out.append(UInt8(truncatingIfNeeded: v))
    }
}
