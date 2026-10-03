//
//  BPSPatch.swift
//
//  byuu's BPS, the format that replaced UPS. Where UPS stores an XOR at fixed
//  positions, BPS is a little instruction stream, which is what lets it
//  describe data that moved.
//
//      "BPS1"
//      VLV   source size
//      VLV   target size
//      VLV   metadata size
//      n×    metadata (UTF-8, usually XML; no terminator)
//      actions, until (patch length - 12):
//          VLV   data — command = data & 3, length = (data >> 2) + 1
//            0  SourceRead  take `length` bytes from the source at the output's
//                           own offset
//            1  TargetRead  `length` literal bytes follow in the patch
//            2  SourceCopy  a signed VLV moves a cursor in the source; take
//                           `length` bytes from there
//            3  TargetCopy  the same, over the output written so far
//      footer, three little-endian UInt32:
//          CRC-32 of the source, of the target, and of the patch ahead of it
//
//  Three things to get right:
//
//  * **A signed VLV is `sign | (magnitude << 1)`** — the low bit is the sign,
//    not part of the value, and the cursor it moves is *relative to the last
//    copy of that kind*, not to the output position.
//  * **TargetCopy may overlap its own output.** Copying a 1-byte-back
//    reference 300 bytes long is how the format spells a run, so the copy has
//    to be byte at a time; a block move would read bytes that aren't written
//    yet.
//  * **The two copy cursors are independent** and persist across actions.
//
//  The VLV itself is UPS's, unchanged — see `PatchVariableLengthInteger`.
//

import Foundation

public struct BPSPatch {

    public static let magic: [UInt8] = Array("BPS1".utf8)
    public static let footerLength = 12
    /// Magic, three one-byte sizes, and the footer.
    public static let minimumLength = 4 + 3 + footerLength

    public enum Action: Equatable {
        /// Bytes the target shares with the source, at the same offset.
        case sourceRead(length: Int)
        /// Literal bytes, stored at `patchOffset` in the patch.
        case targetRead(patchOffset: Int, length: Int)
        /// Bytes taken from the source at an arbitrary offset.
        case sourceCopy(sourceOffset: Int, length: Int)
        /// Bytes taken from the output written so far, which may overlap what
        /// this action is writing.
        case targetCopy(targetOffset: Int, length: Int)

        public var length: Int {
            switch self {
            case let .sourceRead(length): return length
            case let .targetRead(_, length): return length
            case let .sourceCopy(_, length): return length
            case let .targetCopy(_, length): return length
            }
        }
    }

    public let sourceSize: Int
    public let targetSize: Int
    /// The patch's own metadata block, as stored. Usually empty; `beat` writes
    /// XML here.
    public let metadata: [UInt8]
    public let actions: [Action]
    public let sourceChecksum: UInt32
    public let targetChecksum: UInt32
    public let patchChecksum: UInt32

    // MARK: - Parsing

    public static func parse(_ patch: GoDReadable, validatingChecksum: Bool = true) throws -> BPSPatch {
        let name = BPSPatchCodec.formatName
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
        let metadataSize = try size(from: stream, field: "metadata size", name: name)
        var metadata = [UInt8]()
        if metadataSize > 0 {
            let start = stream.offset
            guard start + metadataSize <= bodyEnd,
                  let block = patch.read(atAddress: start, length: metadataSize) else {
                throw PatchError.malformedPatch(
                    format: name, reason: "the metadata block runs past the end of the patch", offset: start
                )
            }
            metadata = block.rawBytes
            stream.skip(metadataSize)
        }

        var actions = [Action]()
        var outputOffset = 0
        var sourceCursor = 0
        var targetCursor = 0

        while !stream.isAtEnd {
            let actionOffset = stream.offset
            let data = try decodeInteger(from: stream, field: "action", name: name)
            let command = Int(data & 3)
            guard data >> 2 < UInt64(Int.max) else {
                throw PatchError.malformedPatch(format: name, reason: "an action length is not addressable", offset: actionOffset)
            }
            let actionLength = Int(data >> 2) + 1
            guard outputOffset + actionLength <= targetSize else {
                throw PatchError.malformedPatch(
                    format: name,
                    reason: "an action writes \(actionLength) bytes at \(outputOffset), past the \(targetSize)-byte target",
                    offset: actionOffset
                )
            }

            switch command {
            case 0:
                guard outputOffset + actionLength <= sourceSize else {
                    throw PatchError.malformedPatch(
                        format: name,
                        reason: "a SourceRead of \(actionLength) bytes at \(outputOffset) runs past the "
                        + "\(sourceSize)-byte source",
                        offset: actionOffset
                    )
                }
                actions.append(.sourceRead(length: actionLength))
            case 1:
                let start = stream.offset
                guard start + actionLength <= bodyEnd else {
                    throw PatchError.malformedPatch(
                        format: name,
                        reason: "a TargetRead of \(actionLength) bytes runs past the end of the patch",
                        offset: start
                    )
                }
                actions.append(.targetRead(patchOffset: start, length: actionLength))
                stream.skip(actionLength)
            case 2, 3:
                let delta = try decodeSignedInteger(from: stream, field: "copy offset", name: name)
                if command == 2 {
                    sourceCursor += delta
                    guard sourceCursor >= 0, sourceCursor + actionLength <= sourceSize else {
                        throw PatchError.malformedPatch(
                            format: name,
                            reason: "a SourceCopy reads \(actionLength) bytes at \(sourceCursor), outside the "
                            + "\(sourceSize)-byte source",
                            offset: actionOffset
                        )
                    }
                    actions.append(.sourceCopy(sourceOffset: sourceCursor, length: actionLength))
                    sourceCursor += actionLength
                } else {
                    targetCursor += delta
                    // A TargetCopy may overlap what it is writing — that is how
                    // the format spells a run — so its start only has to be
                    // behind the output position, not behind the whole copy.
                    guard targetCursor >= 0, targetCursor < outputOffset || actionLength == 0 else {
                        throw PatchError.malformedPatch(
                            format: name,
                            reason: "a TargetCopy reads from \(targetCursor), which is not yet written "
                            + "(the output is at \(outputOffset))",
                            offset: actionOffset
                        )
                    }
                    actions.append(.targetCopy(targetOffset: targetCursor, length: actionLength))
                    targetCursor += actionLength
                }
            default:
                throw PatchError.malformedPatch(format: name, reason: "unknown action \(command)", offset: actionOffset)
            }
            outputOffset += actionLength
        }

        guard outputOffset == targetSize else {
            throw PatchError.malformedPatch(
                format: name,
                reason: "the actions write \(outputOffset) bytes, but the patch declares a \(targetSize)-byte target",
                offset: bodyEnd
            )
        }

        guard let footer = patch.read(atAddress: bodyEnd, length: footerLength) else {
            throw PatchError.readFailed(format: name, offset: bodyEnd, length: footerLength)
        }
        let words = footer.rawBytes
        let storedSource = littleEndianWord(words, at: 0)
        let storedTarget = littleEndianWord(words, at: 4)
        let storedPatch = littleEndianWord(words, at: 8)

        return BPSPatch(
            sourceSize: sourceSize,
            targetSize: targetSize,
            metadata: metadata,
            actions: actions,
            sourceChecksum: storedSource,
            targetChecksum: storedTarget,
            patchChecksum: storedPatch
        )
    }

