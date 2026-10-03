//
//  BPSPatchView.swift
//
//  A BPS patch, as a readable over the target it was planned against.
//
//  Literal bytes are the target's own and are read from it on demand, so the
//  patch costs its run list. Same shape as `UPSPatchView` and `IPSPatchView`.
//

import Foundation

public final class BPSPatchView: GoDReadable {

    private struct Segment {
        let patchStart: Int
        let header: [UInt8]
        let run: BPSPatch.Plan.Run

        var payloadStart: Int { patchStart + header.count }
        /// A shared run names source bytes and carries none of its own.
        var payloadLength: Int { run.sharedWithSource ? 0 : run.range.count }
        var end: Int { payloadStart + payloadLength }
    }

    private let target: GoDReadable
    private let prefix: [UInt8]
    private let segments: [Segment]
    private let footer: [UInt8]
    private let footerStart: Int

    public let length: Int
    public var byteOrder: ByteOrder { .big }

    /// - Parameter patchChecksum: as for `UPSPatchView`, it can only be known
    ///   once the rest of the patch exists — `BPSPatchCodec.createPatch` builds
    ///   the view twice.
    public init(target: GoDReadable, plan: BPSPatch.Plan, patchChecksum: UInt32) {
        self.target = target

        var prefix = BPSPatch.magic
        prefix += PatchVariableLengthInteger.encode(UInt64(plan.sourceSize))
        prefix += PatchVariableLengthInteger.encode(UInt64(plan.targetSize))
        prefix += PatchVariableLengthInteger.encode(0)   // no metadata
        self.prefix = prefix

        var segments = [Segment]()
        segments.reserveCapacity(plan.runs.count)
        var patchOffset = prefix.count
        for run in plan.runs {
            // command 0 = SourceRead, 1 = TargetRead; the length is stored one
            // less, since a zero-length action would say nothing.
            let command: UInt64 = run.sharedWithSource ? 0 : 1
            let header = PatchVariableLengthInteger.encode(UInt64(run.range.count - 1) << 2 | command)
            let segment = Segment(patchStart: patchOffset, header: header, run: run)
            segments.append(segment)
            patchOffset = segment.end
        }
        self.segments = segments

        self.footerStart = patchOffset
        self.footer = BPSPatchView.littleEndianBytes(plan.sourceChecksum)
            + BPSPatchView.littleEndianBytes(plan.targetChecksum)
            + BPSPatchView.littleEndianBytes(patchChecksum)
        self.length = patchOffset + BPSPatch.footerLength
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
            let take = min(end, segment.end) - cursor
            let targetOffset = segment.run.range.lowerBound + (cursor - segment.payloadStart)
            guard let payload = target.read(atAddress: targetOffset, length: take), payload.length == take else {
                return nil
            }
            bytes += payload.rawBytes
            cursor += take
        }
        guard bytes.count == count else { return nil }
        return GoDData(byteStream: bytes, byteOrder: byteOrder)
    }

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
