//
//  JunkStream.swift
//
//  Nintendo disc junk PRNG — the deterministic pseudo-random stream
//  used to fill unused space on every GameCube and Wii disc.
//  Identical-seed inputs (`gameID`, `disc`, `blockIndex`) always yield
//  the same bytes, so lossless formats like NKit and RVZ can throw
//  away the stored bytes and regenerate them on demand.
//
//  This is a faithful Swift port of NKit's `JunkStream.cs`. The
//  algorithm is non-obvious (re-seeded every 0x8000 bytes, odd 18-bit
//  shift when extracting the second byte of each 32-bit word) but
//  reproduces the stream exactly — which is what matters.
//
//  Reference:
//    Nanook/NKitv1 `NKit/FilesAndStreams/JunkStream.cs`
//    Documentation/File Formats/Shared/NKIT - Lossless Shrunk ISO.md
//

import Foundation

public struct JunkStream {

    /// Every `blockSize` bytes of junk are a self-contained unit; the
    /// PRNG state is re-seeded per block so seeking is O(block).
    public static let blockSize: UInt64 = 0x40000

    /// The 4-byte game ID that seeds the PRNG (disc header bytes 0..3).
    public let id: [UInt8]

    /// Disc number from the disc header (offset 0x06).
    public let disc: UInt8

    /// Logical length of the junk stream, in bytes. Computed from the
    /// caller-supplied disc length aligned up to a `0x8000` boundary;
    /// bytes past this point are always zero.
    public let junkLength: UInt64

    // MARK: - Construction

    public init(gameID: [UInt8], disc: UInt8, length: UInt64) {
        precondition(gameID.count >= 4, "JunkStream needs at least 4 ID bytes")
        self.id = Array(gameID.prefix(4))
        self.disc = disc
        self.junkLength = (length + 0x7FFF) & ~UInt64(0x7FFF)
    }

    /// Convenience for the common case of an ASCII game ID string.
    public init(gameID: String, disc: UInt8, length: UInt64) {
        let bytes = Array(gameID.utf8)
        self.init(gameID: bytes, disc: disc, length: length)
    }

    // MARK: - Generation

    /// Produce the `0x40000`-byte junk block at `blockIndex`. Bytes
    /// beyond `junkLength` within the last block are zero.
    public func block(_ blockIndex: UInt64) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: Int(Self.blockSize))
        fillBlock(blockIndex: UInt32(truncatingIfNeeded: blockIndex), into: &buffer)
        return buffer
    }

    /// Random-access read across any span of the stream.
    public func read(at position: UInt64, count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var out = [UInt8]()
        out.reserveCapacity(count)
        var pos = position
        var remaining = count
        while remaining > 0 {
            let blockIdx = pos / Self.blockSize
            let offsetInBlock = Int(pos % Self.blockSize)
            let blk = block(blockIdx)
            let take = min(remaining, Int(Self.blockSize) - offsetInBlock)
            out.append(contentsOf: blk[offsetInBlock..<(offsetInBlock + take)])
            remaining -= take
            pos &+= UInt64(take)
        }
        return out
    }

    // MARK: - Core algorithm (verbatim port)

    private func fillBlock(blockIndex: UInt32, into buffer: inout [UInt8]) {
        let blk = blockIndex
        var block: UInt32 = (blockIndex &* 8) &* 0x1EF29123
        var state = [UInt32](repeating: 0, count: 522)
        var sample: UInt32 = 0
        var num2: Int = 0
        var i = 0
        while i < 0x40000 {
            if (i & 0x7FFF) == 0 {
                // Re-seed every 0x8000 bytes. Seed derivation:
                //   s = ((id[2]<<8|id[1])<<16) | ((id[3]+id[2])<<8) | (id[0]+id[1])
                //   s = ((s ^ disc) * 0x260BCD5) ^ block
                let id0 = UInt32(id[0])
                let id1 = UInt32(id[1])
                let id2 = UInt32(id[2])
                let id3 = UInt32(id[3])
                sample = (((id2 << 8) | id1) << 16)
                    | ((id3 &+ id2) << 8)
                    | (id0 &+ id1)
                sample = ((sample ^ UInt32(disc)) &* 0x260BCD5) ^ block
                initState(seed: sample, state: &state)
                num2 = 520
                block = block &+ 0x1EF29123
            }
            num2 += 1
            if num2 == 0x209 {
                mixState(&state)
                num2 = 0
            }
            let w = state[num2]
            buffer[i]     = UInt8(truncatingIfNeeded: w >> 0x18)
            buffer[i + 1] = UInt8(truncatingIfNeeded: w >> 0x12) // NOT 0x10
            buffer[i + 2] = UInt8(truncatingIfNeeded: w >> 0x08)
            buffer[i + 3] = UInt8(truncatingIfNeeded: w)
            i += 4
        }

        // Zero any bytes past the stream's logical end.
        let absoluteStart = UInt64(blk) * Self.blockSize
        if absoluteStart >= junkLength {
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.update(repeating: 0)
            }
            return
        }
        let remaining = junkLength - absoluteStart
        if remaining < Self.blockSize {
            for j in Int(remaining)..<Int(Self.blockSize) {
                buffer[j] = 0
            }
        }
    }

    /// Initialises 17 state words via an LCG, extends to 521 via an
    /// XOR-linear recurrence, then runs 3 mix passes. The odd
    /// `++sample & 0x80000000` pattern in the inner loop is the C#
    /// prefix-increment semantic: increment first, then read.
    private func initState(seed: UInt32, state: inout [UInt32]) {
        var sample = seed
        var num: UInt32 = 0
        for wordIdx in 0..<17 {
            for _ in 0..<32 {
                sample = sample &* 0x5D588B65
                sample = sample &+ 1
                num = (num >> 1) | (sample & 0x8000_0000)
            }
            state[wordIdx] = num
        }
        state[0x10] ^= (state[0] >> 9) ^ (state[0x10] << 23)
        // num2 = 1..0x1F8 in the original (inclusive upper bound = 504)
        for n in 1..<505 {
            state[n + 16] = ((state[n - 1] << 23) ^ (state[n] >> 9)) ^ state[n + 15]
        }
        for _ in 0..<3 {
            mixState(&state)
        }
    }

    private func mixState(_ state: inout [UInt32]) {
        for index in 0..<0x20 {
            state[index] ^= state[index + 0x1E9]
        }
        for index in 0x20..<0x209 {
            state[index] ^= state[index - 0x20]
        }
    }
}
