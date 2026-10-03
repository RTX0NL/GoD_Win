//
//  NKitGapEncoding.swift
//
//  The Run-Length style encoding NKit uses to shrink "gap" regions
//  between files on a GameCube or Wii disc.
//
//  Every gap gets a 4-byte header whose low 2 bits are a type tag:
//    0b00 AllJunk      — entire gap regenerated from the disc PRNG
//    0b01 AllScrubbed  — entire gap is zero
//    0b10 Mixed        — followed by a sequence of 32-bit block entries,
//                        each describing a 0x100-byte segment
//    0b11 JunkFile     — a "junk file" (original file whose content was
//                        junk) was removed; regenerate N bytes from the
//                        PRNG starting at a given stream offset
//
//  Mixed-gap block entries: top 2 bits = kind, low 30 bits = count of
//  0x100-byte units.
//    0b00 Junk       — regenerate count × 0x100 bytes from the PRNG
//    0b01 NonJunk    — count × 0x100 bytes follow inline, verbatim
//    0b10 ByteFill   — fill count × 0x100 bytes with a single byte (the
//                      low 8 bits of the header)
//    0b11 Repeat     — re-emit the previous NonJunk payload count times
//
//  Gap lengths are always multiples of 4; lengths ≥ 0xFFFFFFFC split
//  into two consecutive 4-byte headers.
//
//  Reference: Documentation/File Formats/Shared/NKIT - Lossless Shrunk ISO.md
//

import Foundation

public enum NKitGapEncoding {

    // MARK: - Types

    public enum GapType: UInt32 {
        case allJunk     = 0b00
        case allScrubbed = 0b01
        case mixed       = 0b10
        case junkFile    = 0b11
    }

    public enum MixedBlockKind: UInt32 {
        case junk     = 0b00
        case nonJunk  = 0b01
        case byteFill = 0b10
        case repeatPrevious = 0b11
    }

    public enum MixedBlock: Equatable {
        /// `count` × 0x100 bytes regenerated from the PRNG.
        case junk(count: UInt32)
        /// `count` × 0x100 bytes supplied inline, verbatim.
        case nonJunk(bytes: [UInt8])
        /// `count` × 0x100 bytes, each equal to `byte`.
        case byteFill(byte: UInt8, count: UInt32)
        /// Re-emit the last NonJunk payload `count` times.
        case repeatPrevious(count: UInt32)

        /// Intrinsic byte length of this block in isolation. For
        /// `.repeatPrevious` the answer depends on the preceding
        /// `.nonJunk` payload; callers should compute length as they
        /// walk the block list. Returning 0 here keeps standalone use
        /// clearly undefined.
        public var byteLength: UInt64 {
            switch self {
            case .junk(let c):          return UInt64(c) * 0x100
            case .nonJunk(let b):       return UInt64(b.count)
            case .byteFill(_, let c):   return UInt64(c) * 0x100
            case .repeatPrevious:       return 0
            }
        }
    }

    public enum Gap: Equatable {
        case allJunk(length: UInt64)
        case allScrubbed(length: UInt64)
        case junkFile(length: UInt64, streamOffset: UInt64)
        case mixed(length: UInt64, blocks: [MixedBlock])

        public var length: UInt64 {
            switch self {
            case .allJunk(let n):        return n
            case .allScrubbed(let n):    return n
            case .junkFile(let n, _):    return n
            case .mixed(let n, _):       return n
            }
        }
    }

    // MARK: - Encode

    /// Serialize a gap to its on-disc byte representation. Length is
    /// asserted to be 4-byte aligned (the format's hard invariant).
    public static func encode(_ gap: Gap) -> [UInt8] {
        precondition(gap.length % 4 == 0, "NKit gap lengths must be 4-byte aligned")
        var out = [UInt8]()

        // 4-byte header(s): type in low 2 bits, length in top 30.
        // Lengths that don't fit into 30 bits split into two headers.
        let typeBits = typeOf(gap).rawValue
        writeHeaderLength(gap.length, type: typeBits, into: &out)

        switch gap {
        case .allJunk, .allScrubbed:
            break
        case .junkFile(_, let streamOffset):
            // Stream offset is a straight 64-bit append.
            appendUInt64BE(streamOffset, into: &out)
        case .mixed(_, let blocks):
            for blk in blocks {
                encodeBlock(blk, into: &out)
            }
        }
        return out
    }

    private static func typeOf(_ gap: Gap) -> GapType {
        switch gap {
        case .allJunk:     return .allJunk
        case .allScrubbed: return .allScrubbed
        case .junkFile:    return .junkFile
        case .mixed:       return .mixed
        }
    }

