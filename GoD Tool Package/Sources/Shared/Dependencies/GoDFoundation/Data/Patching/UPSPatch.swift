//
//  UPSPatch.swift
//
//  byuu's UPS patch format.
//
//      "UPS1"
//      VLV   source size
//      VLV   target size
//      hunks, repeated until (patch length - 12):
//            VLV   relative offset — bytes to skip from the current position
//            n×    XOR byte        — output = input ^ byte
//            0x00                  — closes the hunk, and counts against the position
//      footer, three little-endian UInt32:
//            CRC-32 of the source
//            CRC-32 of the target
//            CRC-32 of the patch, over every byte ahead of this word
//
//  Three things decide whether an implementation is right:
//
//  * **The hunk terminator occupies a position.** A hunk's span in the output
//    is `payload + 1`, so the next hunk's relative offset is measured from
//    one past the payload's end. Treat the zero as free and every hunk after
//    the first lands one byte early.
//  * **The XOR space is `max(sourceSize, targetSize)`**, not either file's own
//    size. Bytes past the shorter file read as zero, which is how the patch
//    carries the longer file's tail. Applying forward writes only
//    `targetSize` bytes, so hunk data past that exists purely to rebuild the
//    source in reverse — it is not corruption and must not be rejected.
//  * **The footer is little-endian**, in a tool whose `GoDData` defaults to
//    big, so every word here is decoded by hand.
//

import Foundation

public struct UPSPatch {

    public static let magic: [UInt8] = Array("UPS1".utf8)
    public static let footerLength = 12
    /// Magic, two one-byte sizes and the footer: the shortest legal patch,
    /// which is what two empty files produce.
    public static let minimumLength = 4 + 1 + 1 + footerLength

    /// One run of XOR bytes, and where its payload sits in the patch file.
    ///
    /// Held as an index rather than as bytes: the payload is read out of the
    /// patch on demand, so applying a patch costs a window, not its size.
    public struct Hunk: Equatable {
        /// Where the run starts in the patched output.
        public let outputOffset: Int
        /// Where its bytes sit in the patch file.
        public let patchOffset: Int
        public let length: Int

        public init(outputOffset: Int, patchOffset: Int, length: Int) {
            self.outputOffset = outputOffset
            self.patchOffset = patchOffset
            self.length = length
        }

        var outputRange: Range<Int> { outputOffset ..< (outputOffset + length) }
    }

    public let sourceSize: Int
    public let targetSize: Int
    /// Ordered by `outputOffset`, non-overlapping, and never empty-length.
    public let hunks: [Hunk]
    public let sourceChecksum: UInt32
    public let targetChecksum: UInt32
    /// The checksum the patch stores for itself.
    public let patchChecksum: UInt32

    /// The widest the XOR data can reach: bytes past the shorter file are
    /// zero-extended, so the patch describes this many positions.
    public var coverage: Int { max(sourceSize, targetSize) }

    public func inputSize(applying direction: PatchDirection) -> Int {
        direction == .forward ? sourceSize : targetSize
    }

    public func outputSize(applying direction: PatchDirection) -> Int {
        direction == .forward ? targetSize : sourceSize
    }

    public func inputChecksum(applying direction: PatchDirection) -> UInt32 {
        direction == .forward ? sourceChecksum : targetChecksum
    }

    public func outputChecksum(applying direction: PatchDirection) -> UInt32 {
        direction == .forward ? targetChecksum : sourceChecksum
    }

    // MARK: - Parsing

