//
//  IPSPatchView.swift
//
//  An IPS patch, as a readable over the target it was planned against.
//
//  A record's literal bytes are the target's own, so they are read from it
//  when a reader asks rather than copied here. Same shape as `UPSPatchView`:
//  the layout is fixed in `init`, the bytes are derived.
//

import Foundation

public final class IPSPatchView: GoDReadable {

    private struct Segment {
        let patchStart: Int
        /// Offset and size fields, and for a run its length and byte.
        let header: [UInt8]
        let entry: IPSPatch.Plan.Entry

        var payloadStart: Int { patchStart + header.count }
        /// A run stores its bytes in the header; a literal follows it.
        var payloadLength: Int { entry.runByte == nil ? entry.length : 0 }
        var end: Int { payloadStart + payloadLength }
    }

    private let target: GoDReadable
    private let segments: [Segment]
    private let prefix: [UInt8]
    private let suffix: [UInt8]
    private let suffixStart: Int

    public let length: Int
    public var byteOrder: ByteOrder { .big }

    public init(target: GoDReadable, plan: IPSPatch.Plan) {
        self.target = target
        self.prefix = IPSPatch.magic

        var segments = [Segment]()
        segments.reserveCapacity(plan.entries.count)
        var patchOffset = prefix.count
        for entry in plan.entries {
            var header = IPSPatchView.threeBytes(entry.offset)
            if let runByte = entry.runByte {
                header += [0, 0]                                     // size 0 marks a run
                header += IPSPatchView.twoBytes(entry.length)
                header += [runByte]
            } else {
                header += IPSPatchView.twoBytes(entry.length)
            }
            let segment = Segment(patchStart: patchOffset, header: header, entry: entry)
            segments.append(segment)
            patchOffset = segment.end
        }
        self.segments = segments

        var suffix = IPSPatch.terminator
        if let truncation = plan.truncation {
            suffix += IPSPatchView.threeBytes(truncation)
        }
        self.suffix = suffix
        self.suffixStart = patchOffset
        self.length = patchOffset + suffix.count
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
            if cursor >= suffixStart {
                let offset = cursor - suffixStart
                bytes += suffix[offset ..< offset + (end - cursor)]
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
            let targetOffset = segment.entry.offset + (cursor - segment.payloadStart)
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

    private static func threeBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func twoBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