    /// A 4-byte header with `type` in the low 2 bits and `length` in
    /// the top 30. Lengths ≥ 0xFFFFFFFC (which can't fit) split into
    /// two consecutive headers carrying `0xFFFFFFFC - type` and the
    /// remainder.
    private static func writeHeaderLength(_ length: UInt64, type: UInt32, into out: inout [UInt8]) {
        var remaining = length
        while remaining >= 0xFFFFFFFC {
            // Maximum single-header length is (0xFFFFFFFC | type),
            // because the low 2 bits carry the type tag.
            let head: UInt32 = 0xFFFF_FFFC | type
            appendUInt32BE(head, into: &out)
            remaining -= UInt64(0xFFFFFFFC)
        }
        // Low 2 bits = type, upper 30 bits = remaining length (which
        // is guaranteed to be 4-byte aligned and < 0xFFFFFFFC).
        let head: UInt32 = UInt32(remaining) | type
        appendUInt32BE(head, into: &out)
    }

    private static func encodeBlock(_ block: MixedBlock, into out: inout [UInt8]) {
        switch block {
        case .junk(let count):
            precondition(count <= 0x3FFF_FFFF, "mixed-block count overflow (junk)")
            let w: UInt32 = (MixedBlockKind.junk.rawValue << 30) | count
            appendUInt32BE(w, into: &out)
        case .nonJunk(let bytes):
            precondition(bytes.count % 0x100 == 0, "NonJunk block must be a multiple of 0x100 bytes")
            let count = UInt32(bytes.count / 0x100)
            precondition(count <= 0x3FFF_FFFF, "mixed-block count overflow (nonJunk)")
            let w: UInt32 = (MixedBlockKind.nonJunk.rawValue << 30) | count
            appendUInt32BE(w, into: &out)
            out.append(contentsOf: bytes)
        case .byteFill(let b, let count):
            // ByteFill's bottom 8 bits are the fill byte, so it
            // borrows count-space — max count is 0x3F_FFFF (22 bits).
            precondition(count <= 0x003F_FFFF, "ByteFill count overflow (max 0x3FFFFF)")
            let w: UInt32 = (MixedBlockKind.byteFill.rawValue << 30) | (count << 8) | UInt32(b)
            appendUInt32BE(w, into: &out)
        case .repeatPrevious(let count):
            precondition(count <= 0x3FFF_FFFF, "mixed-block count overflow (repeat)")
            let w: UInt32 = (MixedBlockKind.repeatPrevious.rawValue << 30) | count
            appendUInt32BE(w, into: &out)
        }
    }

    // MARK: - Decode

    /// Parse the next gap from `bytes` starting at `cursor`. Returns
    /// the parsed gap and the number of bytes consumed.
    public static func decode(from bytes: [UInt8], cursor: Int) throws -> (Gap, consumed: Int) {
        var cur = cursor
        var totalLength: UInt64 = 0
        var type: GapType = .allJunk

        // Consume any number of continuation headers (`0xFFFFFFFC` with
        // type tag) until we hit a terminal header.
        while true {
            guard cur + 4 <= bytes.count else {
                throw DecodeError.shortBuffer
            }
            let head = readUInt32BE(bytes, at: cur)
            cur += 4
            let t = head & 0b11
            let len = head & ~UInt32(0b11)
            guard let parsedType = GapType(rawValue: t) else {
                throw DecodeError.invalidType
            }
            type = parsedType
            totalLength &+= UInt64(len)
            if len != 0xFFFF_FFFC {
                // Not a continuation — done reading the size.
                break
            }
        }

        switch type {
        case .allJunk, .allScrubbed:
            return (type == .allJunk
                    ? .allJunk(length: totalLength)
                    : .allScrubbed(length: totalLength),
                    consumed: cur - cursor)
        case .junkFile:
            guard cur + 8 <= bytes.count else { throw DecodeError.shortBuffer }
            let streamOffset = readUInt64BE(bytes, at: cur)
            cur += 8
            return (.junkFile(length: totalLength, streamOffset: streamOffset), consumed: cur - cursor)
        case .mixed:
            var blocks = [MixedBlock]()
            var emitted: UInt64 = 0
            var lastNonJunkSize: UInt64 = 0
            while emitted < totalLength {
                guard cur + 4 <= bytes.count else { throw DecodeError.shortBuffer }
                let emittedBefore = emitted
                let w = readUInt32BE(bytes, at: cur)
                cur += 4
                let kindBits = (w >> 30) & 0b11
                guard let kind = MixedBlockKind(rawValue: kindBits) else {
                    throw DecodeError.invalidBlockKind
                }
                switch kind {
                case .junk:
                    let count = w & 0x3FFF_FFFF
                    blocks.append(.junk(count: count))
                    emitted &+= UInt64(count) * 0x100
                case .nonJunk:
                    let count = w & 0x3FFF_FFFF
                    let nbytes = Int(count) * 0x100
                    guard cur + nbytes <= bytes.count else { throw DecodeError.shortBuffer }
                    blocks.append(.nonJunk(bytes: Array(bytes[cur..<(cur + nbytes)])))
                    cur += nbytes
                    emitted &+= UInt64(count) * 0x100
                    lastNonJunkSize = UInt64(nbytes)
                case .byteFill:
                    let b = UInt8(truncatingIfNeeded: w)
                    let count = (w >> 8) & 0x003F_FFFF
                    blocks.append(.byteFill(byte: b, count: count))
                    emitted &+= UInt64(count) * 0x100
                case .repeatPrevious:
                    // `.repeatPrevious` re-emits the previous NonJunk
                    // payload; without a prior NonJunk it has zero size
                    // and can never advance `emitted` → infinite loop.
                    guard lastNonJunkSize > 0 else {
                        throw DecodeError.repeatWithoutNonJunk
                    }
                    let count = w & 0x3FFF_FFFF
                    blocks.append(.repeatPrevious(count: count))
                    emitted &+= UInt64(count) * lastNonJunkSize
                }
                // A block that makes no forward progress (e.g. a
                // zero-count junk/byteFill/nonJunk) would spin the loop
                // forever on malformed data — reject it.
                guard emitted > emittedBefore else {
                    throw DecodeError.noProgress
                }
            }
            return (.mixed(length: totalLength, blocks: blocks), consumed: cur - cursor)
        }
    }

