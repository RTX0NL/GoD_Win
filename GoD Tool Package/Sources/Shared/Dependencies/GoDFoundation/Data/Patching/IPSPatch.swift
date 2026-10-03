//
//  IPSPatch.swift
//
//  The International Patching System — the oldest and simplest of these
//  formats, and the only one here that verifies nothing.
//
//      "PATCH"
//      records, until the three bytes "EOF" appear where a record would:
//          3   offset, big-endian
//          2   size, big-endian
//          if size == 0:  2  run length, big-endian
//                         1  the byte to repeat
//          else:          n  the bytes to write
//      "EOF"
//      3   optional: the length to truncate the file to
//
//  What follows from that:
//
//  * **A three-byte offset caps the format at 16 MiB.** Nothing can be
//    patched past 0xFFFFFF, which rules out a disc image. `plan` refuses
//    rather than wrapping.
//  * **An offset of 0x454F46 spells "EOF".** A record there would end the
//    patch early for every reader, so one is never emitted: the record starts
//    a byte earlier instead, covering one byte that didn't need patching.
//  * **There are no checksums, no source size and no metadata.** Nothing
//    identifies the file a patch belongs to, so applying one cannot be
//    checked — not by us, not by any other tool. `apply` says so.
//  * **Records are applied in order and may overlap**, so a later record wins
//    where two cover the same byte.
//

import Foundation

public struct IPSPatch {

    public static let magic: [UInt8] = Array("PATCH".utf8)
    public static let terminator: [UInt8] = Array("EOF".utf8)
    /// The largest offset a three-byte field can hold.
    public static let maximumOffset = 0xFF_FFFF
    /// The largest size a two-byte field can hold.
    public static let maximumRecordLength = 0xFFFF
    /// The offset whose big-endian spelling is the terminator.
    public static let terminatorOffset = 0x45_4F46

    public enum Payload: Equatable {
        /// Bytes stored in the patch, at this offset in the patch file.
        case literal(patchOffset: Int)
        /// One byte, repeated.
        case run(byte: UInt8)
    }

    public struct Record: Equatable {
        public let offset: Int
        public let length: Int
        public let payload: Payload

        public init(offset: Int, length: Int, payload: Payload) {
            self.offset = offset
            self.length = length
            self.payload = payload
        }

        var outputRange: Range<Int> { offset ..< (offset + length) }
    }

    /// In file order, which is also the order they are applied in.
    public let records: [Record]
    /// The optional trailing field: the length the patched file is cut to.
    public let truncation: Int?

    /// The highest offset any record writes to.
    public var coverage: Int { records.map { $0.offset + $0.length }.max() ?? 0 }

    // MARK: - Parsing

    public static func parse(_ patch: GoDReadable) throws -> IPSPatch {
        let name = IPSPatchCodec.formatName
        let length = patch.length
        let minimum = magic.count + terminator.count
        guard length >= minimum else {
            throw PatchError.patchTooShort(format: name, length: length, minimum: minimum)
        }
        guard let head = patch.read(atAddress: 0, length: magic.count), head.rawBytes == magic else {
            let found = patch.read(atAddress: 0, length: min(length, PatchFormat.magicLength))?.rawBytes ?? []
            throw PatchError.wrongMagic(format: name, found: found)
        }

        var records = [Record]()
        var offset = magic.count
        while true {
            guard let marker = patch.read(atAddress: offset, length: terminator.count), marker.length == terminator.count else {
                throw PatchError.malformedPatch(
                    format: name, reason: "the records are not closed by \"EOF\"", offset: offset
                )
            }
            if marker.rawBytes == terminator {
                offset += terminator.count
                break
            }
            let recordOffset = Int(bigEndian: marker.rawBytes)
            offset += terminator.count

            guard let sizeField = patch.read(atAddress: offset, length: 2), sizeField.length == 2 else {
                throw PatchError.malformedPatch(format: name, reason: "a record's size is missing", offset: offset)
            }
            offset += 2
            let size = Int(bigEndian: sizeField.rawBytes)

            if size == 0 {
                guard let runField = patch.read(atAddress: offset, length: 3), runField.length == 3 else {
                    throw PatchError.malformedPatch(
                        format: name, reason: "a run record's length and byte are missing", offset: offset
                    )
                }
                let runLength = Int(bigEndian: Array(runField.rawBytes[0 ..< 2]))
                records.append(Record(
                    offset: recordOffset, length: runLength, payload: .run(byte: runField.rawBytes[2])
                ))
                offset += 3
            } else {
                guard offset + size <= length else {
                    throw PatchError.malformedPatch(
                        format: name, reason: "a record of \(size) bytes runs past the end of the patch", offset: offset
                    )
                }
                records.append(Record(offset: recordOffset, length: size, payload: .literal(patchOffset: offset)))
                offset += size
            }
        }

        let remaining = length - offset
        let truncation: Int?
        switch remaining {
        case 0:
            truncation = nil
        case 3:
            guard let field = patch.read(atAddress: offset, length: 3) else {
                throw PatchError.readFailed(format: name, offset: offset, length: 3)
            }
            truncation = Int(bigEndian: field.rawBytes)
        default:
            throw PatchError.malformedPatch(
                format: name,
                reason: "\(remaining) bytes follow the terminator — a patch ends there, or carries a "
                + "three-byte truncation length",
                offset: offset
            )
        }

        return IPSPatch(records: records, truncation: truncation)
    }