    // MARK: - Diffing

    /// A linear plan: the runs the target shares with its source, and the runs
    /// it doesn't.
    ///
    /// This is byuu's "linear" creator — `SourceRead` and `TargetRead` only.
    /// It never claims a match that isn't at the same offset, so it cannot
    /// express moved data, which is what `SourceCopy` and `TargetCopy` are
    /// for; a reader handles all four, since other tools emit them.
    public struct Plan {
        public let sourceSize: Int
        public let targetSize: Int
        /// Ordered and gapless over `[0, targetSize)`.
        public let runs: [Run]
        public let sourceChecksum: UInt32
        public let targetChecksum: UInt32

        public struct Run: Equatable {
            public let range: Range<Int>
            /// True where the target's bytes are the source's, at the same
            /// offset — a `SourceRead` rather than a `TargetRead`.
            public let sharedWithSource: Bool

            public init(range: Range<Int>, sharedWithSource: Bool) {
                self.range = range
                self.sharedWithSource = sharedWithSource
            }
        }

        public init(
            sourceSize: Int,
            targetSize: Int,
            runs: [Run],
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

    public static func plan(source: GoDReadable, target: GoDReadable) throws -> Plan {
        let name = BPSPatchCodec.formatName
        let differing = try PatchDiff.differingRanges(source: source, target: target, format: name)
        let targetSize = target.length

        var runs = [Plan.Run]()
        var cursor = 0
        for range in differing {
            if range.lowerBound > cursor {
                runs.append(.init(range: cursor ..< range.lowerBound, sharedWithSource: true))
            }
            runs.append(.init(range: range, sharedWithSource: false))
            cursor = range.upperBound
        }
        if cursor < targetSize {
            runs.append(.init(range: cursor ..< targetSize, sharedWithSource: true))
        }

        return Plan(
            sourceSize: source.length,
            targetSize: targetSize,
            runs: runs,
            sourceChecksum: CRC32.compute(source),
            targetChecksum: CRC32.compute(target)
        )
    }

    // MARK: - Fields

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

    /// `sign | (magnitude << 1)`: the low bit says which way, the rest is how
    /// far.
    private static func decodeSignedInteger(from stream: PatchByteStream, field: String, name: String) throws -> Int {
        let start = stream.offset
        let data = try decodeInteger(from: stream, field: field, name: name)
        let magnitude = data >> 1
        guard magnitude <= UInt64(Int.max) else {
            throw PatchError.malformedPatch(format: name, reason: "\(field) is not addressable", offset: start)
        }
        return data & 1 == 1 ? -Int(magnitude) : Int(magnitude)
    }

    static func encodeSignedInteger(_ value: Int) -> [UInt8] {
        let magnitude = UInt64(value.magnitude)
        return PatchVariableLengthInteger.encode((magnitude << 1) | (value < 0 ? 1 : 0))
    }

    private static func littleEndianWord(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