    /// Read a patch's header, hunk index and footer.
    ///
    /// - Parameter validatingChecksum: checks the patch against the CRC-32 in
    ///   its own footer, which costs one streamed pass. On by default: every
    ///   later decision trusts these bytes, and a truncated download is the
    ///   single most likely thing to be wrong with a patch.
    public static func parse(_ patch: GoDReadable, validatingChecksum: Bool = true) throws -> UPSPatch {
        let name = UPSPatchCodec.formatName
        let length = patch.length
        guard length >= minimumLength else {
            throw PatchError.patchTooShort(format: name, length: length, minimum: minimumLength)
        }
        guard let head = patch.read(atAddress: 0, length: magic.count), head.rawBytes == magic else {
            let found = patch.read(atAddress: 0, length: min(length, PatchFormat.magicLength))?.rawBytes ?? []
            throw PatchError.wrongMagic(format: name, found: found)
        }

        // Before anything structural: a patch that fails its own checksum is a
        // corrupt file, and saying so is more use than a complaint about
        // whichever field the corruption landed in.
        if validatingChecksum {
            let stored = littleEndianWord(
                patch.read(atAddress: length - 4, length: 4)?.rawBytes ?? [0, 0, 0, 0], at: 0
            )
            let computed = CRC32.compute(patch, bytes: 0 ..< (length - 4))
            guard computed == stored else {
                throw PatchError.patchChecksumMismatch(format: name, stored: stored, computed: computed)
            }
        }

        let bodyEnd = length - footerLength
        let stream = PatchByteStream(source: patch, start: magic.count, end: bodyEnd)

        let sourceSize = try size(from: stream, field: "source size", name: name)
        let targetSize = try size(from: stream, field: "target size", name: name)
        let coverage = max(sourceSize, targetSize)

        var hunks = [Hunk]()
        var position = 0
        while !stream.isAtEnd {
            let offsetField = stream.offset
            let relative = try decodeInteger(from: stream, field: "hunk offset", name: name)
            guard position <= coverage, relative <= UInt64(coverage - position) else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: "a hunk offset of \(relative) from position \(position) runs past the \(coverage) bytes the patch covers",
                    offset: offsetField
                )
            }
            position += Int(relative)

            let payloadOffset = stream.offset
            guard let payloadLength = stream.readZeroTerminatedRun() else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: "a hunk's XOR data is not terminated before the footer",
                    offset: payloadOffset
                )
            }
            guard position + payloadLength <= coverage else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: "a hunk of \(payloadLength) bytes at position \(position) runs past the \(coverage) bytes the patch covers",
                    offset: payloadOffset
                )
            }
            if payloadLength > 0 {
                hunks.append(Hunk(outputOffset: position, patchOffset: payloadOffset, length: payloadLength))
            }
            // The terminator occupies a position of its own.
            position += payloadLength + 1
        }

        guard let footer = patch.read(atAddress: bodyEnd, length: footerLength) else {
            throw PatchError.readFailed(format: name, offset: bodyEnd, length: footerLength)
        }
        let words = footer.rawBytes
        let storedSourceChecksum = littleEndianWord(words, at: 0)
        let storedTargetChecksum = littleEndianWord(words, at: 4)
        let storedPatchChecksum = littleEndianWord(words, at: 8)

        return UPSPatch(
            sourceSize: sourceSize,
            targetSize: targetSize,
            hunks: hunks,
            sourceChecksum: storedSourceChecksum,
            targetChecksum: storedTargetChecksum,
            patchChecksum: storedPatchChecksum
        )
    }

    private static func size(from stream: PatchByteStream, field: String, name: String) throws -> Int {
        let value = try decodeInteger(from: stream, field: field, name: name)
        guard value <= UInt64(Int.max) else {
            throw PatchError.malformedPatch(
                format: name, reason: "\(field) of \(value) bytes is not addressable", offset: stream.offset
            )
        }
        return Int(value)
    }

    private static func decodeInteger(from stream: PatchByteStream, field: String, name: String) throws -> UInt64 {
        let start = stream.offset
        do {
            return try PatchVariableLengthInteger.decode(nextByte: { stream.readByte() })
        } catch {
            throw PatchError.malformedPatch(format: name, reason: "\(field): \(error)", offset: start)
        }
    }

    private static func littleEndianWord(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}

// MARK: - Diffing

public extension UPSPatch {

    /// Everything needed to write a patch, with none of its bytes held.
    ///
    /// The runs are where the two files differ; a patch's payload is derived
    /// from the files themselves at write time, so creating one between two
    /// discs costs this list rather than a gigabyte.
    struct Plan {
        public let sourceSize: Int
        public let targetSize: Int
        /// Differing ranges over `[0, max(sourceSize, targetSize))`, ordered
        /// and disjoint.
        public let runs: [Range<Int>]
        public let sourceChecksum: UInt32
        public let targetChecksum: UInt32

