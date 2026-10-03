//
//  PatchDiff.swift
//
//  The windowed walk that finds where two files differ, shared by the formats
//  whose patches describe the target's bytes directly — IPS and BPS.
//
//  UPS has its own walk rather than this one, because its question is a
//  different one: a UPS patch stores `source ^ target` over
//  `max(sourceSize, targetSize)` positions, so a byte past the end of the
//  shorter file counts as *equal* when the other file's byte is zero. Here, a
//  byte with no source behind it always has to be written out.
//

import Foundation

enum PatchDiff {

    /// The stretches of `target` that a patch has to carry, ordered and
    /// disjoint: where the two files disagree, plus everything past the end of
    /// the source.
    ///
    /// Only the target's own length is walked. A target shorter than its
    /// source is a truncation, which is each format's own business.
    static func differingRanges(
        source: GoDReadable,
        target: GoDReadable,
        format name: String,
        windowSize: Int = 1 << 22
    ) throws -> [Range<Int>] {
        let sourceSize = source.length
        let coverage = target.length
        let window = max(1, windowSize)

        var ranges = [Range<Int>]()
        var runStart: Int?
        var offset = 0

        while offset < coverage {
            let count = min(window, coverage - offset)
            // One pool per window, or every window's buffers live until the
            // walk ends and a streamed diff peaks at the files' size.
            try autoreleasepool {
                let targetBytes = try read(target, at: offset, count: count, name: name)
                let overlap = max(0, min(count, sourceSize - offset))
                let sourceBytes = try read(source, at: offset, count: overlap, name: name)

                if overlap == count, sourceBytes == targetBytes {
                    if let start = runStart {
                        ranges.append(start ..< offset)
                        runStart = nil
                    }
                    return
                }
                for index in 0 ..< count {
                    let same = index < overlap && sourceBytes[index] == targetBytes[index]
                    if same {
                        if let start = runStart {
                            ranges.append(start ..< (offset + index))
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
            ranges.append(start ..< coverage)
        }
        return ranges
    }

    static func read(
        _ readable: GoDReadable,
        at offset: Int,
        count: Int,
        name: String
    ) throws -> [UInt8] {
        guard count > 0 else { return [] }
        guard let chunk = readable.read(atAddress: offset, length: count), chunk.length == count else {
            throw PatchError.readFailed(format: name, offset: offset, length: count)
        }
        return chunk.rawBytes
    }
}
