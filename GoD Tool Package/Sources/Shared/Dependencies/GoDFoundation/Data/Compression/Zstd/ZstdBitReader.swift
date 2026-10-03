//
//  ZstdBitReader.swift
//
//  Zstandard reads its entropy-coded bitstreams *backwards*: the last byte
//  of a stream carries a single set bit marking where the payload ends, and
//  decoding walks from there toward the front, taking bits most-significant
//  first.
//
//  The implementation follows the reference decoder's `BIT_DStream_t`
//  closely — a 64-bit window that slides backward over the source — because
//  the exact overflow behaviour is load-bearing: FSE and Huffman streams are
//  terminated by *running out of bits*, not by a count, so a reader that
//  reports exhaustion a bit early or late decodes a different number of
//  symbols.
//
//  Reference: RFC 8878 §4.2.1, facebook/zstd `lib/common/bitstream.h`
//

import Foundation

/// A backward, MSB-first bit reader over a byte range.
///
/// Holds the source array by value; `[UInt8]` is copy-on-write, so several
/// readers over the same block share one buffer.
struct ZstdBitReader {

    /// How much of the stream is left, in the reference decoder's terms.
    enum Status {
        /// More whole bytes remain behind the window.
        case unfinished
        /// The window reaches the front of the stream but bits remain.
        case endOfBuffer
        /// Every bit has been consumed, exactly.
        case completed
        /// More bits were taken than the stream holds. Decoders use this as
        /// their stop condition, so it is a state rather than an error.
        case overflow
    }

    private let bytes: [UInt8]
    private let start: Int
    private let limit: Int          // start + 8; below it, reloads go byte-wise
    private var pointer: Int        // index of the window's lowest byte
    private var container: UInt64
    private var bitsConsumed: Int

    /// - Throws: `ZstdError.corrupted` when the stream is empty or its last
    ///   byte is zero (there is then no end marker to start from).
    init(bytes: [UInt8], range: Range<Int>) throws {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= bytes.count else {
            throw ZstdError.corrupted("empty or out-of-bounds bitstream")
        }
        let size = range.count
        let lastByte = bytes[range.upperBound - 1]
        guard lastByte != 0 else {
            throw ZstdError.corrupted("bitstream's final byte has no end marker")
        }

        self.bytes = bytes
        self.start = range.lowerBound
        self.limit = range.lowerBound + 8

        if size >= 8 {
            self.pointer = range.upperBound - 8
            self.container = ZstdBitReader.readLE64(bytes, at: range.upperBound - 8)
            self.bitsConsumed = 8 - Int(ZstdBitReader.highestSetBit(lastByte))
        } else {
            // Short stream: assemble the window by hand, left-aligned the
            // same way an 8-byte little-endian load would leave it, then
            // charge the missing bytes to `bitsConsumed`.
            self.pointer = range.lowerBound
            var value: UInt64 = 0
            for i in 0..<size {
                value |= UInt64(bytes[range.lowerBound + i]) << (8 * i)
            }
            self.container = value
            self.bitsConsumed = 8 - Int(ZstdBitReader.highestSetBit(lastByte)) + (8 - size) * 8
        }
    }

    /// The next `count` bits, without consuming them. `count` must be 0...64.
    @inline(__always)
    func lookBits(_ count: Int) -> UInt64 {
        // The `& 63` mirrors the reference's register mask: at exactly 64
        // bits consumed it wraps to a zero shift rather than clearing the
        // window, and decoders depend on reading that stale value before
        // noticing the overflow.
        ((container << (bitsConsumed & 63)) >> 1) >> ((63 - count) & 63)
    }

    @inline(__always)
    mutating func skipBits(_ count: Int) {
        bitsConsumed += count
    }

    /// Consume and return the next `count` bits.
    @inline(__always)
    mutating func readBits(_ count: Int) -> UInt64 {
        let value = lookBits(count)
        skipBits(count)
        return value
    }

    /// Slide the window back over the bits consumed since the last reload.
    @discardableResult
    mutating func reload() -> Status {
        if bitsConsumed > 64 { return .overflow }
        if pointer >= limit {
            pointer -= bitsConsumed >> 3
            bitsConsumed &= 7
            container = ZstdBitReader.readLE64(bytes, at: pointer)
            return .unfinished
        }
        if pointer == start {
            return bitsConsumed < 64 ? .endOfBuffer : .completed
        }
        var wholeBytes = bitsConsumed >> 3
        var status = Status.unfinished
        if pointer - wholeBytes < start {
            wholeBytes = pointer - start
            status = .endOfBuffer
        }
        pointer -= wholeBytes
        bitsConsumed -= wholeBytes * 8
        container = ZstdBitReader.readLE64(bytes, at: pointer)
        return status
    }

    /// True once the stream is spent — the window sits at the front and
    /// every bit in it has been taken.
    var isFinished: Bool {
        pointer == start && bitsConsumed == 64
    }

    // MARK: - Byte helpers

    @inline(__always)
    private static func readLE64(_ bytes: [UInt8], at index: Int) -> UInt64 {
        UInt64(bytes[index])
            | UInt64(bytes[index + 1]) << 8
            | UInt64(bytes[index + 2]) << 16
            | UInt64(bytes[index + 3]) << 24
            | UInt64(bytes[index + 4]) << 32
            | UInt64(bytes[index + 5]) << 40
            | UInt64(bytes[index + 6]) << 48
            | UInt64(bytes[index + 7]) << 56
    }

    /// Index of the highest set bit, counting the LSB as 0. Callers
    /// guarantee a non-zero argument.
    @inline(__always)
    static func highestSetBit(_ value: UInt8) -> UInt32 {
        UInt32(7 - value.leadingZeroBitCount)
    }

    @inline(__always)
    static func highestSetBit(_ value: UInt32) -> UInt32 {
        UInt32(31 - value.leadingZeroBitCount)
    }
}

/// A forward, LSB-first bit reader, used only for the FSE table
/// descriptions — those are written front to back, unlike the streams they
/// then decode.
struct ZstdForwardBitReader {
    private let bytes: [UInt8]
    private let start: Int
    private let end: Int
    private(set) var bitPosition: Int = 0

    init(bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        self.start = range.lowerBound
        self.end = range.upperBound
    }

    /// Reads past the end as zero bits. The FSE header decoder checks its
    /// own invariants (`remaining`, symbol count) and rejects a table that
    /// ran off the end, so a short read surfaces there rather than here.
    mutating func read(_ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<count {
            let index = start + (bitPosition >> 3)
            let bit: UInt32
            if index < end {
                bit = UInt32((bytes[index] >> (bitPosition & 7)) & 1)
            } else {
                bit = 0
            }
            value |= bit << i
            bitPosition += 1
        }
        return value
    }

    mutating func peek(_ count: Int) -> UInt32 {
        let saved = bitPosition
        let value = read(count)
        bitPosition = saved
        return value
    }

    /// Bytes consumed so far, rounding a partial byte up.
    var bytesConsumed: Int { (bitPosition + 7) >> 3 }
}
