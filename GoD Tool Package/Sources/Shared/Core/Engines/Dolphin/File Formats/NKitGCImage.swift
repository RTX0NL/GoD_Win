//
//  NKitGCImage.swift
//
//  The layout of a GameCube NKit image, shared by the decoder and the
//  encoder.
//
//  An NKit image keeps the disc's system area verbatim — header,
//  bi2/apploader/main.dol, FST — and then *packs* the files together,
//  replacing each run of junk between them with a short gap encoding
//  (`NKitGapEncoding`) and rewriting the FST to the packed offsets. A
//  restore walks the packed files, re-expands each gap, and puts the
//  original offsets back into the FST.
//
//  Two rules are load-bearing and neither is guessable from the file:
//
//  - **A file occupies its length rounded up to 4 bytes**, in the
//    packed image and in the original alike. So the gap before the
//    next file is measured from `align4(end)`, not from `end`.
//  - **A junk run may begin with zeros**, and how many is *derived*,
//    not stored: the allowance is `nullsPos - position`, where
//    `nullsPos` is set to `align4(end of the last file) + 0x1C` — and
//    it is dropped to zero for a gap of `0x40000` bytes or more that
//    doesn't sit at either end of the file list. Measured on six real
//    discs: junk begins at `align4(gapStart) + 28` in 49 of 50 sampled
//    gaps, and at `gapStart` in the big ones, exactly as this says.
//
//  Ported from Nanook's NKit v1 (`NKit/Conversion/NkitFormat.cs`,
//  `Readers/NkitReaderGc.cs`, `Writers/NkitWriterGc.cs`, `Gaps.cs`) —
//  see `Documentation/Credits & References.md`.
//

import Foundation
import GoDFoundation

enum NKitGCImage {

    /// Bytes of disc header copied before `bi2.bin`.
    static let discHeaderSize = 0x440
    /// The junk stream is always seeded for a whole GameCube disc,
    /// whatever the image's own size field says.
    static let gamecubeDiscSize: UInt64 = 1_459_978_240
    /// A mixed gap's blocks are counted in units of this many bytes.
    static let gapBlockSize = 0x100
    /// Bytes of leading zeros a junk run is allowed after a file.
    static let nullsAllowance = 0x1C
    /// A gap at least this large, other than the first or last, starts
    /// its junk immediately rather than after the zero allowance.
    static let largeGapThreshold = 0x40000
    /// The image is padded out to a whole DVD sector.
    static let imageAlignment = 0x800

    static func align4(_ value: Int) -> Int { (value + 3) & ~3 }

    /// One file the FST declares, in whichever image it was read from.
    struct File {
        /// Index of the entry in the FST, or nil for the synthetic
        /// `fst.bin` that owns the first gap.
        var entryIndex: Int?
        var offset: Int
        var length: Int

        /// Byte offset of the entry's `file_offset` field inside the
        /// FST. Its `length` field follows immediately.
        var offsetField: Int? { entryIndex.map { $0 * 12 + 4 } }
    }

    /// A file paired with the gap that follows it. The first entry's
    /// file is the FST itself, so a list of *n* files has *n + 1*
    /// entries and every file is written exactly once.
    struct Segment {
        var file: File
        var gapLength: Int
    }

    /// Every file the FST lists, in on-disc order.
    static func files(inFST fst: [UInt8]) throws -> [File] {
        guard fst.count >= 12 else { throw NKitGCConverter.Error.invalidFSTOffsets }
        let count = Int(readUInt32(fst, at: 8))
        guard count > 0, count * 12 <= fst.count else {
            throw NKitGCConverter.Error.invalidFSTOffsets
        }
        var files: [File] = []
        for entry in 1 ..< count where fst[entry * 12] == 0 {
            files.append(File(
                entryIndex: entry,
                offset: Int(readUInt32(fst, at: entry * 12 + 4)),
                length: Int(readUInt32(fst, at: entry * 12 + 8))
            ))
        }
        // Ties broken by length so a zero-length file sorts ahead of a
        // real one sharing its offset, as NKit's own ordering does.
        files.sort { $0.offset == $1.offset ? $0.length < $1.length : $0.offset < $1.offset }
        return files
    }

    /// Pair each file with the gap after it. `imageLength` bounds the
    /// last gap: the packed image's length when reading, the original
    /// disc's size when writing.
    static func segments(
        fst: [UInt8],
        fstOffset: Int,
        fstPaddedSize: Int,
        imageLength: Int
    ) throws -> [Segment] {
        let files = try files(inFST: fst)
        guard !files.isEmpty else { throw NKitGCConverter.Error.invalidFSTOffsets }

        let fstFile = File(entryIndex: nil, offset: fstOffset, length: fstPaddedSize)
        var segments: [Segment] = []
        for index in files.indices {
            let previous = index == 0 ? fstFile : files[index - 1]
            let end = align4(previous.offset + previous.length)
            let gap = files[index].offset - end
            guard gap >= 0 else {
                throw NKitGCConverter.Error.overlappingFiles(at: files[index].offset)
            }
            segments.append(Segment(file: previous, gapLength: gap))
        }

        let last = files[files.count - 1]
        var tail = imageLength - align4(last.offset + last.length)
        // Some hacked images end exactly on the last file; NKit tolerates
        // being up to three bytes short there rather than failing.
        if tail >= -3 && tail < 0 { tail = 0 }
        guard tail >= 0 else { throw NKitGCConverter.Error.overlappingFiles(at: last.offset) }
        segments.append(Segment(file: last, gapLength: tail))
        return segments
    }

    /// How many bytes of zeros a junk run starts with. `nullsPos` is
    /// the position the zero allowance runs out at; `firstOrLast` is
    /// whether this gap belongs to the first or last segment.
    static func leadingNulls(
        gapSize: Int,
        position: Int,
        nullsPos: Int,
        firstOrLast: Bool
    ) -> Int {
        let maxNulls = max(0, nullsPos - position)
        if gapSize < maxNulls { return gapSize }
        return (gapSize >= largeGapThreshold && !firstOrLast) ? 0 : maxNulls
    }

    // MARK: - Byte helpers

    static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    static func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value >> 24)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value)
    }
}
