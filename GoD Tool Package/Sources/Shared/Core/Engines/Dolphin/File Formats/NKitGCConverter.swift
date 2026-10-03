//
//  NKitGCConverter.swift
//
//  GameCube NKit codec, both directions.
//
//  An NKit image keeps the disc's system area verbatim and packs the
//  files together, replacing the junk between them with short gap
//  encodings and rewriting the FST to the packed offsets. `dump`
//  walks that back out to a raw ISO; `build` produces it. The layout
//  rules, and the two that aren't guessable from a file, are in
//  `NKitGCImage`.
//
//  **The restore is checked, not assumed.** NKit records the original
//  disc's CRC-32 at 0x208, and `dump` refuses to hand back an image
//  that doesn't hash to it. That gate is the reason this file can be
//  trusted at all: an earlier version implemented a different image
//  shape, restored a real Pokemon XD US image to something 99.24 %
//  wrong, and reported success, because the structural check it used
//  instead cannot see a rewritten FST.
//
//  Ported from Nanook's NKit v1 (`NKit/Conversion/Readers/NkitReaderGc.cs`,
//  `Writers/NkitWriterGc.cs`, `NkitFormat.cs`, `Gaps.cs`).
//  See `Documentation/Credits & References.md` and
//  `Documentation/File Formats/Shared/NKIT - Lossless Shrunk ISO.md`.
//

import Foundation
import GoDFoundation

public enum NKitGCConverter {

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAnNKitGCImage
        case notAGameCubeISO
        case alreadyNKit
        case wiiNotSupported
        case invalidFSTOffsets
        case overlappingFiles(at: Int)
        case truncated(needed: Int, available: Int)
        case metadataRegionNotEmpty(firstNonZeroOffset: Int)
        case invalidJunkOverrideID(String)
        case restoredImageCRCMismatch(expected: UInt32, actual: UInt32)
        case unencodableGap(at: Int, length: Int)