    // MARK: - Expand

    /// Produce the actual bytes of a gap by combining the stored
    /// encoding with the disc's junk PRNG.
    public static func expand(_ gap: Gap, junk: JunkStream, junkOffset: UInt64) -> [UInt8] {
        switch gap {
        case .allJunk(let length):
            return junk.read(at: junkOffset, count: Int(length))
        case .allScrubbed(let length):
            return [UInt8](repeating: 0, count: Int(length))
        case .junkFile(let length, let streamOffset):
            return junk.read(at: streamOffset, count: Int(length))
        case .mixed(_, let blocks):
            var out = [UInt8]()
            var cursor: UInt64 = junkOffset
            var lastNonJunk = [UInt8]()
            for blk in blocks {
                switch blk {
                case .junk(let count):
                    let n = Int(count) * 0x100
                    out.append(contentsOf: junk.read(at: cursor, count: n))
                    cursor &+= UInt64(n)
                case .nonJunk(let bytes):
                    out.append(contentsOf: bytes)
                    lastNonJunk = bytes
                    cursor &+= UInt64(bytes.count)
                case .byteFill(let byte, let count):
                    let n = Int(count) * 0x100
                    out.append(contentsOf: [UInt8](repeating: byte, count: n))
                    cursor &+= UInt64(n)
                case .repeatPrevious(let count):
                    for _ in 0..<count {
                        out.append(contentsOf: lastNonJunk)
                    }
                    cursor &+= UInt64(count) * UInt64(lastNonJunk.count)
                }
            }
            return out
        }
    }

    // MARK: - Errors

    public enum DecodeError: Error {
        case shortBuffer
        case invalidType
        case invalidBlockKind
        /// A mixed-gap block made no forward progress (a zero-count
        /// block), which would otherwise loop forever.
        case noProgress
        /// A `.repeatPrevious` block appeared before any `.nonJunk`
        /// established a payload to repeat.
        case repeatWithoutNonJunk
    }

    // MARK: - Byte helpers

    private static func appendUInt32BE(_ v: UInt32, into out: inout [UInt8]) {
        out.append(UInt8(truncatingIfNeeded: v >> 24))
        out.append(UInt8(truncatingIfNeeded: v >> 16))
        out.append(UInt8(truncatingIfNeeded: v >> 8))
        out.append(UInt8(truncatingIfNeeded: v))
    }

    private static func appendUInt64BE(_ v: UInt64, into out: inout [UInt8]) {
        for shift in stride(from: 56, through: 0, by: -8) {
            out.append(UInt8(truncatingIfNeeded: v >> shift))
        }
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt64BE(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var r: UInt64 = 0
        for i in 0..<8 {
            r = (r << 8) | UInt64(bytes[offset + i])
        }
        return r
    }
}
