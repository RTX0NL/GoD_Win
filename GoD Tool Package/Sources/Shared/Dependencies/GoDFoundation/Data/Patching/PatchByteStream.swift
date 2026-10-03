//
//  PatchByteStream.swift
//
//  Sequential byte reads over a `GoDReadable`, a window at a time. Shared by
//  the formats whose fields are variable-length — UPS and BPS.
//
//  Parsing a patch is a strictly forward walk of variable-length fields, so
//  it cannot be expressed as reads at known offsets. Going through
//  `read(atAddress:length:)` per byte would allocate a `GoDData` for each
//  one — a patch between two discs has hundreds of millions of bytes — so
//  this holds one window of raw bytes and refills it.
//

import Foundation

final class PatchByteStream {

    private let source: GoDReadable
    private let end: Int
    private let windowSize: Int

    private var window: [UInt8] = []
    private var windowStart: Int = 0

    /// How far the walk has got, as an absolute offset into `source`.
    private(set) var offset: Int

    init(source: GoDReadable, start: Int, end: Int, windowSize: Int = 1 << 16) {
        self.source = source
        self.end = min(end, source.length)
        self.windowSize = max(1, windowSize)
        self.offset = start
        self.windowStart = start
    }

    var isAtEnd: Bool { offset >= end }

    /// The next byte, or nil at the end of the range.
    func readByte() -> UInt8? {
        guard offset < end, fillWindow() else { return nil }
        let byte = window[offset - windowStart]
        offset += 1
        return byte
    }

    /// Consume a run of non-zero bytes and the zero that terminates it,
    /// returning the length of the run.
    ///
    /// This is a hunk's payload: a UPS hunk is a run of XOR bytes closed by a
    /// `0x00`, and the terminator counts against the output position, so the
    /// caller needs the run length and the fact that it was terminated.
    ///
    /// - Returns: nil when the range ends before a zero byte is found, which
    ///   is a malformed patch rather than an empty hunk.
    func readZeroTerminatedRun() -> Int? {
        var length = 0
        while offset < end {
            guard fillWindow() else { return nil }
            var index = offset - windowStart
            let limit = min(window.count, end - windowStart)
            while index < limit {
                if window[index] == 0 {
                    offset = windowStart + index + 1
                    return length
                }
                index += 1
                length += 1
            }
            offset = windowStart + index
        }
        return nil
    }

    /// Step past `count` bytes without reading them — a BPS literal run, or a
    /// metadata block.
    func skip(_ count: Int) {
        offset = min(end, offset + max(0, count))
    }

    /// Make sure `offset` is inside the window, reading the next one if not.
    private func fillWindow() -> Bool {
        if offset >= windowStart, offset < windowStart + window.count {
            return true
        }
        let count = min(windowSize, end - offset)
        guard count > 0, let chunk = source.read(atAddress: offset, length: count), chunk.length > 0 else {
            window = []
            return false
        }
        window = chunk.rawBytes
        windowStart = offset
        return true
    }
}