        public var description: String {
            switch self {
            case .notAnNKitGCImage:
                return "Input isn't an NKit GameCube image (missing NKIT magic or wrong disc magic)"
            case .notAGameCubeISO:
                return "Input isn't a raw GameCube ISO (no 0xC2339F3D disc magic at 0x1C)"
            case .alreadyNKit:
                return "Input is already an NKit image (NKIT magic at 0x200)"
            case .wiiNotSupported:
                return "This is a Wii disc image. NKit on Wii also strips each partition's hashes and "
                    + "encryption, which this codec doesn't do — convert it with NKit or wit instead."
            case .invalidFSTOffsets:
                return "The image's FST pointers are invalid"
            case let .overlappingFiles(offset):
                return "Two files overlap around \(String(format: "0x%X", offset)); the FST doesn't "
                    + "describe a valid layout"
            case let .truncated(needed, available):
                return "The image ends early: \(needed) bytes were needed at offset \(available)"
            case let .metadataRegionNotEmpty(offset):
                return "Bytes 0x200-0x21B of this ISO aren't zero (first at "
                    + "\(String(format: "0x%X", offset))), and NKit writes its header block over them. "
                    + "Shrinking would lose data that can't be restored."
            case let .invalidJunkOverrideID(id):
                return "Junk-override Game ID \"\(id)\" isn't four ASCII characters"
            case let .restoredImageCRCMismatch(expected, actual):
                return "The restored image's CRC-32 is "
                    + "\(String(format: "0x%08X", actual)) where NKit recorded "
                    + "\(String(format: "0x%08X", expected)) for the original disc, so the restore is "
                    + "wrong and has been discarded."
            case let .unencodableGap(offset, length):
                return "The \(length)-byte gap at \(String(format: "0x%X", offset)) is neither junk nor "
                    + "a single fill byte, and its length isn't a multiple of "
                    + "\(NKitGCImage.gapBlockSize), so no gap encoding can reproduce it."
            }
        }
    }

    // MARK: - Dump

    /// Restore a raw GameCube ISO from an NKit image.
    ///
    /// The result is checked against the CRC-32 NKit recorded for the
    /// original disc before it is returned, so a restore that isn't
    /// that disc throws rather than handing back a plausible-looking
    /// image.
    public static func dump(nkit: GoDReadable) throws -> GoDData {
        guard var discHeader = nkit.read(atAddress: 0, length: NKitGCImage.discHeaderSize)?.rawBytes,
              discHeader.count == NKitGCImage.discHeaderSize else {
            throw Error.notAnNKitGCImage
        }
        // NKit leaves the disc header alone apart from the two Wii flag
        // bytes, so the disc magic still says which platform this is.
        guard NKitGCImage.readUInt32(discHeader, at: 0x18) != 0x5D1C_9EA3 else {
            throw Error.wiiNotSupported
        }
        let header = try NKitHeader(binary: nkit, platform: .gamecube)
        let imageSize = Int(header.originalImageSize)
        // The NKit block goes back to zero: on a GameCube disc it is
        // padding inside the game-title field. Seven words, matching
        // what NKit's own reader clears.
        for word in stride(from: 0x200, through: 0x218, by: 4) {
            NKitGCImage.writeUInt32(0, into: &discHeader, at: word)
        }

        let junkID: [UInt8] = try {
            if let override = header.junkOverrideID {
                let bytes = Array(override.utf8)
                guard bytes.count >= 4 else { throw Error.invalidJunkOverrideID(override) }
                return Array(bytes.prefix(4))
            }
            return Array(discHeader[0 ..< 4])
        }()
        let junk = JunkStream(
            gameID: junkID,
            disc: discHeader[6],
            length: NKitGCImage.gamecubeDiscSize
        )

        let mainDolAddress = Int(NKitGCImage.readUInt32(discHeader, at: 0x420))
        let fstOffset = Int(NKitGCImage.readUInt32(discHeader, at: 0x424))
        let fstSize = Int(NKitGCImage.readUInt32(discHeader, at: 0x428))
        let fstPadded = NKitGCImage.align4(fstSize)
        guard fstOffset >= NKitGCImage.discHeaderSize,
              fstOffset + fstPadded <= nkit.length else {
            throw Error.invalidFSTOffsets
        }

        guard let systemArea = nkit.read(
                atAddress: NKitGCImage.discHeaderSize,
                length: fstOffset - NKitGCImage.discHeaderSize)?.rawBytes,
              var fst = nkit.read(atAddress: fstOffset, length: fstPadded)?.rawBytes else {
            throw Error.notAnNKitGCImage
        }

        let segments = try NKitGCImage.segments(
            fst: fst, fstOffset: fstOffset, fstPaddedSize: fstPadded, imageLength: nkit.length
        )

        // The system area goes out verbatim; the FST is patched with the
        // restored offsets once the walk has derived them, so its bytes
        // are written over afterwards.
        let output = GoDData(byteOrder: .big)
        output.append(GoDData(byteStream: discHeader, byteOrder: .big))
        output.append(GoDData(byteStream: systemArea, byteOrder: .big))
        let fstOutputOffset = output.length
        output.append(GoDData(byteStream: fst, byteOrder: .big))

        var sourcePosition = fstOffset + fstPadded
        var destination = sourcePosition
        var nullsPosition = destination + NKitGCImage.nullsAllowance

        for (index, segment) in segments.enumerated() {
            let file = segment.file
            if index > 0 {
                // Skip any alignment padding the packer left in front of
                // the file.
                if sourcePosition < file.offset { sourcePosition = file.offset }
                if file.offset == mainDolAddress {
                    NKitGCImage.writeUInt32(UInt32(destination), into: &discHeader, at: 0x420)
                }
                if let field = file.offsetField {
                    NKitGCImage.writeUInt32(UInt32(destination), into: &fst, at: field)
                }
                if file.length > 0 {
                    let copied = min(NKitGCImage.align4(file.length), imageSize - destination)
                    try append(nkit, from: sourcePosition, count: copied, to: output)
                    sourcePosition += copied
                    destination += copied
                    nullsPosition = destination + NKitGCImage.nullsAllowance
                }
            }

            guard destination < imageSize else { continue }
            var restoredLength = file.length
            try expandGap(
                segment: segment,
                firstOrLast: index == 0 || index == segments.count - 1,
                nkit: nkit,
                junk: junk,
                output: output,
                sourcePosition: &sourcePosition,
                destination: &destination,
                nullsPosition: &nullsPosition,
                fileLength: &restoredLength
            )
            if index > 0, let field = file.offsetField {
                NKitGCImage.writeUInt32(UInt32(restoredLength), into: &fst, at: field + 4)
            }
        }

        guard destination == imageSize else {
            throw Error.truncated(needed: imageSize, available: destination)
        }

        _ = output.write(GoDData(byteStream: discHeader, byteOrder: .big), atAddress: 0)
        _ = output.write(GoDData(byteStream: fst, byteOrder: .big), atAddress: fstOutputOffset)

        let restoredCRC = crc32(of: output)
        guard restoredCRC == header.originalCRC else {
            throw Error.restoredImageCRCMismatch(expected: header.originalCRC, actual: restoredCRC)
        }
        return output
    }

    /// Expand one gap — and, when the gap stands in for a file whose
    /// content was junk, that file too — appending the original bytes
    /// to `output`.
    private static func expandGap(
        segment: NKitGCImage.Segment,
        firstOrLast: Bool,
        nkit: GoDReadable,
        junk: JunkStream,
        output: GoDData,
        sourcePosition: inout Int,
        destination: inout Int,
        nullsPosition: inout Int,
        fileLength: inout Int
    ) throws {
        guard segment.gapLength != 0 else {
            // A zero-length file leaves the allowance measured from here.
            if segment.file.length == 0 {
                nullsPosition = destination + NKitGCImage.nullsAllowance
            }
            return
        }

        var head = try readUInt32(nkit, at: sourcePosition)
        sourcePosition += 4
        var size = Int(head & 0xFFFF_FFFC)
        var type = NKitGapEncoding.GapType(rawValue: head & 0b11) ?? .allJunk
        if size == 0xFFFF_FFFC {
            // Only reachable on Wii, where a gap can exceed 32 bits.
            let extra = try readUInt32(nkit, at: sourcePosition)
            sourcePosition += 4
            size = 0xFFFF_FFFC + Int(extra)
        }

        if type == .junkFile {
            // The file's content was junk, so the packer dropped it and
            // recorded its length here instead. Its leading zero count
            // rides in the header's spare bits.
            nullsPosition = min(nullsPosition - destination, 0)
            let nulls = Int((head & 0xFC) >> 2)
            let declared = try readUInt32(nkit, at: sourcePosition)
            sourcePosition += 4
            fileLength = Int(declared)
            let padded = NKitGCImage.align4(Int(declared))
            appendZeros(nulls, to: output)
            appendJunk(junk, from: destination + nulls, count: padded - nulls, to: output)
            destination += padded

            if segment.gapLength <= 8 { return }
            head = try readUInt32(nkit, at: sourcePosition)
            sourcePosition += 4
            size = Int(head & 0xFFFF_FFFC)
            type = NKitGapEncoding.GapType(rawValue: head & 0b11) ?? .allJunk
        } else if segment.file.length == 0 {
            nullsPosition = destination + NKitGCImage.nullsAllowance
        }

        switch type {
        case .allJunk:
            let nulls = NKitGCImage.leadingNulls(
                gapSize: size, position: destination,
                nullsPos: nullsPosition, firstOrLast: firstOrLast
            )
            appendZeros(nulls, to: output)
            appendJunk(junk, from: destination + nulls, count: size - nulls, to: output)
            destination += size

        case .allScrubbed:
            appendZeros(size, to: output)
            destination += size

        case .mixed, .junkFile:
            var remaining = size
            var fillByte: UInt8 = 0
            var kind = NKitGapEncoding.MixedBlockKind.junk
            while remaining > 0 {
                let word = try readUInt32(nkit, at: sourcePosition)
                sourcePosition += 4
                let rawKind = (word >> 30) & 0b11
                let isRepeat = rawKind == NKitGapEncoding.MixedBlockKind.repeatPrevious.rawValue
                if !isRepeat {
                    kind = NKitGapEncoding.MixedBlockKind(rawValue: rawKind) ?? .junk
                }
                var count = Int(word & 0x3FFF_FFFF)
                let written: Int
                switch kind {
                case .nonJunk:
                    written = min(count * NKitGCImage.gapBlockSize, remaining)
                    try append(nkit, from: sourcePosition, count: written, to: output)
                    sourcePosition += written
                case .byteFill:
                    if !isRepeat {
                        fillByte = UInt8(truncatingIfNeeded: count)
                        count >>= 8
                    }
                    written = min(count * NKitGCImage.gapBlockSize, remaining)
                    appendFill(fillByte, written, to: output)
                case .junk, .repeatPrevious:
                    written = min(count * NKitGCImage.gapBlockSize, remaining)
                    // The allowance is re-measured per block, and against
                    // the bytes still to come rather than this block's
                    // size — NKit's own condition, kept verbatim.
                    let maxNulls = max(0, nullsPosition - destination)
                    let nulls: Int
                    if remaining < maxNulls {
                        nulls = written
                    } else {
                        nulls = (written >= NKitGCImage.largeGapThreshold && !firstOrLast) ? 0 : maxNulls
                    }
                    appendZeros(nulls, to: output)
                    appendJunk(junk, from: destination + nulls, count: written - nulls, to: output)
                }
                guard written > 0 else { throw Error.invalidFSTOffsets }
                remaining -= written
                destination += written
            }
        }
    }

    // MARK: - Build

    /// Shrink a raw GameCube ISO into an NKit image.
    ///
    /// `junkOverrideID` seeds the junk PRNG with a Game ID other than
    /// the disc's own, for the discs whose padding was written under a
    /// different ID; it is recorded in the header so a restore reads
    /// the same stream. Pass nil for the normal case.
    public static func build(iso: GoDReadable, junkOverrideID: String? = nil) throws -> GoDData {
        guard var discHeader = iso.read(atAddress: 0, length: NKitGCImage.discHeaderSize)?.rawBytes,
              discHeader.count == NKitGCImage.discHeaderSize else {
            throw Error.notAGameCubeISO
        }
        guard NKitGCImage.readUInt32(discHeader, at: 0x18) != 0x5D1C_9EA3 else {
            throw Error.wiiNotSupported
        }
        guard NKitGCImage.readUInt32(discHeader, at: 0x1C) == 0xC233_9F3D else {
            throw Error.notAGameCubeISO
        }
        if Array(discHeader[NKitHeader.blockOffset ..< NKitHeader.blockOffset + NKitHeader.magic.count])
            == NKitHeader.magic {
            throw Error.alreadyNKit
        }
        // The NKit header block lands on 0x200-0x21B, which is padding
        // inside the game-title field on a real disc. Anything else
        // there is data a restore has nowhere to recover from.
        for offset in 0x200 ..< 0x200 + 0x1C where discHeader[offset] != 0 {
            throw Error.metadataRegionNotEmpty(firstNonZeroOffset: offset)
        }

        let junkID: [UInt8]
        if let override = junkOverrideID {
            let bytes = Array(override.utf8)
            guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
                throw Error.invalidJunkOverrideID(override)
            }
            junkID = bytes
        } else {
            junkID = Array(discHeader[0 ..< 4])
        }
        let junk = JunkStream(
            gameID: junkID,
            disc: discHeader[6],
            length: NKitGCImage.gamecubeDiscSize
        )

        let imageSize = iso.length
        let originalDolAddress = Int(NKitGCImage.readUInt32(discHeader, at: 0x420))
        var mainDolAddress = originalDolAddress
        let fstOffset = Int(NKitGCImage.readUInt32(discHeader, at: 0x424))
        let fstSize = Int(NKitGCImage.readUInt32(discHeader, at: 0x428))
        let fstPadded = NKitGCImage.align4(fstSize)
        guard fstOffset >= NKitGCImage.discHeaderSize, fstOffset + fstPadded <= imageSize else {
            throw Error.invalidFSTOffsets
        }

        guard let systemArea = iso.read(
                atAddress: NKitGCImage.discHeaderSize,
                length: fstOffset - NKitGCImage.discHeaderSize)?.rawBytes,
              var fst = iso.read(atAddress: fstOffset, length: fstPadded)?.rawBytes else {
            throw Error.notAGameCubeISO
        }

        let segments = try NKitGCImage.segments(
            fst: fst, fstOffset: fstOffset, fstPaddedSize: fstPadded, imageLength: imageSize
        )

        let output = GoDData(byteOrder: .big)
        output.append(GoDData(byteStream: discHeader, byteOrder: .big))
        output.append(GoDData(byteStream: systemArea, byteOrder: .big))
        let fstOutputOffset = output.length
        output.append(GoDData(byteStream: fst, byteOrder: .big))

        var sourcePosition = fstOffset + fstPadded
        var destination = sourcePosition
        var nullsPosition = sourcePosition + NKitGCImage.nullsAllowance

        for (index, segment) in segments.enumerated() {
            let file = segment.file
            if index > 0 {
                // Only the file that *is* main.dol moves the pointer, and
                // only once: after it has moved, the new value could
                // coincide with a later file's position.
                if sourcePosition == mainDolAddress, mainDolAddress == originalDolAddress {
                    mainDolAddress = destination
                }
                if let field = file.offsetField {
                    NKitGCImage.writeUInt32(UInt32(destination), into: &fst, at: field)
                }
                if file.length > 0 {
                    let copied = min(NKitGCImage.align4(file.length), imageSize - sourcePosition)
                    try append(iso, from: sourcePosition, count: copied, to: output)
                    sourcePosition += copied
                    destination += copied
                    nullsPosition = sourcePosition + NKitGCImage.nullsAllowance
                }
            }

            guard segment.gapLength != 0 else {
                if file.length == 0 {
                    nullsPosition = sourcePosition + NKitGCImage.nullsAllowance
                }
                continue
            }
            let nulls = NKitGCImage.leadingNulls(
                gapSize: segment.gapLength, position: sourcePosition,
                nullsPos: nullsPosition, firstOrLast: index == 0 || index == segments.count - 1
            )
            let encoded = try encodeGap(
                iso: iso, at: sourcePosition, length: segment.gapLength, nulls: nulls, junk: junk
            )
            output.append(GoDData(byteStream: encoded, byteOrder: .big))
            sourcePosition += segment.gapLength
            destination += encoded.count
        }

        // The image is padded out to a whole DVD sector.
        if destination % NKitGCImage.imageAlignment != 0 {
            appendZeros(NKitGCImage.imageAlignment - destination % NKitGCImage.imageAlignment, to: output)
        }

        NKitGCImage.writeUInt32(UInt32(mainDolAddress), into: &discHeader, at: 0x420)
        _ = output.write(GoDData(byteStream: fst, byteOrder: .big), atAddress: fstOutputOffset)

        var header = NKitHeader(platform: .gamecube)
        header.originalCRC = crc32(of: iso)
        header.crcForce = 0
        header.originalImageSize = UInt64(imageSize)
        header.junkOverrideID = junkOverrideID
        let headerBlock = GoDData(byteStream: discHeader, byteOrder: .big)
        header.write(into: headerBlock)
        _ = output.write(headerBlock, atAddress: 0)

        // With the force slot left zero above, solve for the word that
        // makes the shrunk file's own CRC-32 equal the original disc's,
        // so a Redump hash matches without restoring first.
        let forceOffset = UInt64(NKitHeader.blockOffset + 0x0C)
        let force = CRCForce.calculate(
            currentCRC: crc32(of: output),
            length: UInt64(output.length),
            newCRC: header.originalCRC,
            offset: forceOffset
        )
        _ = output.write(force, atAddress: Int(forceOffset))
        return output
    }

    /// Encode one gap, choosing the smallest representation that
    /// reproduces its bytes exactly. `nulls` is how many leading zeros
    /// a junk run is allowed here.
    ///
    /// Read in windows rather than whole: a gap can be hundreds of
    /// megabytes, and `JunkStream` regenerates a 0x40000-byte block per
    /// call, so asking it for one 0x100 block at a time costs a full
    /// block generation per 256 bytes. Windowing turned a 47-minute
    /// build of a real disc into seconds.
    private static func encodeGap(
        iso: GoDReadable,
        at offset: Int,
        length: Int,
        nulls: Int,
        junk: JunkStream
    ) throws -> [UInt8] {
        guard length % 4 == 0 else { throw Error.unencodableGap(at: offset, length: length) }
        // A multiple of both the 0x100 block and the PRNG's own block, so
        // a window never splits either.
        let window = 0x10_0000

        // One pass to classify the whole gap, stopping as soon as it can
        // be neither pure junk nor pure zeros.
        var isAllJunk = true
        var isAllZero = true
        var position = 0
        while position < length, isAllJunk || isAllZero {
            let take = min(window, length - position)
            guard let chunk = iso.read(atAddress: offset + position, length: take)?.rawBytes else {
                throw Error.truncated(needed: take, available: offset + position)
            }
            if isAllZero, !chunk.allSatisfy({ $0 == 0 }) { isAllZero = false }
            if isAllJunk {
                let expected = junk.read(at: UInt64(offset + position), count: take)
                for index in 0 ..< take where chunk[index] != (position + index < nulls ? 0 : expected[index]) {
                    isAllJunk = false
                    break
                }
            }
            position += take
        }
        if isAllJunk { return NKitGapEncoding.encode(.allJunk(length: UInt64(length))) }
        if isAllZero { return NKitGapEncoding.encode(.allScrubbed(length: UInt64(length))) }

        // Anything else has to be described block by block, and a block
        // is 0x100 bytes — so a gap that doesn't tile into them can't be
        // written at all rather than written wrongly.
        guard length % NKitGCImage.gapBlockSize == 0 else {
            throw Error.unencodableGap(at: offset, length: length)
        }
        var blocks: [NKitGapEncoding.MixedBlock] = []
        position = 0
        while position < length {
            let take = min(window, length - position)
            guard let chunk = iso.read(atAddress: offset + position, length: take)?.rawBytes else {
                throw Error.truncated(needed: take, available: offset + position)
            }
            let expected = junk.read(at: UInt64(offset + position), count: take)
            var index = 0
            while index < take {
                let upper = index + NKitGCImage.gapBlockSize
                let block = Array(chunk[index ..< upper])
                if block.elementsEqual(expected[index ..< upper]) {
                    append(.junk(count: 1), to: &blocks)
                } else if let fill = block.first, block.allSatisfy({ $0 == fill }) {
                    append(.byteFill(byte: fill, count: 1), to: &blocks)
                } else {
                    append(.nonJunk(bytes: block), to: &blocks)
                }
                index = upper
            }
            position += take
        }
        return NKitGapEncoding.encode(.mixed(length: UInt64(length), blocks: blocks))
    }

    /// Merge a one-block run into the previous block where the encoding
    /// allows it, so a run of junk becomes one entry rather than many.
    private static func append(
        _ block: NKitGapEncoding.MixedBlock,
        to blocks: inout [NKitGapEncoding.MixedBlock]
    ) {
        switch (blocks.last, block) {
        case let (.junk(previous), .junk(count)):
            blocks[blocks.count - 1] = .junk(count: previous + count)
        case let (.byteFill(previousByte, previous), .byteFill(byte, count)) where previousByte == byte:
            blocks[blocks.count - 1] = .byteFill(byte: byte, count: previous + count)
        case let (.nonJunk(previous), .nonJunk(bytes)):
            blocks[blocks.count - 1] = .nonJunk(bytes: previous + bytes)
        default:
            blocks.append(block)
        }
    }

    // MARK: - Output helpers

    private static func append(_ source: GoDReadable, from offset: Int, count: Int, to output: GoDData) throws {
        guard count > 0 else { return }
        guard let chunk = source.read(atAddress: offset, length: count), chunk.length == count else {
            throw Error.truncated(needed: count, available: offset)
        }
        output.append(chunk)
    }

    private static func appendZeros(_ count: Int, to output: GoDData) {
        appendFill(0, count, to: output)
    }

    private static func appendFill(_ byte: UInt8, _ count: Int, to output: GoDData) {
        guard count > 0 else { return }
        let chunkSize = 0x10_0000
        var written = 0
        while written < count {
            let take = min(chunkSize, count - written)
            output.append(GoDData(byteStream: [UInt8](repeating: byte, count: take), byteOrder: .big))
            written += take
        }
    }

    private static func appendJunk(_ junk: JunkStream, from offset: Int, count: Int, to output: GoDData) {
        guard count > 0 else { return }
        let chunkSize = 0x10_0000
        var written = 0
        while written < count {
            let take = min(chunkSize, count - written)
            let bytes = junk.read(at: UInt64(offset + written), count: take)
            output.append(GoDData(byteStream: bytes, byteOrder: .big))
            written += take
        }
    }

    private static func readUInt32(_ source: GoDReadable, at offset: Int) throws -> UInt32 {
        guard let bytes = source.read(atAddress: offset, length: 4)?.rawBytes, bytes.count == 4 else {
            throw Error.truncated(needed: 4, available: offset)
        }
        return NKitGCImage.readUInt32(bytes, at: 0)
    }

    /// CRC-32 over a whole image, read a megabyte at a time so a 1.4 GB
    /// disc doesn't get copied into one `[UInt8]` to be hashed.
    private static func crc32(of binary: GoDReadable) -> UInt32 {
        let chunkSize = 0x10_0000
        var crc: UInt32 = 0xFFFF_FFFF
        var offset = 0
        while offset < binary.length {
            let take = min(chunkSize, binary.length - offset)
            guard let chunk = binary.read(atAddress: offset, length: take) else { break }
            crc = CRC32.update(crc, bytes: chunk.rawBytes)
            offset += take
        }
        return crc ^ 0xFFFF_FFFF
    }
}
