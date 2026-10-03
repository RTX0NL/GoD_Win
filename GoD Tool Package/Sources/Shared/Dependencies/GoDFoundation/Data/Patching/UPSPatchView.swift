//
//  UPSPatchView.swift
//
//  A UPS patch, as a readable over the two files it describes.
//
//  The hunk payload is `source ^ target`, so it is derived rather than
//  stored: this view holds the layout — where each hunk sits in the patch,
//  and which output positions it covers — and computes the bytes when a
//  reader asks for them. Creating a patch between two disc images therefore
//  costs the run list, whatever the patch's own size turns out to be.
//
//  The layout is fixed in `init`, because every later question ("which hunk
//  is at patch offset N?") is answered against it, and because a patch's own
//  length is the sum of its hunks' variable-width offsets — not something
//  that can be derived a byte at a time.
//

import Foundation

public final class UPSPatchView: GoDReadable {

    /// One hunk's place in the patch: its encoded relative offset, the output
    /// positions its payload covers, and (implicitly) the terminating zero.
    private struct Segment {
        let patchStart: Int
        let header: [UInt8]
        let run: Range<Int>

        var payloadStart: Int { patchStart + header.count }
        var terminatorOffset: Int { payloadStart + run.count }
        var end: Int { terminatorOffset + 1 }
    }

    private let source: GoDReadable
    private let target: GoDReadable
    private let sourceSize: Int
    private let targetSize: Int
    private let prefix: [UInt8]
    private let segments: [Segment]
    private let footer: [UInt8]
    private let footerStart: Int

    public let length: Int
    public var byteOrder: ByteOrder { .big }

    /// - Parameter patchChecksum: the CRC-32 the patch stores for itself,
    ///   which can only be known once the rest of the bytes exist. Build the
    ///   view once with a placeholder, checksum its first `length - 4` bytes,
    ///   then build it again — `UPSPatchCodec.createPatch` is that dance, and
    ///   is what callers should use.
    public init(source: GoDReadable, target: GoDReadable, plan: UPSPatch.Plan, patchChecksum: UInt32) {
        self.source = source
        self.target = target
        self.sourceSize = plan.sourceSize
        self.targetSize = plan.targetSize

        var prefix = UPSPatch.magic
        prefix += PatchVariableLengthInteger.encode(UInt64(plan.sourceSize))
        prefix += PatchVariableLengthInteger.encode(UInt64(plan.targetSize))
        self.prefix = prefix

        var segments = [Segment]()
        segments.reserveCapacity(plan.runs.count)
        var patchOffset = prefix.count
        // Offsets are relative to the position after the previous hunk's
        // terminator, which is why the +1 is here and not only in the span.
        var position = 0
        for run in plan.runs {
            let header = PatchVariableLengthInteger.encode(UInt64(run.lowerBound - position))
            let segment = Segment(patchStart: patchOffset, header: header, run: run)
            segments.append(segment)
            patchOffset = segment.end
            position = run.upperBound + 1
        }
        self.segments = segments

        self.footerStart = patchOffset
        self.footer = UPSPatchView.littleEndianBytes(plan.sourceChecksum)
            + UPSPatchView.littleEndianBytes(plan.targetChecksum)
            + UPSPatchView.littleEndianBytes(patchChecksum)
        self.length = patchOffset + UPSPatch.footerLength
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= length else { return nil }
        guard count > 0 else { return GoDData(byteOrder: byteOrder) }
        let end = start + count

        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        var cursor = start

        while cursor < end {
            if cursor < prefix.count {
                let take = min(end, prefix.count) - cursor
                bytes += prefix[cursor ..< cursor + take]
                cursor += take
                continue
            }
            if cursor >= footerStart {
                let offset = cursor - footerStart
                bytes += footer[offset ..< offset + (end - cursor)]
                cursor = end
                continue
            }
            guard let index = segmentIndex(containing: cursor) else { return nil }
            let segment = segments[index]
            if cursor < segment.payloadStart {
                let offset = cursor - segment.patchStart
                let take = min(end, segment.payloadStart) - cursor
                bytes += segment.header[offset ..< offset + take]
                cursor += take
                continue
            }
            if cursor < segment.terminatorOffset {
                let take = min(end, segment.terminatorOffset) - cursor
                let outputStart = segment.run.lowerBound + (cursor - segment.payloadStart)
                guard let xor = xorBytes(at: outputStart, count: take) else { return nil }
                bytes += xor
                cursor += take
                continue
            }
            // The zero that closes the hunk.
            bytes.append(0)
            cursor += 1
        }
        guard bytes.count == count else { return nil }
        return GoDData(byteStream: bytes, byteOrder: byteOrder)
    }

    /// `source ^ target` over `count` output positions, each file reading as
    /// zero past its own end.
    private func xorBytes(at offset: Int, count: Int) -> [UInt8]? {
        guard let sourceBytes = window(source, at: offset, count: count, limit: sourceSize),
              let targetBytes = window(target, at: offset, count: count, limit: targetSize) else {
            return nil
        }
        var out = [UInt8](repeating: 0, count: count)
        for index in 0 ..< count {
            out[index] = sourceBytes[index] ^ targetBytes[index]
        }
        return out
    }

    private func window(_ readable: GoDReadable, at offset: Int, count: Int, limit: Int) -> [UInt8]? {
        let real = max(0, min(count, limit - offset))
        guard real > 0 else { return [UInt8](repeating: 0, count: count) }
        guard let chunk = readable.read(atAddress: offset, length: real), chunk.length == real else {
            return nil
        }
        guard real < count else { return chunk.rawBytes }
        return chunk.rawBytes + [UInt8](repeating: 0, count: count - real)
    }

    /// The segment whose bytes include patch offset `offset`.
    private func segmentIndex(containing offset: Int) -> Int? {
        var low = 0
        var high = segments.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let segment = segments[middle]
            if offset < segment.patchStart {
                high = middle - 1
            } else if offset >= segment.end {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }

    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }
}