    // MARK: - Diffing

    /// Everything needed to write a patch, with none of its bytes held: a
    /// planned record names a stretch of the *target*, since the patch it will
    /// be written into does not exist yet.
    public struct Plan {
        public struct Entry: Equatable {
            public let offset: Int
            public let length: Int
            /// Set when the stretch is one repeated byte, which is stored as a
            /// run record rather than spelled out.
            public let runByte: UInt8?

            public init(offset: Int, length: Int, runByte: UInt8?) {
                self.offset = offset
                self.length = length
                self.runByte = runByte
            }
        }

        public let entries: [Entry]
        public let truncation: Int?

        public init(entries: [Entry], truncation: Int?) {
            self.entries = entries
            self.truncation = truncation
        }
    }

    /// The records that turn `source` into `target`.
    ///
    /// Runs of one repeated byte become run records where that is shorter than
    /// storing them, differing stretches become literals, and a target shorter
    /// than its source becomes the trailing truncation field.
    public static func plan(
        source: GoDReadable,
        target: GoDReadable,
        windowSize: Int = 1 << 22
    ) throws -> Plan {
        let name = IPSPatchCodec.formatName
        let sourceSize = source.length
        let targetSize = target.length
        // Only the target's own bytes can be written, so the walk stops there.
        // Anything past it is the truncation field's business.
        let coverage = targetSize

        var differing = [Range<Int>]()
        var runStart: Int?
        var offset = 0
        let window = max(1, windowSize)

        while offset < coverage {
            let count = min(window, coverage - offset)
            try autoreleasepool {
                let targetBytes = try PatchDiff.read(target, at: offset, count: count, name: name)
                // Past the end of the source every byte is new, so the whole
                // window differs without reading anything.
                let sourceBytes = offset >= sourceSize
                    ? nil
                    : try PatchDiff.read(source, at: offset, count: min(count, sourceSize - offset), name: name)
                for index in 0 ..< count {
                    let same = sourceBytes.map { index < $0.count && $0[index] == targetBytes[index] } ?? false
                    if same {
                        if let start = runStart {
                            differing.append(start ..< (offset + index))
                            runStart = nil
                        }
                    } else if runStart == nil {
                        runStart = offset + index
                    }
                }
            }
            offset += count
        }
        if let start = runStart {
            differing.append(start ..< coverage)
        }

        if let last = differing.last, last.upperBound - 1 > maximumOffset {
            throw PatchError.offsetBeyondFormatLimit(
                format: name, offset: last.upperBound - 1, limit: maximumOffset
            )
        }

        var entries = [Plan.Entry]()
        for region in differing {
            entries += try self.entries(for: region, of: target, name: name)
        }

        return Plan(entries: entries, truncation: targetSize < sourceSize ? targetSize : nil)
    }

    /// One differing stretch as records: split at the format's size ceiling,
    /// with repeated bytes turned into run records where that is shorter.
    private static func entries(
        for region: Range<Int>,
        of target: GoDReadable,
        name: String
    ) throws -> [Plan.Entry] {
        var entries = [Plan.Entry]()
        var cursor = region.lowerBound
        while cursor < region.upperBound {
            var start = cursor
            var limit = min(region.upperBound, start + maximumRecordLength)
            // Never start a record at the offset that spells the terminator:
            // every reader would stop there. One byte of context costs 1 byte
            // and is always available, since the offset is far from zero.
            if start == terminatorOffset {
                start -= 1
                limit = min(region.upperBound, start + maximumRecordLength)
            }
            let bytes = try PatchDiff.read(target, at: start, count: limit - start, name: name)

            // A stretch of one repeated byte is a run record when that is the
            // shorter spelling: a run costs three payload bytes whatever its
            // length, a literal costs one per byte.
            var runLength = 1
            while runLength < bytes.count, bytes[runLength] == bytes[0] { runLength += 1 }
            if runLength > 3 {
                entries.append(Plan.Entry(offset: start, length: runLength, runByte: bytes[0]))
                cursor = start + runLength
                continue
            }

            // Otherwise a literal, ended early if a worthwhile run begins
            // inside it — the run gets its own record on the next pass.
            var literalLength = bytes.count
            var index = 1
            while index + 4 <= bytes.count {
                let byte = bytes[index]
                var ahead = 1
                while index + ahead < bytes.count, bytes[index + ahead] == byte { ahead += 1 }
                if ahead > 8 {
                    literalLength = index
                    break
                }
                index += ahead
            }
            entries.append(Plan.Entry(offset: start, length: literalLength, runByte: nil))
            cursor = start + literalLength
        }
        return entries
    }

}

private extension Int {
    /// A big-endian field of two or three bytes.
    init(bigEndian bytes: [UInt8]) {
        self = bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}