        public var coverage: Int { max(sourceSize, targetSize) }

        public init(
            sourceSize: Int,
            targetSize: Int,
            runs: [Range<Int>],
            sourceChecksum: UInt32,
            targetChecksum: UInt32
        ) {
            self.sourceSize = sourceSize
            self.targetSize = targetSize
            self.runs = runs
            self.sourceChecksum = sourceChecksum
            self.targetChecksum = targetChecksum
        }
    }

    /// Walk both files once, recording where they differ and what each one
    /// checksums to.
    ///
    /// One pass, windowed, holding neither file: the output is a list of
    /// ranges. Bytes past the end of the shorter file compare as zero, which
    /// is what puts the longer file's tail into the patch.
    static func plan(
        source: GoDReadable,
        target: GoDReadable,
        windowSize: Int = 1 << 22
    ) throws -> Plan {
        let name = UPSPatchCodec.formatName
        let window = max(1, windowSize)
        let sourceSize = source.length
        let targetSize = target.length
        let coverage = max(sourceSize, targetSize)

        var runs = [Range<Int>]()
        var runStart: Int?
        var sourceCRC: UInt32 = 0xFFFF_FFFF
        var targetCRC: UInt32 = 0xFFFF_FFFF
        var offset = 0

        while offset < coverage {
            let count = min(window, coverage - offset)
            // One pool per window: a window is a fresh buffer from each file,
            // and without this they all live until the walk ends — which turns
            // a streamed diff into one that peaks at the files' size.
            try autoreleasepool {
                let sourceBytes = try bytes(of: source, at: offset, count: count, limit: sourceSize, name: name)
                let targetBytes = try bytes(of: target, at: offset, count: count, limit: targetSize, name: name)
                // Each file is checksummed over its own bytes only — the zero
                // padding is a comparison device, not part of either file.
                sourceCRC = CRC32.update(sourceCRC, bytes: real(sourceBytes, count, offset, sourceSize))
                targetCRC = CRC32.update(targetCRC, bytes: real(targetBytes, count, offset, targetSize))

                if sourceBytes == targetBytes {
                    // Whole window identical — the common case by far, and
                    // worth skipping the per-byte walk for. A run that was open
                    // ends where this window starts.
                    if let start = runStart {
                        runs.append(start ..< offset)
                        runStart = nil
                    }
                } else {
                    for index in 0 ..< count {
                        if sourceBytes[index] == targetBytes[index] {
                            if let start = runStart {
                                runs.append(start ..< (offset + index))
                                runStart = nil
                            }
                        } else if runStart == nil {
                            runStart = offset + index
                        }
                    }
                }
            }
            offset += count
        }
        if let start = runStart {
            runs.append(start ..< coverage)
        }

        return Plan(
            sourceSize: sourceSize,
            targetSize: targetSize,
            runs: runs,
            sourceChecksum: sourceCRC ^ 0xFFFF_FFFF,
            targetChecksum: targetCRC ^ 0xFFFF_FFFF
        )
    }

    /// `count` bytes at `offset`, zero-extended past `limit`.
    private static func bytes(
        of readable: GoDReadable,
        at offset: Int,
        count: Int,
        limit: Int,
        name: String
    ) throws -> [UInt8] {
        let real = clamped(count, offset, limit)
        guard real > 0 else { return [UInt8](repeating: 0, count: count) }
        guard let chunk = readable.read(atAddress: offset, length: real), chunk.length == real else {
            throw PatchError.readFailed(format: name, offset: offset, length: real)
        }
        var out = chunk.rawBytes
        if real < count {
            out += [UInt8](repeating: 0, count: count - real)
        }
        return out
    }

    private static func clamped(_ count: Int, _ offset: Int, _ limit: Int) -> Int {
        max(0, min(count, limit - offset))
    }

    /// The part of a zero-extended window that is really the file's, without
    /// copying when all of it is.
    private static func real(_ bytes: [UInt8], _ count: Int, _ offset: Int, _ limit: Int) -> [UInt8] {
        let real = clamped(count, offset, limit)
        if real == bytes.count { return bytes }
        return Array(bytes[0 ..< real])
    }
}
